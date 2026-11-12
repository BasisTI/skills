#!/bin/bash
# Espera armada do coordenador (references/acompanhamento.md#worker-ativo-implica-espera-armada):
# sai no primeiro sinal que exige o coordenador de volta.
#
# SOMENTE LEITURA: herdr-workers.sh estado (herdr agent get), orq pend list,
# gh pr view / glab mr view. Feito para `run_in_background` no Claude Code (o
# fim do comando acorda o turno) ou para rodar com --limite-s curto, em laço,
# dentro do turno do Codex.
#
# Uso:
#   espera-onda.sh <agente>=<relatorio> [<agente>=<relatorio> ...]
#                  [--parado-s N]      (padrão 600, máx. 7200) parado = idle/done sem relatório
#                  [--limite-s N]      (padrão 6600, máx. 7200) nunca espera indefinida
#                  [--intervalo-s N]   (padrão 30, máx. 600)  pausa entre voltas
#                  [--onda <id>]       vigia pendência respondida da onda
#                  [--ignorar <chave>] (repetível) com --onda: não dispara por essa chave
#                  [--mr <url>]        vigia de merge (GitHub: gh; demais: glab)
#
# Relatório: conta o arquivo regular não vazio. O worker deve gravá-lo por
# `.<nome>.tmp` + `mv` (atômico); um relatório escrito aos poucos sairia no
# primeiro byte.
#
# Pendência (--onda): dispara só para resposta POSTERIOR ao início desta
# espera (`respondida_em` >= o instante de armar, em UTC). Resposta já lida e
# ainda não resolvida não derruba a armada seguinte. Se o relógio do `orq`
# diverge do desta máquina, ou a resposta caiu entre duas armadas, use
# `--ignorar <chave>` (ex.: `infra-2025/438#P1`) para as já tratadas.
#
# MR (--mr): com URL do GitLab no formato `.../-/merge_requests/<n>` o script
# passa `-R <grupo/projeto>` ao `glab`, que então funciona de qualquer cwd.
# Fora desse formato, o `glab mr view <url>` exige cwd dentro de um repositório.
#
# Existe porque o laço de espera escrito na hora pelo agente quebrou mais de
# uma vez: `espera.sh` reescrito ao menos 7 vezes em sessões diferentes;
# `${!R[@]}` deu "bad substitution" sob zsh e matou a espera da onda no ato;
# um filtro `select(.projeto=="orq")` em campo inexistente deixaria a
# pendência respondida sem disparar nunca; e 58 erros de `jq` vieram de ler
# texto de `pane read` em vez do JSON de `herdr agent get`. Este script é
# bash explícito (roda igual chamado do bash, zsh ou fish), lê o estado do
# agente só por `herdr-workers.sh estado` e SEMPRE imprime a linha final:
#   espera-onda: sinal=<nome> <detalhe>
#
# Saída (um código por sinal):
#   0  relatorio          relatório gravado (detalhe: agente e caminho)
#   1  blocked            worker `blocked`
#   2  uso / ambiente     argumento inválido, comando ausente
#   3  limite             limite de tempo, sem outro sinal
#   4  pane-sumido        o agente não existe mais (`agent_not_found`)
#   5  parado             idle/done sem relatório por --parado-s seguidos
#                         (`working` zera o contador)
#   6  pendencia          resposta nova em `orq pend list --respondidas` (--onda)
#   7  mr                 MR/PR mesclada ou fechada (detalhe: estado)
#   8  herdr-indisponivel o estado do agente falhou 5 voltas seguidas
#   9  fonte-indisponivel `orq` (--onda) ou `gh`/`glab` (--mr) falhou 5 voltas
#                         seguidas; o detalhe diz qual e o último erro
# Cada chamada externa roda sob `timeout` (20 s, nunca além do tempo que resta
# do limite); travar conta como falha. Ordem de conferência a cada volta:
# relatório, pendência, MR, estado dos agentes, limite.

set -euo pipefail

AQUI=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
WORKERS="$AQUI/herdr-workers.sh"

PARADO_S=600
LIMITE_S=6600
INTERVALO_S=30
CHAMADA_S=20
FALHAS_MAX=5
ONDA=""
MR=""
AGENTES=()
RELATORIOS=()
IGNORAR=()

