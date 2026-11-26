#!/usr/bin/env python3
"""Classificador de comandos do vigia-agy.sh (references/harnesses/agy.md).

Decide se um comando que o agy pediu para rodar pode ser aprovado "uma vez" sem
o coordenador olhar. O Enter executa o comando de verdade, então a regra é
LISTA FECHADA, por palavra, com um leitor de shell próprio que sabe o que
estava entre aspas:

1. Para de cara: `$` (qualquer expansão), crase, quebra de linha, aspas que não
   fecham. Fora de aspas também param `{` `}` `*` `?` `[` `]` (expansão de
   chaves e glob: o bash muda as palavras depois da leitura) e `#` no começo
   de palavra (comentário).
2. Operador só fora de aspas: `|`, `&&`, `||`, `;` separam comandos;
   redirecionamento só `>/dev/null`, `>>/dev/null`, `&>/dev/null`, `>&1`,
   `>&2` e `< arquivo`. Qualquer outro operador para. Um `';'` entre aspas é
   argumento, como no bash.
3. Cada comando precisa estar na tabela e passar pelo validador dele. O build
   pelo build-slot só aceita fases e opções de uma lista.
4. Caminho: nada com `..`; absoluto ou com `~` só dentro das raízes (`--raiz`);
   vale também para o valor colado de opção (`-f/x`, `--x=/y`, listas com `:`).
   Nome de segredo em qualquer palavra, já sem as aspas, para.
5. Variável na frente: só `GLAB_CONFIG_DIR=<dir>` (e `export GLAB_CONFIG_DIR=<dir>`
   sozinho) com <dir> igual a uma `--identidade`; o resto do segmento passa
   pelas regras acima. Qualquer outra variável para.
6. `node <arquivo>.js|.mjs|.cjs`: caminho absoluto (ou `~`) dentro das raízes,
   conferido também pelo caminho resolvido (`realpath`: link que aponta para fora
   para), sem as opções que executam código.
7. `mv <origem> <destino>`: só a entrega atômica, e só dentro de `--escrita`
   (escopo de escrita próprio, separado de `--raiz`, que é de leitura e build).
   Origem: arquivo regular existente, sem link. Destino: inexistente, ou o caso
   exato `.<nome>.tmp` -> `<nome>` no mesmo diretório. Nunca `recursos.json`,
   `pendencias/`, `*.registrada.json`, `*.erro.txt`. Sem `--escrita`, para.
8. Subshell `( … )`: só quando cada comando de dentro passaria sozinho (regra
   recursiva), sem palavra antes ou depois do grupo.

LIMITE: isto evita o acidente de um agente honesto. Não é fronteira contra um
agente hostil: o agy lê qualquer arquivo sem pedir aprovação, e o build e o
`node` executam código que o agente escreve sem aprovação (accept-edits e auto).
A conferência de caminho resolve links na hora da classificação; o arquivo pode
mudar entre a classificação e o Enter (não há trava).

Uso: vigia_agy_classificar.py [--build-slot P]... [--raiz D]... [--escrita D]... [--identidade D]... -- '<comando>'
Imprime `aprova` (saída 0) ou `para: <motivo>` (saída 1).
"""

import argparse
import os
import re
import sys

HOME = os.path.expanduser("~")

