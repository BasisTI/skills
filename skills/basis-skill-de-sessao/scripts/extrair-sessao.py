#!/usr/bin/env python3
"""Extrai o dossiê de uma sessão de agente a partir do transcript JSONL.

Somente leitura. Não escreve nada fora do arquivo de saída informado.

    extrair-sessao.py --listar [termo]        lista sessões, filtrando por título/cwd
    extrair-sessao.py <transcript|sessionId>  imprime o dossiê no stdout
    extrair-sessao.py <...> -o dossie.md      grava em arquivo

Lê Claude Code e Codex. A leitura de cada formato mora em `transcripts.py`; aqui fica
só a redação do dossiê, que é a mesma para os dois.

O dossiê separa o que vira skill do que é ruído. Ver references/formato-transcript.md
para a justificativa de cada regra de leitura.
"""

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import transcripts as T                                       # noqa: E402

# Frases do relator que sinalizam beco sem fundo: a tentativa anterior não resolveu.
# É o material mais valioso do transcript e o único que o postmortem não guarda.
NEGATIVAS = re.compile(
    r"não (retornou|funciona|resolve|deu|era|foi|adianta|mudou|aparece)"
    r"|continua (igual|o mesmo|falhando|quebrado)"
    r"|ainda (está|assim|falha|não)"
    r"|persiste|sem efeito|nada mudou|voltou a",
    re.IGNORECASE,
)


def listar(termo=None):
    achados = []
    for caminho in T.transcripts():
        r = T.resumo(caminho)
        rotulo = r["titulo"] or "(sem título)"
        alvo = f"{rotulo} {r['cwd'] or ''} {caminho}"
        if termo and termo.lower() not in alvo.lower():
            continue
        achados.append((r["quando"] or "?", r["prompts"], rotulo,
                        r["cwd"] or "?", r["formato"], caminho))

    for quando, prompts, titulo, cwd, formato, caminho in sorted(achados, reverse=True):
        print(f"{quando}  {formato:6}  {prompts:3} prompts  {titulo[:52]:52}  {cwd}")
        print(f"{'':14}{caminho}")


def resolver(alvo):
    caminho = T.resolver(alvo)
    if not caminho:
        sys.exit(f"sessão não encontrada: {alvo}\nuse --listar para procurar")
    return caminho


def bloco(cmd, limite=None):
    linhas = cmd.strip().split("\n")
    if limite and len(linhas) > limite:
        linhas = linhas[:limite] + [f"... (+{len(cmd.strip().splitlines()) - limite} linhas)"]
    return "\n".join(linhas)