uso() {
  echo "uso: $0 <agente>=<relatorio> [...] [--parado-s N] [--limite-s N] [--intervalo-s N] [--onda <id>] [--ignorar <chave>] [--mr <url>]" >&2
  echo "espera-onda: sinal=uso $1"
  exit 2
}

# numero <opção> <valor> <máximo>: inteiro decimal (zeros à esquerda não viram octal).
numero() {
  [[ "${2:-}" =~ ^[0-9]{1,9}$ ]] || uso "$1 pede um número inteiro"
  NUM=$((10#$2))
  [ "$NUM" -le "$3" ] || uso "$1 aceita no máximo $3"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --parado-s) numero "$1" "${2:-}" 7200; PARADO_S=$NUM; shift 2 ;;
    --limite-s) numero "$1" "${2:-}" 7200; LIMITE_S=$NUM; shift 2 ;;
    --intervalo-s) numero "$1" "${2:-}" 600; INTERVALO_S=$NUM; shift 2 ;;
    --onda) numero "$1" "${2:-}" 999999999; ONDA=$NUM; shift 2 ;;
    --ignorar) [ -n "${2:-}" ] || uso "--ignorar pede a chave"; IGNORAR+=("$2"); shift 2 ;;
    --mr) [ -n "${2:-}" ] || uso "--mr pede a URL"; MR=$2; shift 2 ;;
    -h|--help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
      exit 0 ;;
    --*) uso "opção desconhecida: $1" ;;
    *=*)
      [ -n "${1%%=*}" ] && [ -n "${1#*=}" ] || uso "esperava <agente>=<relatorio>, veio: $1"
      AGENTES+=("${1%%=*}")
      RELATORIOS+=("${1#*=}")
      shift ;;
    *) uso "esperava <agente>=<relatorio>, veio: $1" ;;
  esac
done

[ "${#AGENTES[@]}" -gt 0 ] || uso "informe ao menos um <agente>=<relatorio>"
[ "$INTERVALO_S" -ge 1 ] || uso "--intervalo-s precisa ser 1 ou mais"
if [ "${#IGNORAR[@]}" -gt 0 ] && [ -z "$ONDA" ]; then uso "--ignorar só vale com --onda"; fi

precisa=(herdr jq timeout)
if [ -n "$ONDA" ]; then precisa+=(orq); fi
if [ -n "$MR" ]; then
  case "$MR" in
    *github.com*) precisa+=(gh) ;;
    *) precisa+=(glab) ;;
  esac
