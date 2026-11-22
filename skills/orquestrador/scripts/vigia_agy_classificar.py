#!/usr/bin/env python3
"""Classificador de comandos do vigia-agy.sh (references/harnesses/agy.md).

Decide se um comando que o agy pediu para rodar pode ser aprovado "uma vez" sem
o coordenador olhar. O Enter executa o comando de verdade, então a regra é
LISTA FECHADA e por palavra, não por regex sobre o texto:

1. Recusa de cara o que o shell expandiria ou executaria de um jeito que a
   leitura aqui não acompanha: `$` (variável, `$(...)`, `${...}`, `$'...'`),
   crase, barra invertida antes de aspas ou no fim, quebra de linha.
2. Separa em palavras com `shlex` (POSIX, aspas de verdade, sem comentário) e
   corta em `|`, `&&`, `||` e `;`. Qualquer outro operador (`&` sozinho, `(`,
   `)`, `<<`, `>|`, `|&`…) para. Redirecionamento só `>/dev/null`, `2>&1` e
   `< arquivo` (o arquivo passa pela regra de caminho).
3. Cada comando precisa estar na tabela e passar pelo validador dele (git só
   de leitura e sem `-O`/`--open*`/`--output`, find sem `-exec`/`-ok*`/
   `-delete`/`-fprint*`/`-fls`, sed só `sed -n 'N,Mp'`, sort sem `-o`, ps só
   `-p` e `-o`…). O build pelo build-slot informado executa o código da
   worktree por definição: é a mesma confiança do executor, e só o build passa.
4. Caminho: nada com `..`; caminho absoluto ou com `~` só dentro das raízes
   (`--raiz`); nome de segredo em qualquer palavra (sem distinguir caixa) para.

Uso: vigia_agy_classificar.py [--build-slot P]... [--raiz D]... -- '<comando>'
Imprime `aprova` (saída 0) ou `para: <motivo>` (saída 1).
"""

import argparse
import os
import re
import shlex
import sys

HOME = os.path.expanduser("~")

SEGREDO = re.compile(
    r"secret|credenc|credential|token|passw|senha|\.env\b|\.pem\b|id_rsa|id_ed25519|id_ecdsa|id_dsa"
    r"|\.ssh\b|\.gnupg|\.kube|kubeconfig|\.docker|\.pgpass|\.netrc|glab-cli|\.config/gh\b|vault"
    r"|\.aws\b|sops|\.age\b|\.p12\b|\.jks\b|keystore",
    re.I,
)
# Forma conferida: javap sobre o jar mais novo de um artefato do ~/.m2.
JAVAP_FIND = re.compile(
    r"""^javap -cp "\$\(find ~/\.m2/repository/[A-Za-z0-9/._-]+ -name '[A-Za-z0-9*._-]+' \| sort -V \| tail -1\)"(?= )"""
)
JAR_M2 = "@JAR_DO_M2@"
SEPARADORES = {"|", "&&", "||", ";"}
GIT_LEITURA = {"rev-parse", "status", "log", "diff", "show", "ls-files", "blame", "grep", "merge-base", "cat-file"}
BUILD = [
    ["./mvnw"], ["mvn"], ["go", "test"], ["go", "build"], ["go", "vet"],
    ["npm", "test"], ["npm", "run", "build"], ["uv", "run", "pytest"], ["uv", "run", "python", "-m", "pytest"],
]


class Para(Exception):
    pass


def expande_til(p):
    if p == "~" or p.startswith("~/"):
        return HOME + p[1:]
    if p.startswith("~"):
        raise Para(f"caminho de outro usuário: {p}")
    return p


def confere_caminho(p, raizes):
    if not p or p == JAR_M2:
        return
    if "://" in p:
        raise Para(f"URL: {p}")
    q = expande_til(p)
    if ".." in q.split("/"):
        raise Para(f"caminho com '..': {p}")
    if q.startswith("/"):
        n = os.path.normpath(q)
        if not any(n == r or n.startswith(r.rstrip("/") + "/") for r in raizes):
            raise Para(f"caminho fora das raízes: {p}")


def parece_caminho(t):
    return "/" in t or t.startswith("~") or t.startswith(".")


def confere_palavra(t, raizes):
    """Confere os caminhos que uma palavra pode carregar: ela mesma, o valor
    depois de `=` numa opção, e cada parte de uma lista separada por `:`."""
    valor = t
    if t.startswith("-"):
        if "=" not in t:
            return
        valor = t.split("=", 1)[1]
    for parte in valor.split(":") if ":" in valor else [valor]:
        if parece_caminho(parte) or "://" in t:
            confere_caminho(parte, raizes)