SEGREDO = re.compile(
    r"secret|credenc|credential|token|passw|senha|\.env\b|\.pem\b|id_rsa|id_ed25519|id_ecdsa|id_dsa"
    r"|\.ssh\b|\.gnupg|\.kube|kubeconfig|\.docker|\.pgpass|\.netrc|glab-cli|\.config/gh\b|vault"
    r"|\.aws\b|sops|\.age\b|\.p12\b|\.jks\b|keystore|variables",
    re.I,
)
# Forma conferida: javap sobre o jar mais novo de um artefato do ~/.m2.
JAVAP_FIND = re.compile(
    r"""^javap -cp "\$\(find ~/\.m2/repository/((?:[A-Za-z0-9_-][A-Za-z0-9._-]*/)*[A-Za-z0-9_-][A-Za-z0-9._-]*) -name '[A-Za-z0-9*._-]+' \| sort -V \| tail -1\)"(?= )"""
)
JAR_M2 = "@JAR_DO_M2@"
OPERADORES_OK = {"|", "&&", "||", ";"}
CHARS_OP = set("|&;<>()")
EXPANSAO = set("{}*?[]")
GIT_LEITURA = {"rev-parse", "status", "log", "diff", "show", "ls-files", "blame", "grep", "merge-base", "cat-file"}
GIT_PERIGOSAS = ["--output", "--open-files-in-pager", "--ext-diff", "--textconv", "--no-index", "--exec", "--upload-pack", "--receive-pack"]
MAVEN_FASES = {"clean", "validate", "compile", "test-compile", "test", "package", "verify", "install"}
MAVEN_OPCOES = re.compile(r"^(-q|-B|-o|-U|-e|-X|--quiet|--batch-mode|--offline|-ntp|--no-transfer-progress"
                          r"|-D[A-Za-z0-9_.-]+(=[^ ]*)?|-P[A-Za-z0-9_,!-]+|-pl|-am|-T[0-9C.]*|--fail-at-end|-fae)$")
GLAB_API_OK = re.compile(
    r"^(user|projects/[^/?]+(/(merge_requests|pipelines|jobs|issues|repository/(commits|compare|tree|branches|files))"
    r"(/[^?]*)?)?)(\?[A-Za-z0-9_=&.,%-]*)?$"
)


class Para(Exception):
    pass


class Op(str):
    """Operador do shell (fora de aspas)."""


class Sub:
    """Subshell `( … )` já separado: guarda os tokens de dentro."""

    def __init__(self, toks):
        self.toks = toks


MAX_SUBSHELL = 3
VAR_ATRIBUICAO = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\+?=.*", re.S)
NODE_PROIBIDAS = {"-e", "--eval", "-p", "--print", "-r", "--require", "--import", "--loader",
                  "--experimental-loader", "--env-file", "--inspect", "--inspect-brk", "-i", "--interactive"}


# --- leitura do comando ---------------------------------------------------------

def lexar(cmd):
    """Lista de palavras (str) e operadores (Op), como o bash separaria, para o
    subconjunto aceito. Para em tudo que o bash expandiria depois da leitura."""
    toks, cur, i, n = [], None, 0, len(cmd)

    def fecha():
        nonlocal cur
        if cur is not None:
            toks.append(cur)
            cur = None

    while i < n:
        c = cmd[i]
        if c in " \t":
            fecha(); i += 1; continue
        if c == "'":
            j = cmd.find("'", i + 1)
            if j < 0:
                raise Para("aspas simples não fecham")
            cur = (cur or "") + cmd[i + 1:j]; i = j + 1; continue
        if c == '"':
            j, buf = i + 1, ""
            while j < n and cmd[j] != '"':
                if cmd[j] == "\\" and j + 1 < n and cmd[j + 1] in '"\\':
                    buf += cmd[j + 1]; j += 2; continue
                buf += cmd[j]; j += 1
            if j >= n:
                raise Para("aspas duplas não fecham")
            cur = (cur or "") + buf; i = j + 1; continue
        if c == "\\":
            if i + 1 >= n:
                raise Para("barra invertida no fim")
            cur = (cur or "") + cmd[i + 1]; i += 2; continue
        if c in "()":
            if c == "(" and i > 0 and cmd[i - 1] == "(":
                raise Para("'((' é aritmética do bash, não subshell")
            fecha()
            toks.append(Op(c)); i += 1; continue
        if c in CHARS_OP:
            fecha()
            j = i
            while j < n and cmd[j] in CHARS_OP and cmd[j] not in "()":
                j += 1
            toks.append(Op(cmd[i:j])); i = j; continue
        if c in EXPANSAO:
            raise Para(f"'{c}' fora de aspas (expansão do shell)")
        if c == "#" and cur is None:
            raise Para("comentário do shell")
        cur = (cur or "") + c; i += 1
    fecha()
    return toks


