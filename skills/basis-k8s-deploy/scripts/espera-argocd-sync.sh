#!/bin/bash
# Espera uma Application do ArgoCD ficar sincronizada e saudável, na revisão esperada.
#
# SOMENTE LEITURA: `kubectl get application`. Não dispara sync, não lê Secret.
#
# Uso:
#   espera-argocd-sync.sh --context <ctx> --app <app> [--revisao <sha>]
#                         [--namespace <ns>]        (padrão: argocd)
#                         [--limite-s <segundos>]   (padrão: 1800)
#
# Variáveis opcionais: INTERVALO (segundos entre leituras, padrão 15) e
# CARENCIA_DEGRADED (segundos com Degraded antes do sinal 1, padrão 60: um
# rollout em curso passa por Degraded sem ter falhado).
#
# --revisao aceita o SHA inteiro ou um prefixo de 7+ caracteres e compara com
# `status.sync.revision` (ou, em app com várias fontes, com qualquer item de
# `status.sync.revisions`). Sem --revisao, só exige Synced + Healthy: isso NÃO
# prova que o commit que você acabou de empurrar chegou, porque o app pode estar
# Synced+Healthy na revisão anterior até o ArgoCD enxergar o push. Prefira sempre
# passar --revisao.
#
# Existe porque o laço improvisado de sync do ArgoCD morreu com
# `jq: error: Cannot iterate over null` (campo de `status.sync`/`status.health`
# ausente enquanto o app ainda não foi lido pelo controller) e porque
# `K="kubectl --context ... -n ..."; $K get ...` falha sob zsh (77 "command not
# found" no levantamento de 2026-11-12: zsh não separa palavras de variável).
# Este script é bash explícito, passa o kubectl em array e usa `// valor` em todo
# campo opcional. Feito para `run_in_background` (Claude Code) ou para o laço
# dentro do turno (Codex), sem `sleep` do agente.
#
# Imprime uma linha por mudança de estado e, no fim, o resumo:
#   app <app> sinal <nome> sync <s> saude <h> revisao <sha> esperada <sha|-> fase <f>
#
# Saída:
#   0  Synced + Healthy na revisão esperada (ou em qualquer revisão, sem --revisao)
#   1  Degraded por mais que a carência, ou a última operação de sync falhou
#   2  Synced + Healthy, mas em outra revisão, até o limite (o ArgoCD não pegou o push?)
#   3  limite de tempo atingido sem nenhum dos casos acima
#  64  uso / ambiente (argumento inválido, falta kubectl ou jq, app ilegível)

set -euo pipefail

CONTEXTO="" APP="" REVISAO="" NS="argocd" LIMITE=1800
INTERVALO="${INTERVALO:-15}"
CARENCIA="${CARENCIA_DEGRADED:-60}"

uso() {
  echo "uso: $0 --context <ctx> --app <app> [--revisao <sha>] [--namespace <ns>] [--limite-s <s>]" >&2
  exit 64
}

while [ $# -gt 0 ]; do
  case "$1" in
    --context) CONTEXTO="${2:-}"; shift 2 ;;
    --app) APP="${2:-}"; shift 2 ;;
    --revisao) REVISAO="${2:-}"; shift 2 ;;
    --namespace|-n) NS="${2:-}"; shift 2 ;;
    --limite-s) LIMITE="${2:-}"; shift 2 ;;
    *) uso ;;
  esac
done
[ -n "$CONTEXTO" ] && [ -n "$APP" ] && [ -n "$NS" ] || uso
[[ "$LIMITE" =~ ^[0-9]+$ ]] || uso
[[ "$INTERVALO" =~ ^[0-9]+$ ]] || uso
[[ "$CARENCIA" =~ ^[0-9]+$ ]] || uso
[ -z "$REVISAO" ] || [[ "$REVISAO" =~ ^[0-9a-fA-F]{7,64}$ ]] || { echo "--revisao deve ser um SHA hexadecimal de 7 a 64 caracteres" >&2; exit 64; }
for cmd in kubectl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "falta \`$cmd\` no PATH" >&2; exit 64; }
done

K=(kubectl --context "$CONTEXTO" -n "$NS")
inicio=$(date +%s)
ultimo=""
falhas_leitura=0
degraded_desde=""
sync="?" saude="?" rev="" fase="-"
esperada="${REVISAO:--}"

resumo() { # sinal
  printf 'app %s sinal %s sync %s saude %s revisao %s esperada %s fase %s\n' \
    "$APP" "$1" "$sync" "$saude" "${rev:--}" "$esperada" "$fase"
}

na_revisao() { # a revisão lida bate com a esperada (prefixo nos dois sentidos)
  [ -z "$REVISAO" ] && return 0
  local r
  for r in $rev; do
    case "$r" in "$REVISAO"*) return 0 ;; esac
    case "$REVISAO" in "$r"*) [ "${#r}" -ge 7 ] && return 0 ;; esac
  done
  return 1
}

while :; do
  agora=$(date +%s)
  if ! app_json=$("${K[@]}" get application.argoproj.io "$APP" -o json 2>/dev/null); then
    falhas_leitura=$((falhas_leitura + 1))
    [ "$falhas_leitura" -lt 5 ] || { echo "não consegui ler a Application $NS/$APP no contexto $CONTEXTO 5 vezes seguidas" >&2; exit 64; }
    printf '%s  não consegui ler a Application %s/%s; tentando de novo\n' "$(date +%H:%M:%S)" "$NS" "$APP"
  else
    falhas_leitura=0
    sync=$(jq -r '.status.sync.status // "Desconhecido"' <<<"$app_json")
    saude=$(jq -r '.status.health.status // "Desconhecido"' <<<"$app_json")
    rev=$(jq -r '[.status.sync.revision // empty, (.status.sync.revisions // [])[]] | unique | join(" ")' <<<"$app_json")
    fase=$(jq -r '.status.operationState.phase // "-"' <<<"$app_json")

    estado="sync $sync saúde $saude fase $fase revisão ${rev:--}"
    [ "$estado" != "$ultimo" ] && { printf '%s  %s\n' "$(date +%H:%M:%S)" "$estado"; ultimo="$estado"; }

    if [ "$sync" = "Synced" ] && [ "$saude" = "Healthy" ] && na_revisao; then
      resumo ok; exit 0
    fi

    # Operação de sync que terminou em falha na revisão esperada (ou em qualquer, sem --revisao).
    if [ "$fase" = "Failed" ] || [ "$fase" = "Error" ]; then
      op_rev=$(jq -r '.status.operationState.syncResult.revision // ""' <<<"$app_json")
      if [ -z "$REVISAO" ] || [ -z "$op_rev" ] || [[ "$op_rev" == "$REVISAO"* || "$REVISAO" == "$op_rev"* ]]; then
        resumo degradado; exit 1
      fi
    fi

    if [ "$saude" = "Degraded" ]; then
      [ -n "$degraded_desde" ] || degraded_desde=$agora
      if [ $((agora - degraded_desde)) -ge "$CARENCIA" ]; then
        resumo degradado; exit 1
      fi
    else
      degraded_desde=""
    fi
  fi

  if [ $((agora - inicio)) -ge "$LIMITE" ]; then
    echo "limite de ${LIMITE}s atingido"
    if [ "$sync" = "Synced" ] && [ "$saude" = "Healthy" ]; then
      resumo revisao-diferente; exit 2
    fi
    resumo limite; exit 3
  fi
  sleep "$INTERVALO"
done