def confere_args(args, raizes, pular=()):
    for i, t in enumerate(args):
        if i in pular:
            continue
        confere_palavra(t, raizes)


def posicional(args, com_valor=()):
    """Índices dos argumentos posicionais (pula opções e o valor das opções em com_valor)."""
    idx, i = [], 0
    fim_opcoes = False
    while i < len(args):
        t = args[i]
        if not fim_opcoes and t == "--":
            fim_opcoes = True
        elif not fim_opcoes and t.startswith("-") and t != "-":
            if t in com_valor:
                i += 1
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


def v_padrao_primeiro(com_valor):
    """grep/rg/jq: o primeiro posicional é o padrão (ou filtro), não arquivo."""
    def v(args, raizes):
        pos = posicional(args, com_valor)
        explicito = any(a in ("-e", "-f", "--regexp", "--file") or a.startswith(("--regexp=", "-e")) and len(a) > 2 for a in args)
        pular = set()
        if pos and not explicito:
            pular.add(pos[0])
        # valor de -e/--regexp também é padrão
        for i, a in enumerate(args):
            if a in ("-e", "--regexp") and i + 1 < len(args):
                pular.add(i + 1)
        confere_args(args, raizes, pular)
    return v


def v_grep(args, raizes):
    v_padrao_primeiro({"-e", "-f", "-A", "-B", "-C", "-m", "--regexp", "--file"})(args, raizes)


def v_rg(args, raizes):
    for a in args:
        if a.startswith("--pre"):
            raise Para("rg --pre executa programa")
    v_padrao_primeiro({"-e", "-f", "-A", "-B", "-C", "-m", "-g", "-t", "-T", "--glob", "--type", "--regexp", "--file"})(args, raizes)


def v_jq(args, raizes):
    for a in args:
        if re.search(r"\benv\b|input_filename|\$__loc__", a):
            raise Para("jq lendo o ambiente")
    v_padrao_primeiro({"--arg", "--argjson", "--rawfile", "--slurpfile", "--indent"})(args, raizes)


def v_echo(args, raizes):
    pass  # só imprime: `$` e crase já pararam antes


def v_printf(args, raizes):
    if any(a == "-v" or a.startswith("-v") for a in args):
        raise Para("printf -v grava variável")


def v_date(args, raizes):
    if any(a in ("-s", "--set") or a.startswith("--set") or (a.startswith("-") and not a.startswith("--") and "s" in a[1:]) for a in args):
        raise Para("date -s muda a hora")
    confere_args(args, raizes)


def v_git(args, raizes):
    if not args or args[0] not in GIT_LEITURA:
        raise Para(f"git fora da leitura: {' '.join(args[:1])}")
    sub, resto = args[0], args[1:]
    for a in resto:
        if re.match(r"--(out|output|open|ext-diff|exec|upload|receive|textconv|no-index)", a):
            raise Para(f"opção do git que escreve ou executa: {a}")
        if sub == "grep" and (a.startswith("--o") or re.match(r"^-[^-]*O", a)):
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


def v_ps(args, raizes):
    i = 0
    tem_p = False
    while i < len(args):
        a = args[i]
        if a == "-p" and i + 1 < len(args) and re.fullmatch(r"[0-9,]+", args[i + 1]):
            tem_p = True
            i += 2
        elif a == "-o" and i + 1 < len(args) and re.fullmatch(r"[a-z%,]+", args[i + 1]):
            i += 2
        else:
            raise Para(f"ps só com -p <pid> e -o <campos>: {a}")
    if not tem_p:
        raise Para("ps sem -p")


def v_javap(args, raizes):
    for a in args:
        if a.startswith("-J"):
            raise Para("javap -J passa opção à JVM")
    confere_args(args, raizes)


def v_glab(args, raizes):
    if len(args) >= 2 and args[0] == "api":
        if len(args) > 3 or (len(args) == 3 and args[2] != "--paginate") or args[1].startswith("-") or "://" in args[1]:
            raise Para("glab api só GET: glab api <caminho> [--paginate]")
        return
    if len(args) >= 3 and args[:2] == ["mr", "view"] and args[2].isdigit() and args[3:] in ([], ["-F", "json"]):
        return
    raise Para("glab fora de 'api <caminho>' e 'mr view <n>'")


def v_sonar(args, raizes):
    if not (args[:2] == ["qg", "status"] or args[:1] == ["issues"] or args[:2] in (["hotspot", "list"], ["hotspots", "list"])):
        raise Para("sonar fora da leitura")
    for a in args:
        if re.match(r"--(url|host|server|token)", a):
            raise Para(f"sonar {a}")
    confere_args(args, raizes)