def aninha(toks):
    """Troca cada `( … )` do nível de cima por um Sub com os tokens de dentro."""
    saida, i = [], 0
    while i < len(toks):
        t = toks[i]
        if isinstance(t, Op) and t == "(":
            prof, j = 1, i + 1
            while j < len(toks) and prof:
                if isinstance(toks[j], Op) and toks[j] == "(":
                    prof += 1
                elif isinstance(toks[j], Op) and toks[j] == ")":
                    prof -= 1
                j += 1
            if prof:
                raise Para("parêntese que não fecha")
            saida.append(Sub(toks[i + 1:j - 1])); i = j; continue
        if isinstance(t, Op) and t == ")":
            raise Para("parêntese sem abertura")
        saida.append(t); i += 1
    return saida


def segmentos(toks):
    segs, atual, i = [], [], 0
    while i < len(toks):
        t = toks[i]
        prox = toks[i + 1] if i + 1 < len(toks) else None
        if isinstance(t, Op):
            if t in OPERADORES_OK:
                segs.append(atual); atual = []
            elif any(isinstance(x, Sub) for x in atual):
                raise Para(f"redirecionamento ou operador junto de um subshell: {t}")
            elif t in (">", ">>", "&>") and prox == "/dev/null" and not isinstance(prox, Op):
                if atual and atual[-1] in ("1", "2"):
                    atual.pop()
                i += 1
            elif t == ">&" and prox in ("1", "2") and not isinstance(prox, Op):
                if atual and atual[-1] in ("1", "2"):
                    atual.pop()
                i += 1
            elif t == "<" and prox is not None and not isinstance(prox, Op):
                atual.append(("<", prox)); i += 1
            else:
                raise Para(f"operador do shell: {t}")
        else:
            atual.append(t)
        i += 1
    segs.append(atual)
    return segs


# --- caminhos -----------------------------------------------------------------------

def expande_til(p):
    if p == "~" or p.startswith("~/"):
        return HOME + p[1:]
    if p.startswith("~"):
        raise Para(f"caminho de outro usuário ou de pilha: {p}")
    return p


def confere_caminho(p, raizes):
    if not p or p == JAR_M2:
        return
    if "://" in p or p.startswith("//"):
        raise Para(f"URL ou caminho de rede: {p}")
    q = expande_til(p)
    if ".." in q.split("/"):
        raise Para(f"caminho com '..': {p}")
    if q.startswith("/"):
        n = os.path.normpath(q)
        if not any(n == r or n.startswith(r.rstrip("/") + "/") for r in raizes):
            raise Para(f"caminho fora das raízes: {p}")


def valores_da_palavra(t):
    """O que uma palavra pode carregar de caminho: ela mesma; numa opção, o
    valor depois de `=` ou colado à letra (`-f/x`); listas separadas por `:`."""
    if t.startswith("--"):
        vals = [t.split("=", 1)[1]] if "=" in t else []
    elif t.startswith("-") and len(t) > 2:
        vals = [t[2:], t.split("=", 1)[1]] if "=" in t else [t[2:]]
    elif t.startswith("-"):
        vals = []
    else:
        vals = [t]
    saida = []
    for v in vals:
        saida.extend(v.split(":") if ":" in v else [v])
    return saida


def confere_palavra(t, raizes):
    for v in valores_da_palavra(t):
        if "/" in v or v.startswith("~") or v.startswith(".") or "://" in v:
            confere_caminho(v, raizes)


def confere_args(args, raizes, pular=()):
    for i, t in enumerate(args):
        if i not in pular:
            confere_palavra(t, raizes)


def nome_longo_perigoso(a, perigosas):
    """Opção longa que o programa aceita abreviada: `--textc` liga `--textconv`."""
    if not a.startswith("--") or len(a) < 4:
        return False
    nome = a.split("=", 1)[0]
    return any(p.startswith(nome) or nome.startswith(p) for p in perigosas)