fi
for cmd in "${precisa[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "falta \`$cmd\` no PATH" >&2; echo "espera-onda: sinal=uso falta $cmd"; exit 2; }
done
[ -x "$WORKERS" ] || { echo "falta $WORKERS" >&2; echo "espera-onda: sinal=uso falta herdr-workers.sh"; exit 2; }

fim() {  # fim <código> <sinal> <detalhe>
  printf 'espera-onda: sinal=%s %s\n' "$2" "$3"
  exit "$1"
}

inicio=$(date +%s)

# chamar <comando> [args...]: roda sob `timeout`, nunca além do que resta do limite.
chamar() {
  local resta=$((LIMITE_S - ($(date +%s) - inicio)))
  local t=$CHAMADA_S
  [ "$resta" -lt "$t" ] && t=$resta
  [ "$t" -ge 1 ] || t=1
  timeout "$t" "$@"
}

# Alvo do glab: com URL `.../-/merge_requests/<n>`, `<n> -R <grupo/projeto>`.
MR_ARGS=("$MR")
if [ -n "$MR" ] && [[ "$MR" =~ ^https?://[^/]+/(.+)/-/merge_requests/([0-9]+) ]]; then
  MR_ARGS=("${BASH_REMATCH[2]}" -R "${BASH_REMATCH[1]}")
fi

n=${#AGENTES[@]}
parado_desde=()
falhas=()
for ((i = 0; i < n; i++)); do parado_desde+=(0); falhas+=(0); done
falhas_pend=0
falhas_mr=0
erro_pend=""
erro_mr=""

ign='[]'
if [ "${#IGNORAR[@]}" -gt 0 ]; then ign=$(printf '%s\n' "${IGNORAR[@]}" | jq -R . | jq -sc .); fi

printf 'espera-onda: armada com %d agente(s), parado %ss, limite %ss\n' "$n" "$PARADO_S" "$LIMITE_S"

while :; do
  agora=$(date +%s)

  for ((i = 0; i < n; i++)); do
    if [ -f "${RELATORIOS[$i]}" ] && [ -s "${RELATORIOS[$i]}" ]; then
      fim 0 relatorio "agente ${AGENTES[$i]} gravou ${RELATORIOS[$i]}"
    fi
  done

  if [ -n "$ONDA" ]; then
    if pend=$(chamar orq pend list --respondidas --onda "$ONDA" --output json 2>&1) &&
       novas=$(jq -c --argjson ini "$inicio" --argjson ign "$ign" '
         if type != "array" then error("saída não é lista") else . end
         | [ .[] | select(((.chave // "") as $c | $ign | index($c)) | not)
                 | select(((.respondida_em // "" | sub("\\.[0-9]+"; "") | try fromdateiso8601 catch 0)) >= $ini) ]
       ' <<<"$pend" 2>&1); then
      falhas_pend=0
      qtd=$(jq 'length' <<<"$novas")
      if [ "$qtd" -gt 0 ]; then
        chaves=$(jq -r '[.[] | (.chave // "?")] | join(" ")' <<<"$novas")
        fim 6 pendencia "$qtd resposta(s) nova(s) na onda $ONDA: $chaves"
      fi
    else
      falhas_pend=$((falhas_pend + 1))
      erro_pend=$(printf '%s' "${novas:-$pend}" | head -c 200 | tr '\n' ' ')
      if [ "$falhas_pend" -ge "$FALHAS_MAX" ]; then
        fim 9 fonte-indisponivel "orq pend list falhou $FALHAS_MAX voltas seguidas: $erro_pend"
      fi
    fi
  fi

  if [ -n "$MR" ]; then
    if case "$MR" in
         *github.com*) saida=$(chamar gh pr view "$MR" --json state -q '.state' 2>&1) ;;
         *) saida=$(chamar glab mr view "${MR_ARGS[@]}" --output json 2>&1) &&
            saida=$(jq -r '.state // ""' <<<"$saida" 2>&1) ;;
       esac; then
      falhas_mr=0
      minusculo=$(printf '%s' "$saida" | tr '[:upper:]' '[:lower:]')
      case "$minusculo" in
        merged|closed) fim 7 mr "$MR está $minusculo" ;;
      esac
    else
      falhas_mr=$((falhas_mr + 1))
      erro_mr=$(printf '%s' "$saida" | head -c 200 | tr '\n' ' ')
      if [ "$falhas_mr" -ge "$FALHAS_MAX" ]; then
        fim 9 fonte-indisponivel "consulta da MR $MR falhou $FALHAS_MAX voltas seguidas: $erro_mr"
      fi
    fi
  fi

  for ((i = 0; i < n; i++)); do
    cod=0
    chamar "$WORKERS" estado "${AGENTES[$i]}" >/dev/null 2>&1 || cod=$?
    st=""
    case "$cod" in
      0) st=working ;;
      10) st=idle ;;
      12) st="done" ;;
      14) st=desconhecido ;;
      11) fim 1 blocked "agente ${AGENTES[$i]} está blocked" ;;
      13) fim 4 pane-sumido "agente ${AGENTES[$i]} não existe mais" ;;
    esac
    if [ -z "$st" ]; then  # 1, 2, 124 (timeout) ou outro: sem leitura
      falhas[i]=$((falhas[i] + 1))
      if [ "${falhas[$i]}" -ge "$FALHAS_MAX" ]; then
        fim 8 herdr-indisponivel "estado de ${AGENTES[$i]} sem leitura em $FALHAS_MAX voltas seguidas (último código $cod)"
      fi
      continue
    fi
    falhas[i]=0

    if [ "$st" = working ]; then
      parado_desde[i]=0
    elif [ "${parado_desde[$i]}" -eq 0 ]; then
      parado_desde[i]=$agora
    elif [ $((agora - parado_desde[i])) -ge "$PARADO_S" ]; then
      fim 5 parado "agente ${AGENTES[$i]} $st sem relatório há $((agora - parado_desde[i]))s (limite ${PARADO_S}s)"
    fi
  done

  if [ $(( $(date +%s) - inicio )) -ge "$LIMITE_S" ]; then
    fim 3 limite "limite de ${LIMITE_S}s atingido sem outro sinal"
  fi
  sleep "$INTERVALO_S"
done
