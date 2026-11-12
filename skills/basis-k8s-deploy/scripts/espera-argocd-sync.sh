#!/bin/bash
# Espera uma Application do ArgoCD ficar sincronizada e saudável, na revisão esperada.
#
# SOMENTE LEITURA: `kubectl get application` (e, com --repo, `git fetch` do clone
# informado). Não dispara sync, não lê Secret.
#
# Uso:
#   espera-argocd-sync.sh --context <ctx> --app <app> [--revisao <sha>] [--repo <clone>]
#                         [--namespace <ns>]        (padrão: argocd)
#                         [--limite-s <segundos>]   (padrão: 1800)
#
# Variáveis opcionais: INTERVALO (segundos entre leituras, padrão 15, mínimo 1),
# CARENCIA_DEGRADED (segundos com Degraded na revisão esperada antes do sinal 1,
# padrão 240: o ArgoCD reconcilia a cada 180 s e um rollout em curso passa por
# Degraded sem ter falhado) e REQUEST_TIMEOUT (segundos de cada `kubectl`, padrão 20).
#
# --revisao é o SHA do commit do REPOSITÓRIO QUE O ARGOCD OBSERVA (o `argocd-apps`,
# no nosso caso), inteiro ou prefixo de 7+ caracteres hexadecimais. Num monorepo, o
# app costuma ficar `Synced` numa revisão POSTERIOR à esperada (commits de outros
# apps e do Image Updater). Por isso:
#   - com --repo <clone local do repositório observado>: vale "a revisão do app
#     contém o commit esperado" (`git merge-base --is-ancestor`), com `git fetch`
#     do clone quando algum dos dois commits não existe localmente;
#   - sem --repo: vale IGUALDADE (ou prefixo). Se o app avançar para um commit
#     posterior, o script não reconhece e termina com o sinal 2 no limite.
# Sem --revisao, só exige Synced + Healthy: isso NÃO prova que o commit empurrado
# chegou (o app pode estar Synced+Healthy na revisão anterior).
# Fluxo do Image Updater: o commit do `argocd-apps` é feito pelo Image Updater e o
# agente não o conhece; ali espere pela imagem com `esperar-rollout.sh --imagem`.
#
# Sinal 1 (Degraded ou operação Failed/Error) só vale quando o estado é da revisão
# esperada (ou de uma que a contém); antes disso o script continua esperando.
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
# Imprime uma linha por mudança de estado e, no fim, sempre o resumo:
#   app <app> sinal <nome> sync <s> saude <h> revisao <sha> esperada <sha|-> fase <f>
#
# Saída:
#   0  Synced + Healthy na revisão esperada (ou em qualquer revisão, sem --revisao)
#   1  Degraded por mais que a carência, ou a última operação de sync falhou,
#      em ambos os casos na revisão esperada
#   2  Synced + Healthy, mas sem a revisão esperada, até o limite
#   3  limite de tempo atingido sem nenhum dos casos acima
#  64  uso / ambiente (argumento inválido, falta kubectl, jq ou git, app inexistente
#      ou ilegível: 5 leituras seguidas falharam ou não eram uma Application)
# 129  interrompido por SIGHUP    130  por SIGINT    143  por SIGTERM
#      (nos três, a linha final tem `sinal interrompido`)

set -euo pipefail

CONTEXTO="" APP="" REVISAO="" REPO="" NS="argocd" LIMITE=1800
INTERVALO="${INTERVALO:-15}"
CARENCIA="${CARENCIA_DEGRADED:-240}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-20}"

uso() {
  echo "uso: $0 --context <ctx> --app <app> [--revisao <sha>] [--repo <clone>] [--namespace <ns>] [--limite-s <s>]" >&2
  exit 64
}

while [ $# -gt 0 ]; do
  case "$1" in
    --context|--app|--revisao|--repo|--namespace|-n|--limite-s)
      if [ $# -lt 2 ] || [ -z "$2" ]; then echo "$1 exige um valor" >&2; uso; fi ;;
  esac
  case "$1" in
    --context) CONTEXTO="$2"; shift 2 ;;
    --app) APP="$2"; shift 2 ;;
    --revisao) REVISAO="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --namespace|-n) NS="$2"; shift 2 ;;
    --limite-s) LIMITE="$2"; shift 2 ;;
    *) uso ;;
  esac