def posicionais(args, com_valor):
    idx, i, fim = [], 0, False
    while i < len(args):
        t = args[i]
        if not fim and t == "--":
            fim = True
        elif not fim and t.startswith("-") and t != "-":
            i += com_valor.get(t, 0)
        else:
            idx.append(i)
        i += 1
    return idx


# --- validadores por comando ---------------------------------------------------

def v_sem_args(nome):
    def v(args, raizes):
        if args:
            raise Para(f"{nome} com argumentos")
    return v


def v_cd(args, raizes):
    if len(args) != 1:
        raise Para("cd precisa de exatamente um caminho")
    confere_caminho(args[0], raizes)


def v_generico(args, raizes):
    confere_args(args, raizes)


def v_so_imprime(args, raizes):
    pass


def padrao_primeiro(args, raizes, com_valor):
    """grep/rg: o primeiro posicional é o padrão, a não ser com -e/-f."""
    pos = posicionais(args, com_valor)
    explicito = any(a in ("-e", "-f", "--regexp", "--file") or a.startswith(("--regexp=", "--file=")) or
                    (re.match(r"^-[A-Za-z]*[ef]", a) and not a.startswith("--")) for a in args)
    pular = set()
    if pos and not explicito:
        pular.add(pos[0])
    for i, a in enumerate(args):
        if a in ("-e", "--regexp") and i + 1 < len(args):
            pular.add(i + 1)
    confere_args(args, raizes, pular)


GREP_VALOR = {"-e": 1, "-f": 1, "-A": 1, "-B": 1, "-C": 1, "-m": 1, "--regexp": 1, "--file": 1}


def v_grep(args, raizes):
    padrao_primeiro(args, raizes, GREP_VALOR)


def v_rg(args, raizes):
    for a in args:
        if nome_longo_perigoso(a, ["--pre", "--pre-glob", "--hostname-bin", "--search-zip"]) or a.startswith("--pre"):
            raise Para(f"rg {a} executa programa")
        if re.match(r"^-[A-Za-z]*z", a) and not a.startswith("--"):
            raise Para("rg -z executa descompactador")
    padrao_primeiro(args, raizes, dict(GREP_VALOR, **{"-g": 1, "-t": 1, "-T": 1, "--glob": 1, "--type": 1}))


def v_jq(args, raizes):
    for a in args:
        if a in ("-f", "--from-file") or a.startswith("--from-file") or (re.match(r"^-[A-Za-z]*f", a) and not a.startswith("--")):
            raise Para("jq -f lê o filtro de arquivo")
        if re.search(r"\benv\b|input_filename|\$__loc__", a):
            raise Para("jq lendo o ambiente")
    com_valor = {"--arg": 2, "--argjson": 2, "--rawfile": 2, "--slurpfile": 2, "--indent": 1}
    pos = posicionais(args, com_valor)
    pular = {pos[0]} if pos else set()
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("--rawfile", "--slurpfile") and i + 2 < len(args):
            confere_caminho(args[i + 2], raizes)
            pular.update({i + 1, i + 2})
        elif a in ("--arg", "--argjson") and i + 2 < len(args):
            pular.update({i + 1, i + 2})
        i += 1
    confere_args(args, raizes, pular)


def v_printf(args, raizes):
    if any(a.startswith("-v") for a in args):
        raise Para("printf -v grava variável")


def v_date(args, raizes):
    for a in args:
        if a.startswith("--set") or (a.startswith("-") and not a.startswith("--") and "s" in a[1:]):
            raise Para("date -s muda a hora")
    confere_args(args, raizes)


def v_git(args, raizes):
    if not args or args[0] not in GIT_LEITURA:
        raise Para(f"git fora da leitura: {' '.join(args[:1])}")
    sub, resto = args[0], args[1:]
    for a in resto:
        if nome_longo_perigoso(a, GIT_PERIGOSAS):
            raise Para(f"opção do git que escreve ou executa: {a}")
        if sub == "grep" and re.match(r"^-[^-]*O", a):
            raise Para(f"git grep {a} roda programa sobre os arquivos")
    confere_args(resto, raizes)


