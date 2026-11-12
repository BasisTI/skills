#!/bin/bash
# Espera os checks do HEAD de um PR no GitHub terminarem e diz se servem de aceite
# (equivalente GitHub do esperar-pipeline-mr.sh).
#
# SOMENTE LEITURA. Funciona de qualquer diretório: o repositório vem do argumento.
#
# Uso:
#   esperar-checks-pr.sh <owner/repo> <pr> [limite_em_segundos]     (padrão: 3600)
#
# Variáveis opcionais: INTERVALO (segundos entre leituras, padrão 20) e
# CARENCIA_SEM_CHECKS (segundos esperando o primeiro check aparecer antes de
# dar o sinal 2, padrão 120).
#
# Existe para que ninguém improvise essa espera: `grep -q pass\|fail` sem aspas
# nunca casou sob zsh e o laço morreu em 8m20s (skills TG-47, 2026-11-09), e
# `sleep 60; gh pr checks 26` é bloqueado pelo harness (orq TG-40; 485 bloqueios
# de `sleep` no levantamento de 2026-11-12). Feito para `run_in_background`
# (Claude Code) ou para o laço dentro do turno (Codex), sem `sleep` do agente.
#
# Os checks são lidos pelo SHA da cabeça do PR (`headRefOid`), relido a cada
# volta: `gh pr checks` não expõe o SHA e, depois de um push, mostra os checks
# do SHA anterior. Os check-runs e os statuses de commit contam juntos.
# Aviso (não muda a saída): o CI de PR no GitHub testa o merge ref, que pode
# estar velho; se o PR está BEHIND/DIRTY em relação à base, o script avisa.
#
# Imprime uma linha por mudança de estado e, no fim, o resumo:
#   pr <repo>#<n> sha <sha> sinal <nome> total <n> ok <n> falhou <n> pendente <n>
#
# Saída:
#   0  todos os checks do head terminaram verdes (success, neutral ou skipped)
#   1  algum check do head falhou (sai assim que o primeiro falha)
#   2  nenhum check apareceu para o head dentro da carência
#   3  limite de tempo atingido (ainda há check pendente)
#  64  uso / ambiente (argumento inválido, falta gh ou jq, PR ilegível)

set -euo pipefail

REPO="${1:-}"
PR="${2:-}"
LIMITE="${3:-3600}"
INTERVALO="${INTERVALO:-20}"
CARENCIA="${CARENCIA_SEM_CHECKS:-120}"

uso() { echo "uso: $0 <owner/repo> <pr> [limite_em_segundos]" >&2; exit 64; }
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || uso
[[ "$PR" =~ ^[0-9]+$ ]] || uso
[[ "$LIMITE" =~ ^[0-9]+$ ]] || uso
for cmd in gh jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "falta \`$cmd\` no PATH" >&2; exit 64; }
done

inicio=$(date +%s)
ultimo=""
falhas_leitura=0
sha=""

resumo() { # sinal total ok falhou pendente
  printf 'pr %s#%s sha %s sinal %s total %s ok %s falhou %s pendente %s\n' \
    "$REPO" "$PR" "$sha" "$1" "$2" "$3" "$4" "$5"
}

while :; do
  if ! pr_json=$(gh pr view "$PR" -R "$REPO" --json headRefOid,mergeStateStatus 2>/dev/null); then
    falhas_leitura=$((falhas_leitura + 1))
    [ "$falhas_leitura" -lt 5 ] || { echo "não consegui ler o PR $REPO#$PR (gh) 5 vezes seguidas" >&2; exit 64; }
    printf '%s  não consegui ler o PR %s#%s (gh); tentando de novo\n' "$(date +%H:%M:%S)" "$REPO" "$PR"
  else
    falhas_leitura=0
    sha=$(jq -r '.headRefOid // ""' <<<"$pr_json")
    merge_estado=$(jq -r '.mergeStateStatus // "UNKNOWN"' <<<"$pr_json")
    [ -n "$sha" ] || { echo "PR $REPO#$PR sem headRefOid" >&2; exit 64; }

    runs=$(gh api --paginate "repos/$REPO/commits/$sha/check-runs?per_page=100" \
      --jq '.check_runs[] | {nome: .name, fim: (.status == "completed"), res: (.conclusion // "")}' \
      2>/dev/null | jq -sc '.') || runs=""
    stat=$(gh api "repos/$REPO/commits/$sha/status" \
      --jq '[.statuses[]? | {nome: .context, fim: (.state != "pending"), res: (.state // "")}]' \
      2>/dev/null) || stat=""

    if [ -n "$runs" ] && [ -n "$stat" ]; then
      checks=$(jq -c -n --argjson a "$runs" --argjson b "$stat" '$a + $b')
      total=$(jq 'length' <<<"$checks")
      # bom: terminou com success, neutral, skipped. ruim: terminou com qualquer outra coisa.
      ok=$(jq '[.[] | select(.fim and (.res == "success" or .res == "neutral" or .res == "skipped"))] | length' <<<"$checks")
      ruim=$(jq '[.[] | select(.fim and (.res != "success" and .res != "neutral" and .res != "skipped"))] | length' <<<"$checks")
      pend=$((total - ok - ruim))

      estado="head ${sha:0:8}: $total checks, $ok ok, $ruim falhou, $pend pendente"
      if [ "$estado" != "$ultimo" ]; then
        printf '%s  %s\n' "$(date +%H:%M:%S)" "$estado"
        ultimo="$estado"
      fi

      if [ "$ruim" -gt 0 ]; then
        jq -r '.[] | select(.fim and (.res != "success" and .res != "neutral" and .res != "skipped")) | "  falhou: \(.nome) (\(.res))"' <<<"$checks"
        resumo falhou "$total" "$ok" "$ruim" "$pend"
        exit 1
      fi
      if [ "$total" -gt 0 ] && [ "$pend" -eq 0 ]; then
        case "$merge_estado" in
          BEHIND|DIRTY)
            printf 'aviso: PR %s em relação à base; os checks de PR testam o merge ref e podem estar velhos\n' "$merge_estado" ;;
        esac
        resumo verde "$total" "$ok" "$ruim" "$pend"
        exit 0
      fi
      if [ "$total" -eq 0 ] && [ $(( $(date +%s) - inicio )) -ge "$CARENCIA" ]; then
        resumo sem-checks 0 0 0 0
        exit 2
      fi
    else
      printf '%s  não consegui ler os checks do head %s (gh api); tentando de novo\n' "$(date +%H:%M:%S)" "${sha:0:8}"
    fi
  fi

  if [ $(( $(date +%s) - inicio )) -ge "$LIMITE" ]; then
    printf 'limite de %ss atingido; último estado: %s\n' "$LIMITE" "${ultimo:-nenhum}"
    resumo limite "${total:-0}" "${ok:-0}" "${ruim:-0}" "${pend:-0}"
    exit 3
  fi
  sleep "$INTERVALO"
done