done
[ -n "$CONTEXTO" ] && [ -n "$APP" ] || uso
[[ "$CONTEXTO" =~ ^[A-Za-z0-9][A-Za-z0-9._:@/-]*$ ]] || { echo "--context inválido" >&2; uso; }
[[ "$APP" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "--app inválido" >&2; uso; }
[[ "$NS" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { echo "--namespace inválido" >&2; uso; }
[[ "$LIMITE" =~ ^[0-9]{1,7}$ ]] || { echo "--limite-s deve ser um inteiro" >&2; uso; }
[[ "$INTERVALO" =~ ^[0-9]{1,5}$ ]] && [ "$INTERVALO" -ge 1 ] || { echo "INTERVALO deve ser um inteiro >= 1" >&2; uso; }
[[ "$CARENCIA" =~ ^[0-9]{1,7}$ ]] || { echo "CARENCIA_DEGRADED deve ser um inteiro" >&2; uso; }
[[ "$REQUEST_TIMEOUT" =~ ^[0-9]{1,4}$ ]] && [ "$REQUEST_TIMEOUT" -ge 1 ] || { echo "REQUEST_TIMEOUT deve ser um inteiro >= 1" >&2; uso; }
if [ -n "$REVISAO" ]; then
  REVISAO="${REVISAO,,}"
  [[ "$REVISAO" =~ ^[0-9a-f]{7,64}$ ]] || { echo "--revisao deve ser um SHA hexadecimal de 7 a 64 caracteres" >&2; exit 64; }
fi
[ -z "$REPO" ] || [ -n "$REVISAO" ] || { echo "--repo só faz sentido com --revisao" >&2; exit 64; }
CMDS=(kubectl jq); [ -z "$REPO" ] || CMDS+=(git)
for cmd in "${CMDS[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "falta \`$cmd\` no PATH" >&2; exit 64; }
done
if [ -n "$REPO" ]; then
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "--repo não é um clone git: $REPO" >&2; exit 64; }
fi

K=(kubectl --context "$CONTEXTO" -n "$NS" --request-timeout="${REQUEST_TIMEOUT}s")
inicio=$(date +%s)
ultimo=""
falhas_leitura=0
leitura_ok=0
degraded_desde=""
sync="?" saude="?" rev="" fase="-"
esperada="${REVISAO:--}"
buscados=" "
sleep_pid=""

resumo() { # sinal
  printf 'app %s sinal %s sync %s saude %s revisao %s esperada %s fase %s\n' \
    "$APP" "$1" "$sync" "$saude" "${rev:--}" "$esperada" "$fase"
}

interromper() { # código de saída
  [ -z "$sleep_pid" ] || kill "$sleep_pid" 2>/dev/null || true
  resumo interrompido
  exit "$1"
}
trap 'interromper 129' HUP
trap 'interromper 130' INT
trap 'interromper 143' TERM

dormir() { # segundos; guarda o PID do sleep criado aqui para a limpeza
  sleep "$1" &
  sleep_pid=$!
  wait "$sleep_pid" || true
  sleep_pid=""
}

tem_commit() { git -C "$REPO" cat-file -e "$1^{commit}" 2>/dev/null; }

buscar() { # git fetch do clone, no máximo uma vez por commit ausente
  case "$buscados" in *" $1 "*) return 0 ;; esac
  buscados+="$1 "
  if command -v timeout >/dev/null 2>&1; then
    timeout 60 git -C "$REPO" fetch -q origin >/dev/null 2>&1 || true
  else
    git -C "$REPO" fetch -q origin >/dev/null 2>&1 || true
  fi
}

# 0: $1 é a revisão esperada ou a contém; 1: não contém; 2: indeterminado (commit ausente)
contem() {
  local r="$1"
  case "$r" in "$REVISAO"*) return 0 ;; esac
  case "$REVISAO" in "$r"*) [ "${#r}" -ge 7 ] && return 0 ;; esac
  [ -n "$REPO" ] || return 1
  [[ "$r" =~ ^[0-9a-f]{7,64}$ ]] || return 1
  tem_commit "$REVISAO" || buscar "$REVISAO"
  tem_commit "$REVISAO" || return 2
  tem_commit "$r" || buscar "$r"
  tem_commit "$r" || return 2
  local rc=0
  git -C "$REPO" merge-base --is-ancestor "$REVISAO" "$r" 2>/dev/null || rc=$?
  case "$rc" in 0) return 0 ;; 1) return 1 ;; *) return 2 ;; esac
}

# alguma das revisões ($1, separadas por espaço) é a esperada ou a contém?
alguma_contem() {
  local lista r
  [ -n "$REVISAO" ] || return 0
  read -r -a lista <<<"$1"
  for r in ${lista[@]+"${lista[@]}"}; do
    contem "$r" && return 0
  done
  return 1
}

# Alguma revisão da operação coincide com a revisão atual do app (sem --revisao)?
op_e_do_estado() {
  local op atual a o
  read -r -a op <<<"$1"; read -r -a atual <<<"$2"
  for o in ${op[@]+"${op[@]}"}; do
    for a in ${atual[@]+"${atual[@]}"}; do [ "$o" = "$a" ] && return 0; done
  done
  return 1
}

falha_leitura() { # motivo
  falhas_leitura=$((falhas_leitura + 1))
  leitura_ok=0
  if [ "$falhas_leitura" -ge 5 ]; then
    echo "não consegui ler a Application $NS/$APP no contexto $CONTEXTO 5 vezes seguidas: $1" >&2
    resumo ilegivel; exit 64
  fi
  printf '%s  leitura falhou (%s); tentando de novo\n' "$(date +%H:%M:%S)" "$1"
}

# shellcheck disable=SC2016  # `$s` é variável do jq, não do shell
JQ_LEITURA='objects | select(.kind? == "Application") | ((.status | objects) // {}) as $s
  | [ ($s.sync.status // "Desconhecido"),
      ($s.health.status // "Desconhecido"),
      ($s.operationState.phase // "-"),
      ([$s.sync.revision // empty, ($s.sync.revisions // [])[]] | unique | join(" ")),
      ([ ($s.operationState.syncResult | objects | (.revision // empty), (.revisions // [])[]) ] | unique | join(" ")),
      ([ ($s.operationState.operation.sync | objects | (.revision // empty), (.revisions // [])[]) ] | unique | join(" "))
    ] | join("|")'

while :; do
  agora=$(date +%s)
  restante=$((LIMITE - (agora - inicio)))
  if app_json=$("${K[@]}" get application.argoproj.io "$APP" -o json 2>/dev/null); then
    if linha=$(jq -r "$JQ_LEITURA" <<<"$app_json" 2>/dev/null) && [ -n "$linha" ]; then
      falhas_leitura=0 leitura_ok=1
      IFS='|' read -r sync saude fase rev op_sr op_op <<<"$linha"
      op_revs="${op_sr:-${op_op:-$rev}}"

      estado="sync $sync saúde $saude fase $fase revisão ${rev:--}"
      if [ "$estado" != "$ultimo" ]; then printf '%s  %s\n' "$(date +%H:%M:%S)" "$estado"; ultimo="$estado"; fi

      if [ "$sync" = "Synced" ] && [ "$saude" = "Healthy" ] && [ "$fase" != "Running" ] && alguma_contem "$rev"; then
        resumo ok; exit 0
      fi

      # Operação que terminou em falha, e que é da revisão esperada (ou da atual, sem --revisao).
      if [ "$fase" = "Failed" ] || [ "$fase" = "Error" ]; then
        if [ -n "$REVISAO" ]; then alguma_contem "$op_revs" && { resumo falhou; exit 1; }
        else op_e_do_estado "$op_revs" "$rev" && { resumo falhou; exit 1; }
        fi
      fi

      if [ "$saude" = "Degraded" ] && alguma_contem "$rev"; then
        [ -n "$degraded_desde" ] || degraded_desde=$agora
        if [ $((agora - degraded_desde)) -ge "$CARENCIA" ]; then resumo degradado; exit 1; fi
      else
        degraded_desde=""
      fi
    else
      falha_leitura "resposta do kubectl não é uma Application"
    fi
  else
    diag=$("${K[@]}" get application.argoproj.io "$APP" -o json 2>&1 >/dev/null | head -c 200 || true)
    case "$diag" in
      *NotFound*|*"not found"*|*"does not exist"*|*"no context exists"*|*"doesn't have a resource type"*)
        echo "Application $NS/$APP inexistente no contexto $CONTEXTO: $diag" >&2
        resumo ilegivel; exit 64 ;;
    esac
    falha_leitura "kubectl falhou: ${diag//$'\n'/ }"
  fi

  restante=$((LIMITE - ($(date +%s) - inicio)))
  if [ "$restante" -le 0 ]; then
    echo "limite de ${LIMITE}s atingido"
    if [ "$leitura_ok" = 1 ] && [ "$sync" = "Synced" ] && [ "$saude" = "Healthy" ]; then
      resumo revisao-diferente; exit 2
    fi
    resumo limite; exit 3
  fi
  dormir "$(( INTERVALO < restante ? INTERVALO : restante ))"
done