def v_find(args, raizes):
    for a in args:
        if re.match(r"^-(exec|ok|delete|fprint|fls)", a):
            raise Para(f"find {a} executa ou escreve")
    confere_args(args, raizes)


SED_FAIXA = re.compile(r"^\d+(,\d+)?p$")


def v_sed(args, raizes):
    if len(args) < 2 or args[0] != "-n" or not SED_FAIXA.match(args[1]):
        raise Para("sed só na forma sed -n 'N,Mp' arquivo")
    for a in args[2:]:
        if a.startswith("-"):
            raise Para(f"sed com opção depois da faixa: {a}")
    confere_args(args[2:], raizes)


def v_sort(args, raizes):
    i = 0
    while i < len(args):
        a = args[i]
        if a.startswith("--"):
            raise Para(f"sort com opção longa: {a}")
        if a.startswith("-") and a != "-":
            corpo = a[1:]
            if corpo[:1] in ("k", "t"):
                if len(corpo) == 1:
                    i += 1
            elif not re.fullmatch(r"[bdfghiMnRrsuVz]+", corpo):
                raise Para(f"sort {a} (só ordena, sem -o)")
        else:
            confere_palavra(a, raizes)
        i += 1


def v_uniq(args, raizes):
    pos = []
    for a in args:
        if a.startswith("-") and a != "-":
            if not re.fullmatch(r"-[cdiuDz]+", a):
                raise Para(f"uniq {a}")
        else:
            pos.append(a)
    if len(pos) > 1:
        raise Para("uniq com arquivo de saída")
    confere_args(pos, raizes)


PS_CAMPOS = {"pid", "ppid", "comm", "etime", "etimes", "stat", "pcpu", "pmem", "rss", "vsz", "lstart", "user"}


def v_ps(args, raizes):
    i, tem_p = 0, False
    while i < len(args):
        a = args[i]
        if a == "-p" and i + 1 < len(args) and re.fullmatch(r"[0-9,]+", args[i + 1]):
            tem_p = True; i += 2
        elif a == "-o" and i + 1 < len(args) and set(args[i + 1].split(",")) <= PS_CAMPOS:
            i += 2
        else:
            raise Para(f"ps só com -p <pid> e -o <campos sem a linha de comando>: {a}")
    if not tem_p:
        raise Para("ps sem -p")


def v_javap(args, raizes):
    for a in args:
        if a.startswith("-J"):
            raise Para("javap -J passa opção à JVM")
    confere_args(args, raizes)


def v_glab(args, raizes):
    if len(args) in (2, 3) and args[0] == "api":
        if len(args) == 3 and args[2] != "--paginate":
            raise Para("glab api só GET: glab api <caminho> [--paginate]")
        if not GLAB_API_OK.match(args[1]):
            raise Para(f"glab api fora dos caminhos de leitura da MR, pipeline e repositório: {args[1]}")
        return
    if len(args) >= 3 and args[:2] == ["mr", "view"] and args[2].isdigit() and args[3:] in ([], ["-F", "json"]):
        return
    raise Para("glab fora de 'api <caminho>' e 'mr view <n>'")


def v_sonar(args, raizes):
    if not (args[:2] == ["qg", "status"] or args[:2] in (["list", "issues"], ["list", "hotspots"])
            or args[:2] in (["issues", "list"], ["hotspot", "list"], ["hotspots", "list"])):
        raise Para("sonar fora de qg status / list issues / list hotspots")
    for a in args:
        if nome_longo_perigoso(a, ["--url", "--host", "--server", "--token"]):
            raise Para(f"sonar {a}")
    confere_args(args, raizes)


def v_taiga(args, raizes):
    if len(args) < 3 or args[0] != "story" or args[1] not in ("get", "comments") or not args[2].isdigit():
        raise Para("taiga fora de 'story get|comments <n>'")
    for a in args:
        if nome_longo_perigoso(a, ["--url"]):
            raise Para("taiga --url")
    confere_args(args[3:], raizes)


