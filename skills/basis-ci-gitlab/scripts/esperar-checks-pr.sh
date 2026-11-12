#!/bin/bash
# Espera os checks do HEAD de um PR no GitHub terminarem e diz se servem de aceite
# (equivalente GitHub do esperar-pipeline-mr.sh).
#
# SOMENTE LEITURA. Funciona de qualquer diretório: o repositório vem do argumento.
#
# Uso:
#   esperar-checks-pr.sh <owner/repo> <pr> [limite_em_segundos]     (padrão: 3600)
#
# Variáveis opcionais (inteiros): INTERVALO (segundos entre leituras, padrão 20,
# mínimo 1) e CARENCIA_SEM_CHECKS (segundos esperando o primeiro check de um head
# aparecer antes do sinal 2, padrão 120; recomeça a cada troca de head).
#
# Existe para que ninguém improvise essa espera: `grep -q pass\|fail` sem aspas
# nunca casou sob zsh e o laço morreu em 8m20s (skills TG-47, 2026-11-09), e
# `sleep 60; gh pr checks 26` é bloqueado pelo harness (orq TG-40; 485 bloqueios
# de `sleep` no levantamento de 2026-11-12). Feito para `run_in_background`
# (Claude Code) ou para o laço dentro do turno (Codex), sem `sleep` do agente.
#
# Os checks são lidos pelo SHA da cabeça do PR (`headRefOid`), relido a cada
# volta: `gh pr checks` não expõe o SHA. Check-runs e statuses de commit contam
# juntos. Fechar/reabrir ou reexecutar o CI no mesmo SHA cria execuções novas
# sem apagar as antigas; vale só a mais recente de cada check (por nome e app;
# por `context` nos statuses). Se o head muda durante a espera, a leitura segue
# o head novo e a carência recomeça.
#
# Avisos (não mudam a saída): base atrasada, detectada por `behind_by` de
# `compare/<base>...<head>` (o CI de PR testa o merge ref, que pode estar velho;
# a solução é trazer a base e esperar de novo), conflito com a base (DIRTY) e PR
# fechado ou mesclado durante a espera.
#
# Limite conhecido: o verde sai quando todos os checks JÁ REGISTRADOS terminaram.
# Job que só nasce depois de outro (`needs`) ou status externo que chega tarde
# pode fazer o 0 sair cedo. Nos repositórios da Basis hoje os jobs de cada rodada
# nascem juntos, sem `needs`; ao surgir um que não seja assim, revise esta regra.
# `skipped` e `neutral` contam como verde.
#
# Imprime uma linha por mudança de estado e, no fim, o resumo:
#   pr <repo>#<n> sha <sha> sinal <nome> total <n> ok <n> falhou <n> pendente <n>
#
# Saída:
#   0  todos os checks do head terminaram verdes (success, neutral ou skipped)
#   1  algum check do head falhou (sai assim que o primeiro falha)
#   2  nenhum check apareceu para o head dentro da carência
#   3  limite de tempo atingido (ainda há check pendente)
#  64  uso / ambiente (argumento inválido, falta gh ou jq, `gh` falhando
#      várias vezes seguidas)

set -euo pipefail

REPO="${1:-}"
PR="${2:-}"
LIMITE="${3:-3600}"
INTERVALO="${INTERVALO:-20}"
CARENCIA="${CARENCIA_SEM_CHECKS:-120}"
MAX_FALHAS_LEITURA=8

uso() { echo "uso: $0 <owner/repo> <pr> [limite_em_segundos]" >&2; exit 64; }
inteiro() { [[ "$1" =~ ^[0-9]{1,6}$ ]]; }

[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || uso
[[ "$REPO" != ../* && "$REPO" != */.. && "$REPO" != ./* && "$REPO" != */. ]] || uso
inteiro "$PR" || uso
inteiro "$LIMITE" || uso
inteiro "$INTERVALO" && [ "$INTERVALO" -ge 1 ] || { echo "INTERVALO inválido: $INTERVALO" >&2; exit 64; }
inteiro "$CARENCIA" || { echo "CARENCIA_SEM_CHECKS inválida: $CARENCIA" >&2; exit 64; }
for cmd in gh jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "falta \`$cmd\` no PATH" >&2; exit 64; }
done

# Cada chamada ao gh tem prazo próprio, para o limite valer com o gh pendurado.
GH=(gh)
if command -v timeout >/dev/null 2>&1; then GH=(timeout 60 gh); fi

agora() { date +%s; }
inicio=$(agora)
sha=""
desde=$inicio          # início da carência do head atual
ultimo=""
avisou_estado=""
falhas_pr=0
falhas_checks=0
total=0 ok=0 ruim=0 pend=0

resumo() { # sinal
  printf 'pr %s#%s sha %s sinal %s total %s ok %s falhou %s pendente %s\n' \
    "$REPO" "$PR" "$sha" "$1" "$total" "$ok" "$ruim" "$pend"
}

# Verde = terminou com success, neutral ou skipped.
FILTRO_BOM='select(.fim and (.res == "success" or .res == "neutral" or .res == "skipped"))'
FILTRO_RUIM='select(.fim and (.res != "success" and .res != "neutral" and .res != "skipped"))'