def dossie(d, caminho, saida):
    p = lambda *a: print(*a, file=saida)

    p(f"# Dossiê de sessão — {d['titulo'] or '(sem título)'}")
    p()
    p(f"**Transcript:** `{caminho}`  ")
    p(f"**Harness:** {d['formato']}{' · sessão de subagente' if d['filha'] else ''}  ")
    p(f"**Diretório:** `{d['cwd'] or '?'}`  ")
    p(f"**Branch:** `{d['branch'] or '?'}`  ")
    p(f"**Período:** {(d['inicio'] or '?')[:19]} → {(d['fim'] or '?')[:19]} (UTC)  ")
    p(f"**Volume:** {len(d['prompts'])} prompts · {len(d['comandos'])} comandos · "
      f"{d['raciocinios']} blocos de raciocínio")
    p()
    p("> Material bruto. **Não publique nada daqui sem rodar `varrer-segredos.sh` e sem "
      "revisão humana** — saída de comando carrega token, hostname interno e dump.")
    p()

    p("## 1. Prompts do relator — matéria-prima da `description`")
    p()
    p("São as frases que a pessoa realmente usou. A `description` da skill precisa disparar")
    p("nelas, não em vocabulário de documentação. Copie os termos, não os traduza.")
    p()
    for i, (ts, txt) in enumerate(d["prompts"], 1):
        marca = "  ⚠️ **negativa**" if NEGATIVAS.search(txt) else ""
        p(f"### {i}. `{ts[:19]}`{marca}")
        p()
        p("```")
        p(bloco(txt, 30))
        p("```")
        p()

    negativas = [(i, ts, t) for i, (ts, t) in enumerate(d["prompts"], 1) if NEGATIVAS.search(t)]
    falhos = [c for c in d["comandos"] if c["erro"]]
    vazios = [c for c in d["comandos"] if c["vazio"] and not c["erro"]]

    p("## 2. Becos sem saída — o que vira conhecimento negativo")
    p()
    p("A parte que o postmortem descarta e a skill precisa guardar: a teoria errada, a")
    p("ferramenta que mentiu, o comando que não provou nada. Nem todo item aqui é beco —")
    p("julgue cada um. Saída vazia pode ser o achado (ausência de evidência é evidência).")
    p()
    if negativas:
        p("**Prompts em que o relator diz que não resolveu:**")
        p()
        for i, ts, txt in negativas:
            p(f"- Prompt {i} (`{ts[:19]}`): {txt.splitlines()[0][:150]}")
        p()
    if falhos:
        p(f"**Comandos que falharam ({len(falhos)}):**")
        p()
        for c in falhos:
            p(f"- `{c['cmd'].splitlines()[0][:110]}`")
            if c["stderr"]:
                p(f"  - stderr: `{c['stderr'][:110]}`")
        p()
    if vazios:
        p(f"**Comandos com saída vazia ({len(vazios)}):**")
        p()
        for c in vazios:
            p(f"- `{c['cmd'].splitlines()[0][:110]}`")
        p()
    if not (negativas or falhos or vazios):
        p("*Nada detectado automaticamente. Releia os prompts — a heurística é grosseira.*")
        p()

    p("## 3. Comandos executados, em ordem")
    p()
    p("Candidatos ao script de coleta de evidência. Procure o subconjunto que, rodado de")
    p("uma vez e sem mutação, teria dado o mesmo veredito em um passo.")
    p()
    for c in d["comandos"]:
        marca = " ✗" if c["erro"] else (" ∅" if c["vazio"] else "")
        cab = f"`{c['ts'][11:19]}`{marca}"
        p(f"- {cab} {c['desc'] or ''}")
        p("  ```bash")
        for linha in bloco(c["cmd"], 12).split("\n"):
            p(f"  {linha}")
        p("  ```")
    p()

    p("## 4. Conclusões do agente")
    p()
    p("Onde costuma estar a tabela de assinatura sintoma → significado, já redigida.")
    p()
    for ts, txt in d["conclusoes"]:
        p(f"### `{ts[:19]}`")
        p()
        p(bloco(txt, 40))
        p()

    if d["arquivos"]:
        p("## 5. Arquivos escritos ou editados")
        p()
        for nome, caminho_arq in d["arquivos"]:
            p(f"- `{nome}` → `{caminho_arq}`")
        p()


def main():
    ap = argparse.ArgumentParser(description="Extrai dossiê de sessão de agente")
    ap.add_argument("alvo", nargs="?", help="caminho do .jsonl ou sessionId")
    ap.add_argument("--listar", nargs="?", const="", metavar="TERMO",
                    help="lista sessões disponíveis")
    ap.add_argument("-o", "--saida", help="arquivo de saída (padrão: stdout)")
    args = ap.parse_args()

    if args.listar is not None:
        listar(args.listar or None)
        return
    if not args.alvo:
        ap.error("informe o transcript ou use --listar")

    caminho = resolver(args.alvo)
    d = T.ler(caminho)
    if args.saida:
        with open(args.saida, "w") as f:
            dossie(d, caminho, f)
        print(f"dossiê gravado em {args.saida}", file=sys.stderr)
        print(f"PRÓXIMO PASSO OBRIGATÓRIO: varrer-segredos.sh {args.saida}", file=sys.stderr)
    else:
        dossie(d, caminho, sys.stdout)


if __name__ == "__main__":
    main()