def v_herdr(args, raizes):
    if len(args) != 3 or args[:2] != ["agent", "get"]:
        raise Para("herdr fora de 'agent get <nome>'")


def real_dentro(p, bases):
    """`p` (já resolvido) estritamente dentro de alguma base (já resolvida)."""
    return any(p != b and p.startswith(b.rstrip("/") + "/") for b in bases)


def caminho_absoluto_na_raiz(p, raizes, o_que):
    """Caminho absoluto (ou `~`) dentro de uma raiz, também depois de resolver
    links; relativo para."""
    q = expande_til(p)
    if not q.startswith("/"):
        raise Para(f"{o_que}: só caminho absoluto, o diretório de trabalho não é conhecido: {p}")
    confere_caminho(p, raizes)
    reais = [os.path.realpath(r) for r in raizes]
    real = os.path.realpath(q)
    if not any(real == r or real.startswith(r.rstrip("/") + "/") for r in reais):
        raise Para(f"{o_que}: o caminho resolvido sai das raízes (link?): {p} -> {real}")
    return real


def v_node(args, raizes):
    if not args or args[0].startswith("-"):
        raise Para("node só na forma node <arquivo>.js|.mjs|.cjs (sem opção antes do arquivo)")
    if not re.search(r"\.(js|mjs|cjs)$", args[0]):
        raise Para(f"node de arquivo sem extensão .js/.mjs/.cjs: {args[0]}")
    caminho_absoluto_na_raiz(args[0], raizes, "node")
    for a in args[1:]:
        if a.split("=", 1)[0] in NODE_PROIBIDAS:
            raise Para(f"node com {a}")
    confere_args(args[1:], raizes)


def nome_de_controle(p):
    partes = [x for x in p.split("/") if x]
    base = partes[-1] if partes else ""
    return (base == "recursos.json" or base.endswith(".registrada.json") or base.endswith(".erro.txt")
            or "pendencias" in partes)


def v_mv(args, escritas):
    """Só a entrega atômica dentro de uma --escrita (ver o docstring do módulo)."""
    if not escritas:
        raise Para("mv sem --escrita: o escopo de escrita não foi dado")
    pos = []
    for a in args:
        if a in ("-f", "-n"):
            continue
        if a.startswith("-"):
            raise Para(f"mv com opção fora de -f/-n: {a}")
        pos.append(a)
    if len(pos) != 2:
        raise Para("mv só com uma origem e um destino")
    for p in pos:
        q = expande_til(p)
        if not q.startswith("/"):
            raise Para(f"mv: só caminho absoluto, o diretório de trabalho não é conhecido: {p}")
        if ".." in q.split("/"):
            raise Para(f"mv: caminho com '..': {p}")
        if nome_de_controle(os.path.normpath(q)):
            raise Para(f"mv: arquivo de controle da US (recursos.json, pendencias/, *.registrada.json, *.erro.txt): {p}")
    src, dst = os.path.normpath(expande_til(pos[0])), os.path.normpath(expande_til(pos[1]))
    if os.path.islink(src) or not os.path.isfile(src):
        raise Para(f"mv: a origem precisa ser um arquivo regular existente, sem link: {pos[0]}")
    rsrc = os.path.realpath(src)
    rdst = os.path.join(os.path.realpath(os.path.dirname(dst)), os.path.basename(dst))
    if nome_de_controle(rsrc) or nome_de_controle(rdst):
        raise Para("mv: arquivo de controle da US depois de resolver links")
    bases = [os.path.realpath(e) for e in escritas]
    if not any(real_dentro(rsrc, [b]) and real_dentro(rdst, [b]) for b in bases):
        raise Para(f"mv: origem e destino precisam estar na mesma --escrita (caminho resolvido): {pos[0]} -> {pos[1]}")
    if rsrc == rdst:
        raise Para("mv: origem e destino iguais")
    if os.path.lexists(rdst):
        entrega = (os.path.dirname(rsrc) == os.path.dirname(rdst)
                   and os.path.basename(rsrc) == "." + os.path.basename(rdst) + ".tmp")
        if not entrega or (os.path.isdir(rdst) and not os.path.islink(rdst)):
            raise Para(f"mv: o destino já existe e não é a entrega atômica .<nome>.tmp -> <nome>: {pos[1]}")