def v_taiga(args, raizes):
    if len(args) < 3 or args[0] != "story" or args[1] not in ("get", "comments") or not args[2].isdigit():
        raise Para("taiga fora de 'story get|comments <n>'")
    for a in args:
        if a.startswith("--url"):
            raise Para("taiga --url")
    confere_args(args[3:], raizes)


def v_herdr(args, raizes):
    if len(args) != 3 or args[:2] != ["agent", "get"]:
        raise Para("herdr fora de 'agent get <nome>'")


COMANDOS = {
    "cd": v_cd, "true": v_sem_args("true"), "pwd": v_sem_args("pwd"),
    "git": v_git, "grep": v_grep, "rg": v_rg, "jq": v_jq,
    "ls": v_generico, "cat": v_generico, "head": v_generico, "tail": v_generico, "wc": v_generico,
    "stat": v_generico, "du": v_generico, "df": v_echo, "diff": v_generico, "cut": v_generico,
    "tr": v_generico, "which": v_generico,
    "echo": v_echo, "printf": v_printf, "date": v_date,
    "find": v_find, "sed": v_sed, "sort": v_sort, "uniq": v_uniq, "ps": v_ps, "javap": v_javap,
    "glab": v_glab, "sonar": v_sonar, "taiga": v_taiga, "herdr": v_herdr,
}


def confere_build(tokens, slots, raizes):
    nome = expande_til(tokens[0])
    if nome not in slots:
        return False
    resto = tokens[1:]
    if not any(resto[: len(b)] == b for b in BUILD):
        raise Para(f"build-slot com comando fora do build: {' '.join(resto[:3])}")
    for a in resto:
        if re.search(r"exec|antrun", a, re.I):
            raise Para(f"build com {a} executa programa")
    confere_args(resto, raizes)
    return True


def palavras(cmd):
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def segmentos(tokens):
    segs, atual, i = [], [], 0
    while i < len(tokens):
        t = tokens[i]
        if t in SEPARADORES:
            segs.append(atual)
            atual = []
        elif t in (">", ">>", "&>") and i + 1 < len(tokens) and tokens[i + 1] == "/dev/null":
            if atual and re.fullmatch(r"[12]", atual[-1]):
                atual.pop()
            i += 1
        elif t == ">&" and i + 1 < len(tokens) and tokens[i + 1] in ("1", "2"):
            if atual and re.fullmatch(r"[12]", atual[-1]):
                atual.pop()
            i += 1
        elif t == "<" and i + 1 < len(tokens):
            atual.append(("<", tokens[i + 1]))
            i += 1
        elif re.fullmatch(r"[();<>|&]+", t):
            raise Para(f"operador do shell: {t}")
        else:
            atual.append(t)
        i += 1
    segs.append(atual)
    return segs


def classificar(cmd, slots, raizes):
    if not cmd.strip():
        raise Para("comando vazio")
    if "\n" in cmd or "\r" in cmd:
        raise Para("comando em várias linhas")
    if SEGREDO.search(cmd):
        raise Para(f"nome de segredo: {SEGREDO.search(cmd).group(0)}")
    texto = JAVAP_FIND.sub("javap -cp " + JAR_M2, cmd)
    if "$" in texto:
        raise Para("expansão com $")
    if "`" in texto:
        raise Para("crase")
    if re.search(r"\\(['\"]|\s*$)", texto):
        raise Para("barra invertida antes de aspas ou no fim")
    try:
        tokens = palavras(texto)
    except ValueError as e:
        raise Para(f"aspas não fecham ({e})")
    for seg in segmentos(tokens):
        if not seg:
            raise Para("comando vazio entre separadores")
        entradas = [t[1] for t in seg if isinstance(t, tuple)]
        seg = [t for t in seg if not isinstance(t, tuple)]
        for e in entradas:
            confere_caminho(e, raizes)
        if not seg:
            raise Para("redirecionamento sem comando")
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", seg[0]):
            raise Para(f"variável na frente do comando: {seg[0]}")
        if confere_build(seg, slots, raizes):
            continue
        v = COMANDOS.get(seg[0])
        if v is None:
            raise Para(f"fora da lista: {seg[0]}")
        v(seg[1:], raizes)


def main():
    ap = argparse.ArgumentParser(description="classificador do vigia-agy.sh")
    ap.add_argument("--build-slot", action="append", default=[])
    ap.add_argument("--raiz", action="append", default=[])
    ap.add_argument("comando")
    a = ap.parse_args()
    slots = [os.path.normpath(expande_til(s)) for s in a.build_slot]
    raizes = [os.path.normpath(expande_til(r)) for r in a.raiz]
    try:
        classificar(a.comando, slots, raizes)
    except Para as e:
        print(f"para: {e}")
        return 1
    print("aprova")
    return 0


if __name__ == "__main__":
    sys.exit(main())
