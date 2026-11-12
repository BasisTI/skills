#!/bin/bash
# Espera armada do coordenador (references/acompanhamento.md#worker-ativo-implica-espera-armada):
# sai no primeiro sinal que exige o coordenador de volta.
#
# SOMENTE LEITURA: herdr agent get, orq pend list, gh pr view / glab mr view.
# Feito para `run_in_background` no Claude Code (o fim do comando acorda o
# turno) ou para rodar com --limite-s curto, em laço, dentro do turno do Codex.
#
# Uso:
#   espera-onda.sh <agente>=<relatorio> [<agente>=<relatorio> ...]
#                  [--parado-s N]      (padrão: 600)  parado = idle/done sem relatório
#                  [--limite-s N]      (padrão: 6600) nunca espera indefinida
#                  [--intervalo-s N]   (padrão: 30)   pausa entre voltas
#                  [--onda <id>]       confere `orq pend list --respondidas --onda <id>`
#                  [--mr <url>]        vigia de merge (GitHub: gh; demais: glab)
#
# Existe porque o laço de espera escrito na hora pelo agente quebrou mais de
# uma vez: `espera.sh` reescrito ao menos 7 vezes em sessões diferentes;
# `${!R[@]}` deu "bad substitution" sob zsh e matou a espera da onda no ato;
# um filtro `select(.projeto=="orq")` em campo inexistente deixaria a
# pendência respondida sem disparar nunca; e 58 erros de `jq` vieram de ler
# texto de `pane read` em vez do JSON de `herdr agent get`. Este script é
# bash explícito (roda igual chamado do bash, zsh ou fish), lê o estado do
# agente só por `herdr agent get` e SEMPRE imprime a linha final:
#   espera-onda: sinal=<nome> <detalhe>
#
# Saída (um código por sinal):
#   0  relatorio          relatório gravado e não vazio (detalhe: agente e caminho)
#   1  blocked            worker `blocked`
#   2  uso / ambiente     argumento inválido, comando ausente
#   3  limite             limite de tempo, sem outro sinal
#   4  pane-sumido        `herdr agent get` responde `agent_not_found`
#   5  parado             idle/done sem relatório por --parado-s seguidos
#                         (`working` zera o contador)
#   6  pendencia          `orq pend list --respondidas` trouxe alguma (só com --onda)
#   7  mr                 MR/PR mesclada ou fechada (só com --mr; detalhe: estado)
#   8  herdr-indisponivel `herdr agent get` falhou 5 voltas seguidas sem
#                         `agent_not_found` (daemon fora, resposta ilegível)
# Ordem de conferência a cada volta: relatório, pendência, MR, estado dos
# agentes, limite.

set -euo pipefail

PARADO_S=600
LIMITE_S=6600
INTERVALO_S=30
ONDA=""
MR=""
AGENTES=()
RELATORIOS=()

uso() {
  echo "uso: $0 <agente>=<relatorio> [...] [--parado-s N] [--limite-s N] [--intervalo-s N] [--onda <id>] [--mr <url>]" >&2
  echo "espera-onda: sinal=uso $1"
  exit 2
}

numero() { [[ "${2:-}" =~ ^[0-9]+$ ]] || uso "$1 pede um número inteiro"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --parado-s) numero "$1" "${2:-}"; PARADO_S=$2; shift 2 ;;
    --limite-s) numero "$1" "${2:-}"; LIMITE_S=$2; shift 2 ;;
    --intervalo-s) numero "$1" "${2:-}"; INTERVALO_S=$2; shift 2 ;;
    --onda) numero "$1" "${2:-}"; ONDA=$2; shift 2 ;;
    --mr) [ -n "${2:-}" ] || uso "--mr pede a URL"; MR=$2; shift 2 ;;
    -h|--help) sed -n '2,45p' "$0" >&2; exit 2 ;;
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

precisa=(herdr jq)
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

fim() {  # fim <código> <sinal> <detalhe>
  printf 'espera-onda: sinal=%s %s\n' "$2" "$3"
  exit "$1"
}

n=${#AGENTES[@]}
parado_desde=()
falhas=()
for ((i = 0; i < n; i++)); do parado_desde+=(0); falhas+=(0); done

inicio=$(date +%s)
printf 'espera-onda: armada com %d agente(s), parado %ss, limite %ss\n' "$n" "$PARADO_S" "$LIMITE_S"

while :; do
  agora=$(date +%s)

  for ((i = 0; i < n; i++)); do
    if [ -s "${RELATORIOS[$i]}" ]; then
      fim 0 relatorio "agente ${AGENTES[$i]} gravou ${RELATORIOS[$i]}"
    fi
  done

  if [ -n "$ONDA" ]; then
    pend=$(orq pend list --respondidas --onda "$ONDA" --output json 2>/dev/null || true)
    qtd=$(jq -r 'if type == "array" then length else 0 end' <<<"$pend" 2>/dev/null || echo 0)
    if [ "${qtd:-0}" -gt 0 ]; then
      chaves=$(jq -r '[.[] | (.chave // "?")] | join(" ")' <<<"$pend" 2>/dev/null || echo "?")
      fim 6 pendencia "$qtd respondida(s) na onda $ONDA: $chaves"
    fi
  fi

  if [ -n "$MR" ]; then
    case "$MR" in
      *github.com*) estado=$(gh pr view "$MR" --json state -q '.state // ""' 2>/dev/null || true) ;;
      *) estado=$(glab mr view "$MR" --output json 2>/dev/null | jq -r '.state // ""' 2>/dev/null || true) ;;
    esac
    case "$estado" in
      [Mm][Ee][Rr][Gg][Ee][Dd]|[Cc][Ll][Oo][Ss][Ee][Dd])
        minusculo=$(printf '%s' "$estado" | tr '[:upper:]' '[:lower:]')
        fim 7 mr "$MR está $minusculo" ;;
    esac
  fi

  for ((i = 0; i < n; i++)); do
    # O erro (`agent_not_found`) sai em JSON no stderr: junte os dois fluxos.
    saida=$(herdr agent get "${AGENTES[$i]}" 2>&1 || true)
    st=$(jq -r '.result.agent.agent_status // ""' <<<"$saida" 2>/dev/null || true)
    erro=$(jq -r '.error.code // ""' <<<"$saida" 2>/dev/null || true)

    if [ "$erro" = "agent_not_found" ]; then
      fim 4 pane-sumido "agente ${AGENTES[$i]} não existe mais"
    fi
    if [ -z "$st" ]; then
      falhas[i]=$((falhas[i] + 1))
      if [ "${falhas[$i]}" -ge 5 ]; then
        fim 8 herdr-indisponivel "herdr agent get ${AGENTES[$i]} sem resposta legível em 5 voltas"
      fi
      continue
    fi
    falhas[i]=0

    case "$st" in
      working) parado_desde[i]=0 ;;
      blocked) fim 1 blocked "agente ${AGENTES[$i]} está blocked" ;;
      *)
        if [ "${parado_desde[$i]}" -eq 0 ]; then
          parado_desde[i]=$agora
        elif [ $((agora - parado_desde[i])) -ge "$PARADO_S" ]; then
          fim 5 parado "agente ${AGENTES[$i]} $st sem relatório há $((agora - parado_desde[i]))s (limite ${PARADO_S}s)"
        fi ;;
    esac
  done

  if [ $((agora - inicio)) -ge "$LIMITE_S" ]; then
    fim 3 limite "limite de ${LIMITE_S}s atingido sem outro sinal"
  fi
  sleep "$INTERVALO_S"
done