COMANDOS = {
    "cd": v_cd, "true": v_sem_args("true"), "pwd": v_sem_args("pwd"),
    "git": v_git, "grep": v_grep, "rg": v_rg, "jq": v_jq,
    "ls": v_generico, "cat": v_generico, "head": v_generico, "tail": v_generico, "wc": v_generico,
    "stat": v_generico, "du": v_generico, "df": v_so_imprime, "diff": v_generico, "cut": v_generico,
    "tr": v_so_imprime, "which": v_so_imprime, "echo": v_so_imprime, "printf": v_printf, "date": v_date,
    "find": v_find, "sed": v_sed, "sort": v_sort, "uniq": v_uniq, "ps": v_ps, "javap": v_javap,
    "glab": v_glab, "sonar": v_sonar, "taiga": v_taiga, "herdr": v_herdr,
    "node": v_node,
}


def confere_build(tokens, slots, raizes):
    if os.path.normpath(expande_til(tokens[0])) not in slots:
        return False
    resto = tokens[1:]
    if resto[:1] in (["./mvnw"], ["mvn"]):
        for k in range(1, len(resto)):
            a = resto[k]
            if a in MAVEN_FASES or MAVEN_OPCOES.match(a):
                continue
            if resto[k - 1] == "-pl" and re.fullmatch(r"[A-Za-z0-9_.,:-]+", a):
                continue
            raise Para(f"build Maven com {a} (só fases {', '.join(sorted(MAVEN_FASES))} e opções da lista)")
    elif resto[:2] == ["go", "test"] or resto[:2] in (["go", "build"], ["go", "vet"]):
        for a in resto[2:]:
            if re.search(r"exec", a) or a in ("-o",) or a.startswith("-o="):
                raise Para(f"go com {a}")
    elif resto in (["npm", "test"], ["npm", "run", "build"]):
        pass
    elif resto[:3] == ["uv", "run", "pytest"] or resto[:5] == ["uv", "run", "python", "-m", "pytest"]:
        for a in resto:
            if a.startswith("-p") and a != "-p":
                raise Para(f"pytest {a} carrega plugin")
    else:
        raise Para(f"build-slot com comando fora do build: {' '.join(resto[:3])}")
    confere_args(resto, raizes)
    return True


def identidade_valida(valor, identidades):
    """`GLAB_CONFIG_DIR=<valor>`: o valor precisa ser exatamente uma identidade."""
    if ".." in valor.split("/"):
        raise Para(f"GLAB_CONFIG_DIR com '..': {valor}")
    if not valor or not identidades or os.path.normpath(expande_til(valor)) not in identidades:
        raise Para(f"variável na frente do comando fora de GLAB_CONFIG_DIR=<identidade conhecida>: GLAB_CONFIG_DIR={valor}")


def tira_variavel(seg, identidades):
    """Se o segmento abre com `GLAB_CONFIG_DIR=<identidade>` (ou `export …` sozinho),
    devolve o resto; outra variável na frente para."""
    if seg[0] == "export":
        if len(seg) != 2 or not seg[1].startswith("GLAB_CONFIG_DIR="):
            raise Para("export só na forma export GLAB_CONFIG_DIR=<identidade>")
        identidade_valida(seg[1].split("=", 1)[1], identidades)
        return None
    if seg[0].startswith("GLAB_CONFIG_DIR="):
        identidade_valida(seg[0].split("=", 1)[1], identidades)
        if len(seg) == 1:
            raise Para("GLAB_CONFIG_DIR sozinho, sem comando depois")
        return seg[1:]
    if VAR_ATRIBUICAO.fullmatch(seg[0]):
        raise Para(f"variável na frente do comando: {seg[0].split('=', 1)[0]}")
    return seg


def confere_segredo(palavra):
    m = SEGREDO.search(palavra)
    if m:
        raise Para(f"nome de segredo: {m.group(0)}")


