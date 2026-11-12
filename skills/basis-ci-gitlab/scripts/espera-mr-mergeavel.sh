#!/bin/bash
# Espera uma MR do GitLab ficar mesclável (ou terminar: mesclada, fechada,
# com conflito, pipeline do head falhou) e diz qual sinal saiu.
#
# SOMENTE LEITURA. Funciona de qualquer diretório: o projeto vem do argumento.
#
# Uso:
#   espera-mr-mergeavel.sh <projeto> <mr> [limite_em_segundos]     (padrão: 3600)
#
#   <projeto>  caminho com namespace (`grupo/subgrupo/repo`) ou id numérico.
#              O `/` é codificado aqui; não passe `%2F`.
#
# Variáveis opcionais: INTERVALO (segundos entre leituras, padrão 20).
#
# Existe para que ninguém improvise essa espera. No levantamento de 2026-11-12
# nos transcripts de agentes, esperas escritas na hora falharam por três
# motivos que este script evita: `glab api` com a URL e o `?` sem aspas dá
# "no matches found" sob zsh (53 ocorrências); `jq` quebra com "Invalid string:
# control characters" quando a descrição da MR traz caractere de controle; e
# `.head_pipeline.web_url` sobre campo nulo ou sobre corpo de erro dá "Cannot
# index string with string". Aqui a URL vai entre aspas, os caracteres de
# controle são removidos antes do `jq`, todo campo opcional tem `// "?"` e um
# corpo que não é uma MR conta como falha de leitura. Feito para
# `run_in_background` (Claude Code) ou para o laço dentro do turno (Codex),
# sem `sleep` do agente.
#
# Lê a MR por `glab api projects/<projeto>/merge_requests/<mr>` e compara o SHA
# da cabeça (`sha`) com o da pipeline (`head_pipeline.sha`): depois de um push,
# o `head_pipeline` pode ficar na pipeline anterior por minutos, e uma pipeline
# velha, verde ou vermelha, não vale. MR sem nenhuma pipeline (projeto sem CI)
# pode ficar mesclável.
#
# Imprime uma linha por mudança de estado e, no fim, o resumo:
#   mr <projeto>!<n> sha <sha> sinal <nome> estado <state> detalhe <detailed_merge_status> pipeline <status>
#
# Saída (sinal):
#   0  mergeavel   aberta, `detailed_merge_status` = mergeable e a pipeline do
#                  head (se há) não está pendente nem falhou
#   1  pipeline-falhou   a pipeline do head terminou failed ou canceled
#   2  conflito    `has_conflicts` ou `detailed_merge_status` = conflict
#   3  limite      tempo esgotado; o último estado vem na linha anterior
#                  (draft, aprovação, discussão aberta, rebase pendente, pipeline
#                  rodando... nada disso se resolve sozinho, então só o limite
#                  encerra)
#   4  mesclada    `state` = merged
#   5  fechada     `state` = closed
#  64  uso / ambiente (argumento inválido, falta glab ou jq, MR ilegível: 401/403/404 na hora, outra falha 5 vezes seguidas)

set -euo pipefail

PROJETO="${1:-}"
MR="${2:-}"
LIMITE="${3:-3600}"
INTERVALO="${INTERVALO:-20}"

uso() { echo "uso: $0 <projeto> <mr> [limite_em_segundos]" >&2; exit 64; }
[[ "$PROJETO" =~ ^([0-9]+|[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+)$ ]] || uso
[[ "$MR" =~ ^[0-9]+$ ]] || uso
[[ "$LIMITE" =~ ^[0-9]+$ ]] || uso
[[ "$INTERVALO" =~ ^[0-9]+$ ]] || uso
for cmd in glab jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "falta \`$cmd\` no PATH" >&2; exit 64; }
done

ENC="${PROJETO//\//%2F}"
URL="projects/${ENC}/merge_requests/${MR}"

inicio=$(date +%s)
ultimo=""
falhas_leitura=0
sha="?"
state="?"
detalhe="?"
pstatus="nenhuma"

resumo() { # sinal
  printf 'mr %s!%s sha %s sinal %s estado %s detalhe %s pipeline %s\n' \
    "$PROJETO" "$MR" "$sha" "$1" "$state" "$detalhe" "$pstatus"
}

while :; do
  # Caractere de controle cru (0x00-0x1f) derruba o jq; o JSON válido não o
  # traz fora de string, então removê-lo não muda o que importa.
  if raw=$(glab api "$URL" 2>&1); then
    mr=$(printf '%s' "$raw" | tr -d '\000-\037')
  else
    mr=""
  fi

  if [ -n "$mr" ] && jq -e 'type == "object" and has("iid") and has("state")' <<<"$mr" >/dev/null 2>&1; then
    falhas_leitura=0
    sha=$(jq -r '.sha // "?"' <<<"$mr")
    state=$(jq -r '.state // "?"' <<<"$mr")
    detalhe=$(jq -r '.detailed_merge_status // "?"' <<<"$mr")
    conflito=$(jq -r '.has_conflicts // false' <<<"$mr")
    psha=$(jq -r '.head_pipeline.sha // "?"' <<<"$mr")
    pstatus_raw=$(jq -r '.head_pipeline.status // "?"' <<<"$mr")
    pid=$(jq -r '.head_pipeline.id // "?"' <<<"$mr")

    # Só vale a pipeline do head; uma de outro SHA conta como "ainda não saiu".
    if [ "$pstatus_raw" = "?" ]; then
      pstatus="nenhuma"
    elif [ "$psha" = "$sha" ]; then
      pstatus="$pstatus_raw"
    else
      pstatus="velha(${pid})"
    fi

    estado="state $state, $detalhe, pipeline do head ${sha:0:8}: $pstatus"
    if [ "$estado" != "$ultimo" ]; then
      printf '%s  %s\n' "$(date +%H:%M:%S)" "$estado"
      ultimo="$estado"
    fi

    case "$state" in
      merged) resumo mesclada; exit 4 ;;
      closed) resumo fechada; exit 5 ;;
    esac
    if [ "$conflito" = true ] || [ "$detalhe" = conflict ]; then
      resumo conflito; exit 2
    fi
    case "$pstatus" in
      failed|canceled) resumo pipeline-falhou; exit 1 ;;
    esac
    if [ "$detalhe" = mergeable ]; then
      case "$pstatus" in
        nenhuma|success|skipped|manual) resumo mergeavel; exit 0 ;;
      esac
    fi
  else
    falhas_leitura=$((falhas_leitura + 1))
    msg=$(printf '%s' "$raw" | tr -d '\000-\037' | cut -c1-160)
    # 401, 403 e 404 não passam sozinhos: sai na primeira leitura.
    permanente=0
    case "$raw" in *"HTTP 401"*|*"HTTP 403"*|*"HTTP 404"*) permanente=1 ;; esac
    if [ "$permanente" -eq 1 ] || [ "$falhas_leitura" -ge 5 ]; then
      echo "não consegui ler a MR $PROJETO!$MR (glab api; 5 vezes seguidas, ou erro permanente): $msg" >&2
      exit 64
    fi
    printf '%s  não consegui ler a MR %s!%s (glab api): %s; tentando de novo\n' \
      "$(date +%H:%M:%S)" "$PROJETO" "$MR" "$msg"
  fi

  if [ $(( $(date +%s) - inicio )) -ge "$LIMITE" ]; then
    printf 'limite de %ss atingido; último estado: %s\n' "$LIMITE" "${ultimo:-nenhum}"
    resumo limite
    exit 3
  fi
  sleep "$INTERVALO"
done
