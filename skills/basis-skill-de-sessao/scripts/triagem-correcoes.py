#!/usr/bin/env python3
"""Procura o que você teve que dizer mais de uma vez, em todas as sessões locais.

Somente leitura. Não escreve nada fora do arquivo de saída informado.

    triagem-correcoes.py                          últimos 45 dias, todos os projetos
    triagem-correcoes.py --dias 90 --projeto ponto
    triagem-correcoes.py -o triagem.md

**Este script responde a uma pergunta diferente da do `extrair-sessao.py`.** Aquele
parte de "sei que aquela sessão rendeu, extraia dela"; este parte de "não sei onde
estou perdendo tempo, descubra". A diferença importa porque a lacuna mais cara de
skill **não aparece numa sessão só**: nenhuma sessão isolada foi memorável, o sinal é
a mesma correção reaparecendo em sessões diferentes, semanas separadas.

O que ele faz, e o que deliberadamente não faz:

- **Faz**: coletar os prompts que parecem correção, agrupá-los por diretório de
  trabalho, e contar em **quantas sessões distintas** cada termo de conteúdo aparece
  dentro dessas correções.
- **Não faz**: julgar qualidade, dar nota, decidir o que vira skill. Contagem de
  termo é um índice grosseiro para leitura humana, não uma conclusão. Um termo que
  aparece em oito sessões pode ser oito instâncias do mesmo defeito de instrução ou
  oito assuntos diferentes que por acaso compartilham a palavra — só a leitura das
  linhas separa os dois casos.

Recorrência é condição necessária, não suficiente. O portão de "quando não escrever"
está na SKILL.md e continua valendo sobre tudo que sair daqui.
"""

import argparse
import os
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import transcripts as T                                       # noqa: E402

# Um prompt vira candidato quando contradiz, corrige ou repete uma instrução. Os
# marcadores são de português falado em revisão — é assim que a correção sai na
# prática, não em vocabulário de documentação.
CORRECAO = re.compile(
    r"\bnão (é|foi|era|deve|deveria|precisa|pode|use|usa|faça|faz|coloque|mexe|toca)\b"
    r"|\bna verdade\b|\bpelo contrário\b|\bao invés\b|\bem vez de\b"
    r"|\b(está|ficou|isso|esse|essa) errad[oa]\b|\bcorrig[ei]\b|\bcorrija\b"
    r"|\bdeveria (ser|usar|estar|ter|ficar)\b|\bo certo é\b|\bo correto é\b"
    r"|\bjá (falei|disse|tinha dito|expliquei)\b|\bcomo eu disse\b|\bde novo\b"
    r"|\bnunca (crie|use|faça|coloque)\b|\bnão inventa\b|\bnão invente\b"
    r"|\bnão precisa (de|criar|fazer)\b|\bpode (tirar|remover|apagar)\b"
    r"|\bnot (correct|right|what)\b|\binstead of\b|\bdon't (create|use|add)\b",
    re.IGNORECASE,
)

# As mesmas negativas do dossiê: "a tentativa anterior não resolveu". Aqui elas entram
# como sinal separado, porque dizem respeito ao problema e não à instrução.
NEGATIVA = re.compile(
    r"não (retornou|funciona|resolve|deu|adianta|mudou|aparece)"
    r"|continua (igual|o mesmo|falhando|quebrado)"
    r"|ainda (está|assim|falha|não)|persiste|sem efeito|nada mudou",
    re.IGNORECASE,
)

VAZIAS = set("""
a as o os um uma uns umas de do da dos das em no na nos nas por para com sem sob sobre
e ou mas que se como quando onde qual quais quem cujo isso isto aquilo esse essa este
esta aquele aquela ser estar ter haver fazer vai vou pode deve foi era são está estão
não sim já ainda mais menos muito pouco todo toda todos todas cada outro outra outros
outras mesmo mesma nosso nossa nossos nossas meu minha seu sua eu voce você ele ela
nós eles elas lhe me te nos vos ao aos à às pelo pela pelos pelas num numa dum duma
então aqui ali lá agora depois antes sempre nunca também só apenas até desde entre
coisa jeito forma vez vezes parte lugar caso ponto ver vem vamos precisa deveria
the and for with that this from not you your are was were have has can should would
usar usa usando usei colocar coloca coloquei ficar fica ficou ficam fazer faca feito
exemplo novo nova novos novas alguns algumas alguma algum nenhum nenhuma nada tudo
podemos poderia poderiamos seria seriam somente apenas precisar precisamos precisava
temos tenho tinha melhor pior pontos acho acha achei quero queria talvez deixa deixar
olhar olha vendo assim bastante certo pouco depois antes agora falta faltou consegue
conseguiu segue seguem vamos vou pegar pega usar usado usada dizer diz falar fala
""".split())


def sem_acento(s):
    return "".join(c for c in unicodedata.normalize("NFD", s)
                   if unicodedata.category(c) != "Mn")