def valida_toks(toks, slots, raizes, identidades, escritas, prof=0):
    for seg in segmentos(aninha(toks)):
        if not seg:
            raise Para("comando vazio entre separadores")
        if any(isinstance(t, Sub) for t in seg):
            if len(seg) != 1:
                raise Para("subshell com palavra ou redirecionamento junto")
            if prof >= MAX_SUBSHELL:
                raise Para("subshell aninhado demais")
            if not seg[0].toks:
                raise Para("subshell vazio")
            valida_toks(seg[0].toks, slots, raizes, identidades, escritas, prof + 1)
            continue
        for e in [t[1] for t in seg if isinstance(t, tuple)]:
            confere_segredo(e)
            confere_caminho(e, raizes)
        seg = [t for t in seg if not isinstance(t, tuple)]
        if not seg:
            raise Para("redirecionamento sem comando")
        seg = tira_variavel(seg, identidades)
        if seg is None:
            continue
        for w in seg:
            confere_segredo(w)
        if VAR_ATRIBUICAO.fullmatch(seg[0]):
            raise Para(f"variável na frente do comando: {seg[0].split('=', 1)[0]}")
        if confere_build(seg, slots, raizes):
            continue
        if seg[0] == "mv":
            v_mv(seg[1:], escritas)
            continue
        v = COMANDOS.get(seg[0])
        if v is None:
            raise Para(f"fora da lista: {seg[0]}")
        v(seg[1:], raizes)


def classificar(cmd, slots, raizes, identidades=(), escritas=()):
    if not cmd.strip():
        raise Para("comando vazio")
    if "\n" in cmd or "\r" in cmd or "\x1b" in cmd:
        raise Para("comando em várias linhas ou com caractere de controle")
    m = JAVAP_FIND.match(cmd)
    texto = JAVAP_FIND.sub("javap -cp " + JAR_M2, cmd) if m and ".." not in m.group(1).split("/") else cmd
    if m:
        confere_segredo(m.group(0))
    if "$" in texto:
        raise Para("expansão com $")
    if "`" in texto:
        raise Para("crase")
    toks = lexar(texto)
    # O filtro de segredo roda por segmento, em valida_toks, sobre cada palavra
    # já sem aspas. A única exceção é o operando de `GLAB_CONFIG_DIR=` que
    # tira_variavel validou por igualdade com uma --identidade (mesmo critério
    # da comparação: sem `..`, normalizado): o diretório da identidade costuma
    # ter nome de segredo (glab-cli). Nenhuma outra palavra escapa.
    valida_toks(toks, slots, raizes, identidades, escritas)


def main():
    ap = argparse.ArgumentParser(description="classificador do vigia-agy.sh")
    ap.add_argument("--build-slot", action="append", default=[])
    ap.add_argument("--raiz", action="append", default=[])
    ap.add_argument("--identidade", action="append", default=[])
    ap.add_argument("--escrita", action="append", default=[])
    ap.add_argument("comando")
    a = ap.parse_args()
    try:
        slots = [os.path.normpath(expande_til(s)) for s in a.build_slot]
        raizes = [os.path.normpath(expande_til(r)) for r in a.raiz]
        identidades = []
        for d in a.identidade:
            if not (d.startswith("/") or d == "~" or d.startswith("~/")) or ".." in d.split("/"):
                raise Para(f"--identidade precisa ser caminho absoluto sem '..': {d}")
            identidades.append(os.path.normpath(expande_til(d)))
        escritas = []
        for d in a.escrita:
            if not (d.startswith("/") or d == "~" or d.startswith("~/")) or ".." in d.split("/"):
                raise Para(f"--escrita precisa ser caminho absoluto sem '..': {d}")
            escritas.append(os.path.normpath(expande_til(d)))
        classificar(a.comando, slots, raizes, identidades, escritas)
    except Para as e:
        print(f"para: {e}")
        return 1
    print("aprova")
    return 0


if __name__ == "__main__":
    sys.exit(main())
