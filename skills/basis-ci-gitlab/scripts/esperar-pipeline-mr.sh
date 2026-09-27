#!/usr/bin/env bash
# Espera a pipeline do HEAD de uma MR terminar e diz se ela serve de aceite
# (references/ciclo-da-mr.md, passo 2).
#
# SOMENTE LEITURA. Rode de dentro do repositório (o `:id` do glab vem do remote).
#
# Uso:
#   esperar-pipeline-mr.sh <mr_iid> [limite_em_segundos]     (padrão: 3600)
#
# Existe para que ninguém improvise essa espera: um laço feito na hora, com
# `set -- $out` sob zsh, nunca casou o SHA e deixou um agente parado 30 minutos
# até o timeout do monitor. Este script é bash explícito, compara o SHA da
# pipeline com o head da MR e SEMPRE imprime o resultado ao sair.
#
# Imprime uma linha por mudança de estado e, no fim, o resumo:
#   pipeline <id> sha <sha> status <status> check-quality <status> <web_url>
#
# Saída:
#   0  pipeline do head terminou e check-quality = success
#   1  pipeline do head terminou, mas não serve: falhou, cancelada, ou
#      check-quality ausente, skipped ou failed
#   2  uso / ambiente
#   3  limite de tempo atingido (o head ainda sem pipeline final)

set -u

MR="${1:-}"
LIMITE="${2:-3600}"
INTERVALO=20

[[ "$MR" =~ ^[0-9]+$ ]] || { echo "uso: $0 <mr_iid> [limite_em_segundos]" >&2; exit 2; }
for cmd in glab jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "falta \`$cmd\` no PATH" >&2; exit 2; }
done

inicio=$(date +%s)
ultimo=""

while :; do
  mr=$(glab mr view "$MR" --output json 2>/dev/null) || mr=""
  if [ -n "$mr" ]; then
    head=$(jq -r '.sha // ""' <<<"$mr")
    pid=$(jq -r '.head_pipeline.id // ""' <<<"$mr")
    psha=$(jq -r '.head_pipeline.sha // ""' <<<"$mr")
    pstatus=$(jq -r '.head_pipeline.status // ""' <<<"$mr")
    purl=$(jq -r '.head_pipeline.web_url // ""' <<<"$mr")

    if [ "$psha" != "$head" ]; then
      estado="aguardando: head ${head:0:8}, head_pipeline ainda ${pid:-nenhuma} (${psha:0:8})"
    else
      estado="pipeline $pid do head ${head:0:8}: $pstatus"
    fi
    if [ "$estado" != "$ultimo" ]; then
      printf '%s  %s\n' "$(date +%H:%M:%S)" "$estado"
      ultimo="$estado"
    fi

    # Só vale a pipeline do head, e só quando ela terminou.
    if [ "$psha" = "$head" ]; then
      case "$pstatus" in
        success|failed|canceled|skipped|manual)
          cq=$(glab api "projects/:id/pipelines/$pid/jobs?per_page=100" 2>/dev/null \
            | jq -r '[.[] | select(.name == "check-quality")][0].status // "ausente"')
          printf 'pipeline %s sha %s status %s check-quality %s %s\n' "$pid" "$head" "$pstatus" "$cq" "$purl"
          [ "$pstatus" = success ] && [ "$cq" = success ] && exit 0
          exit 1
          ;;
      esac
    fi
  else
    printf '%s  não consegui ler a MR !%s (glab); tentando de novo\n' "$(date +%H:%M:%S)" "$MR"
  fi

  if [ $(( $(date +%s) - inicio )) -ge "$LIMITE" ]; then
    printf 'limite de %ss atingido; último estado: %s\n' "$LIMITE" "${ultimo:-nenhum}"
    exit 3
  fi
  sleep "$INTERVALO"
done