while :; do
  if pr_json=$("${GH[@]}" pr view "$PR" -R "$REPO" --json headRefOid,baseRefName,state,mergeStateStatus 2>/dev/null) \
     && novo=$(jq -r '.headRefOid // ""' <<<"$pr_json" 2>/dev/null) && [ -n "$novo" ]; then
    falhas_pr=0
    base=$(jq -r '.baseRefName // ""' <<<"$pr_json")
    pr_estado=$(jq -r '.state // "OPEN"' <<<"$pr_json")
    merge_estado=$(jq -r '.mergeStateStatus // "UNKNOWN"' <<<"$pr_json")

    if [ "$novo" != "$sha" ]; then
      [ -z "$sha" ] || printf '%s  head mudou: %s -> %s; carência recomeça\n' "$(date +%H:%M:%S)" "${sha:0:8}" "${novo:0:8}"
      sha="$novo"; desde=$(agora); ultimo=""; falhas_checks=0
      total=0 ok=0 ruim=0 pend=0
      if [ -n "$base" ] && behind=$("${GH[@]}" api "repos/$REPO/compare/$base...$sha" --jq '.behind_by // 0' 2>/dev/null) \
         && [[ "$behind" =~ ^[0-9]+$ ]]; then
        if [ "$behind" -gt 0 ]; then
          printf 'aviso: head %s está %s commit(s) atrás de %s; o CI de PR testa o merge ref e pode estar velho (traga a base e espere de novo)\n' "${sha:0:8}" "$behind" "$base"
        elif [ "$merge_estado" = DIRTY ]; then
          printf 'aviso: PR em conflito com %s (DIRTY)\n' "$base"
        fi
      else
        printf 'aviso: não consegui comparar o head com a base; atraso não verificado\n'
      fi
    fi
    if [ "$pr_estado" != OPEN ] && [ "$avisou_estado" != "$pr_estado" ]; then
      printf 'aviso: PR %s durante a espera; os checks do head continuam valendo\n' "$pr_estado"
      avisou_estado="$pr_estado"
    fi

    if runs=$("${GH[@]}" api --paginate "repos/$REPO/commits/$sha/check-runs?per_page=100" \
          --jq '.check_runs[] | {id: .id, nome: .name, app: (.app.slug // ""), fim: (.status == "completed"), res: (.conclusion // "")}' 2>/dev/null \
          | jq -sc 'group_by([.nome, .app]) | map(max_by(.id)) | map(del(.id, .app))' 2>/dev/null) \
       && stat=$("${GH[@]}" api "repos/$REPO/commits/$sha/status?per_page=100" \
          --jq '[.statuses[]? | {nome: .context, fim: (.state != "pending"), res: (.state // "")}]' 2>/dev/null) \
       && checks=$(jq -c -n --argjson a "$runs" --argjson b "$stat" '$a + $b' 2>/dev/null); then
      falhas_checks=0
      total=$(jq 'length' <<<"$checks")
      ok=$(jq "[.[] | $FILTRO_BOM] | length" <<<"$checks")
      ruim=$(jq "[.[] | $FILTRO_RUIM] | length" <<<"$checks")
      pend=$((total - ok - ruim))

      estado="head ${sha:0:8}: $total checks, $ok ok, $ruim falhou, $pend pendente"
      if [ "$estado" != "$ultimo" ]; then
        printf '%s  %s\n' "$(date +%H:%M:%S)" "$estado"
        ultimo="$estado"
      fi

      if [ "$ruim" -gt 0 ]; then
        jq -r ".[] | $FILTRO_RUIM | \"  falhou: \\(.nome) (\\(.res))\"" <<<"$checks"
        resumo falhou
        exit 1
      fi
      if [ "$total" -gt 0 ] && [ "$pend" -eq 0 ]; then
        resumo verde
        exit 0
      fi
      if [ "$total" -eq 0 ] && [ $(( $(agora) - desde )) -ge "$CARENCIA" ]; then
        resumo sem-checks
        exit 2
      fi
    else
      falhas_checks=$((falhas_checks + 1))
      if [ "$falhas_checks" -ge "$MAX_FALHAS_LEITURA" ]; then
        echo "não consegui ler os checks do head ${sha:0:8} ($REPO) $falhas_checks vezes seguidas (gh api)" >&2
        exit 64
      fi
      printf '%s  não consegui ler os checks do head %s (gh api); tentando de novo\n' "$(date +%H:%M:%S)" "${sha:0:8}"
    fi
  else
    falhas_pr=$((falhas_pr + 1))
    if [ "$falhas_pr" -ge "$MAX_FALHAS_LEITURA" ]; then
      echo "não consegui ler o PR $REPO#$PR (gh) $falhas_pr vezes seguidas" >&2
      exit 64
    fi
    printf '%s  não consegui ler o PR %s#%s (gh); tentando de novo\n' "$(date +%H:%M:%S)" "$REPO" "$PR"
  fi

  if [ $(( $(agora) - inicio )) -ge "$LIMITE" ]; then
    printf 'limite de %ss atingido; último estado: %s\n' "$LIMITE" "${ultimo:-nenhum}"
    resumo limite
    exit 3
  fi
  sleep "$INTERVALO"
done