def termos(texto):
    """Palavras de conteúdo de um prompt, normalizadas para agrupar.

    Sem acento e em minúscula para `Configuração` casar com `configuracao`; com 4
    caracteres ou mais para cortar preposição que escapou da lista; e o token cru
    preservado quando tem `-`, `_` ou `.`, porque `application-staging.yml`,
    `ci/pipeline.toml` e `SPRING_PROFILES_ACTIVE` são exatamente os termos que a
    gente quer contar inteiros.
    """
    achados = set()
    for bruto in re.findall(r"[A-Za-zÀ-ÿ0-9][\w./\-]{3,}", texto):
        norm = sem_acento(bruto.lower()).strip("./-")
        if len(norm) < 4 or norm in VAZIAS or norm.isdigit():
            continue
        achados.add(norm)
    return achados


def recente(caminho, limite):
    try:
        return datetime.fromtimestamp(os.path.getmtime(caminho), tz=timezone.utc) >= limite
    except OSError:
        return False


def coletar(dias, projeto, max_sessoes):
    limite = datetime.now(timezone.utc) - timedelta(days=dias)
    sessoes, ignoradas, base = [], Counter(), defaultdict(set)

    for caminho in T.transcripts():
        if len(sessoes) >= max_sessoes:
            break
        if not recente(caminho, limite):
            continue
        try:
            d = T.ler(caminho)
        except T.FormatoNaoSuportado:
            ignoradas["formato não suportado"] += 1
            continue
        except (OSError, ValueError):
            ignoradas["ilegível"] += 1
            continue
        if d["filha"]:
            ignoradas["sessão de subagente"] += 1
            continue
        if projeto and projeto.lower() not in (d["cwd"] or "").lower():
            continue
        if not d["prompts"]:
            ignoradas["sem prompt de pessoa"] += 1
            continue

        achados = []
        for i, (ts, txt) in enumerate(d["prompts"], 1):
            tipo = "correção" if CORRECAO.search(txt) else ("negativa" if NEGATIVA.search(txt) else None)
            # O primeiro prompt é o pedido, não uma correção do que o agente fez.
            if tipo and i > 1:
                achados.append({"n": i, "ts": ts, "tipo": tipo, "txt": " ".join(txt.split())})
        if achados:
            sessoes.append((d, achados))
        # Linha de base: os termos de **todos** os prompts da sessão, inclusive os que
        # não são correção. É contra ela que a especificidade é medida.
        for _, txt in d["prompts"]:
            for termo in termos(txt):
                base[termo].add(d["id"])

    return sessoes, ignoradas, base


def relatorio(sessoes, ignoradas, base, dias, projeto, max_sessoes, saida):
    p = lambda *a: print(*a, file=saida)

    total_corr = sum(len(a) for _, a in sessoes)
    projetos = {(d["cwd"] or "?") for d, _ in sessoes}

    p("# Triagem de correções recorrentes")
    p()
    p(f"**Janela:** últimos {dias} dias · **projeto:** {projeto or 'todos'} · "
      f"**teto de sessões:** {max_sessoes}  ")
    p(f"**Amostra:** {len(sessoes)} sessões com correção, em {len(projetos)} diretórios · "
      f"{total_corr} prompts candidatos")
    if ignoradas:
        p("**Fora da amostra:** " + " · ".join(f"{n} {k}" for k, n in ignoradas.most_common()))
    p()
    p("> Candidatos, não achados. A regex reconhece a **forma** de uma correção, não o")
    p("> assunto dela — elogio com \"na verdade\" entra, e correção educada sem marcador")
    p("> escapa. Leia antes de concluir qualquer coisa.")
    p()

    # ------------------------------------------------------------ recorrência
    por_termo = defaultdict(set)
    linhas_por_termo = defaultdict(list)
    for d, achados in sessoes:
        sid = d["id"]
        for a in achados:
            for termo in termos(a["txt"]):
                por_termo[termo].add(sid)
                linhas_por_termo[termo].append((d, a))

    # Recorrência sozinha não serve: `usar` e `arquivo` aparecem em quase toda sessão e
    # lideram qualquer contagem bruta, afogando o sinal. O que interessa é o termo que é
    # **desproporcionalmente** de correção — aparece quando você corrige e pouco fora
    # disso. Daí a especificidade: das sessões em que o termo aparece em qualquer prompt,
    # em que fração dela ele aparece numa correção.
    #
    #   peso = sessões_com_correção × especificidade
    #
    # O produto é deliberado: só a especificidade promoveria o termo raro que apareceu em
    # três correções e em nada mais, que é ruído de amostra pequena; só a contagem traz o
    # vocabulário de volta. Nenhum dos dois sozinho responde "isto volta sempre".
    marcados = []
    for termo, sess in por_termo.items():
        n = len(sess)
        if n < 3:
            continue
        total = len(base.get(termo, sess)) or n
        espec = n / total
        marcados.append((round(n * espec, 2), n, total, round(espec, 2), termo))
    recorrentes = sorted(marcados, reverse=True)

    p("## 1. Termos que reaparecem em correções, e só nelas")
    p()
    p("A contagem é de **sessões**, não de ocorrências: dizer a mesma coisa três vezes na")
    p("mesma conversa conta 1. É o que separa \"insisti naquele dia\" de \"isto volta sempre\".")
    p()
    p("`espec` é a fração das sessões que citam o termo em que ele aparece **numa correção**.")
    p("Perto de 1,0 quer dizer que o termo praticamente só é dito quando você está")
    p("corrigindo — é esse o sinal, não a contagem bruta.")
    p()
    if not recorrentes:
        p("*Nenhum termo em 3 ou mais sessões. Amostra pequena, ou nada recorrente —")
        p("aumente `--dias` antes de concluir que não há padrão.*")
        p()
    else:
        p("||Peso||Sessões com correção||Sessões que citam||espec||Termo||")
        for peso, n, total, espec, termo in recorrentes[:35]:
            p(f"|{peso}|{n}|{total}|{espec}|`{termo}`|")
        p()
        p("Termo **específico** — nome de arquivo, de chave de configuração, de comando —")
        p("quase sempre aponta uma instrução faltando numa skill. Termo genérico que")
        p("sobreviveu ao peso costuma ser vocabulário seu, não padrão; confira na §2.")
        p()

        p("## 2. As linhas por trás dos termos mais recorrentes")
        p()
        for peso, n, total, espec, termo in recorrentes[:12]:
            vistos, blocos = set(), []
            for d, a in linhas_por_termo[termo]:
                if d["id"] in vistos:
                    continue
                vistos.add(d["id"])
                blocos.append((d, a))
            p(f"### `{termo}` — {n} de {total} sessões que o citam (espec {espec})")
            p()
            for d, a in blocos[:6]:
                proj = os.path.basename((d["cwd"] or "?").rstrip("/"))
                p(f"- **{proj}** · `{(a['ts'] or '')[:10]}` · {a['tipo']} · prompt {a['n']}  ")
                p(f"  {a['txt'][:220]}")
            p()

    # ------------------------------------------------------------ por projeto
    p("## 3. Todas as correções, por diretório")
    p()
    p("Para ler quando um termo da §1 parecer promissor e você quiser o contexto ao redor.")
    p()
    por_projeto = defaultdict(list)
    for d, achados in sessoes:
        por_projeto[d["cwd"] or "?"].append((d, achados))

    for cwd in sorted(por_projeto, key=lambda c: -sum(len(a) for _, a in por_projeto[c])):
        grupo = por_projeto[cwd]
        p(f"### `{cwd}` — {sum(len(a) for _, a in grupo)} em {len(grupo)} sessões")
        p()
        for d, achados in grupo:
            rotulo = (d["titulo"] or "(sem título)")[:60]
            p(f"- `{(d['inicio'] or '?')[:10]}` · {d['formato']} · {rotulo}")
            for a in achados:
                p(f"  - _{a['tipo']}_ (prompt {a['n']}): {a['txt'][:200]}")
        p()

    p("## 4. O que fazer com isto")
    p()
    p("1. Leia a §1 e escolha os termos **específicos**, ignorando os genéricos.")
    p("2. Para cada um, leia as linhas da §2 e decida se são o **mesmo** defeito de")
    p("   instrução ou assuntos diferentes que compartilham a palavra.")
    p("3. Só então aplique o portão da SKILL.md: um agente competente, com as")
    p("   instruções atuais, ainda erraria assim? Se não, não escreva nada.")
    p("4. O que passar no portão vira uma edição pequena e nomeada, na skill que **deveria**")
    p("   ter dito aquilo — não uma skill nova, e não um parágrafo acrescentado no fim.")


def main():
    ap = argparse.ArgumentParser(description="Correções que se repetem entre sessões")
    ap.add_argument("--dias", type=int, default=45, help="janela em dias (padrão: 45)")
    ap.add_argument("--projeto", help="filtra pelo diretório de trabalho da sessão")
    ap.add_argument("--max-sessoes", type=int, default=120, help="teto de sessões lidas")
    ap.add_argument("-o", "--saida", help="arquivo de saída (padrão: stdout)")
    args = ap.parse_args()

    sessoes, ignoradas, base = coletar(args.dias, args.projeto, args.max_sessoes)
    if not sessoes:
        sys.exit(f"nenhuma sessão com correção nos últimos {args.dias} dias"
                 + (f" em '{args.projeto}'" if args.projeto else "")
                 + "\naumente --dias ou tire o --projeto")

    if args.saida:
        with open(args.saida, "w") as f:
            relatorio(sessoes, ignoradas, base, args.dias, args.projeto, args.max_sessoes, f)
        print(f"triagem gravada em {args.saida}", file=sys.stderr)
        print(f"PRÓXIMO PASSO OBRIGATÓRIO: varrer-segredos.sh {args.saida}", file=sys.stderr)
    else:
        relatorio(sessoes, ignoradas, base, args.dias, args.projeto, args.max_sessoes, sys.stdout)


if __name__ == "__main__":
    main()
