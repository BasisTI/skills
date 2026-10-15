#!/usr/bin/env bash
# Espera a mudança empurrada ao argocd-apps chegar aos pods de um Deployment:
# primeiro o template do Deployment passa a ter o que se espera (ConfigMap com
# um texto, imagem com uma tag), depois o rollout termina.
#
# SOMENTE LEITURA: kubectl get e rollout status. Nunca lê Secret; do ConfigMap
# imprime só se o texto apareceu, nunca o conteúdo.
#
# Uso:
#   esperar-rollout.sh --context <ctx> --namespace <ns> --deployment <nome>
#                      [--configmap-contem <texto>] [--imagem <texto>]
#                      [--limite <segundos>]                    (padrão: 900)
#
# Pelo menos uma expectativa (--configmap-contem ou --imagem) é obrigatória:
# sem ela, `rollout status` responde "successfully rolled out" sobre a versão
# ANTIGA, antes de o ArgoCD sincronizar, e a espera termina sem provar nada.
#
# Existe porque, em 2026-10-15 (painel do portal-liven), uma espera improvisada
# rodou 10 minutos sem verificar nada por dois motivos que um laço feito na hora
# repete:
#   - zsh não separa `$ctx` sem aspas em argumentos: `kubectl $ctx get ...`
#     virou um argumento só e todo comando falhou;
#   - o ConfigMap estava num volume `projected`, que
#     `.spec.template.spec.volumes[*].configMap.name` não enxerga.
# Este script é bash explícito (roda igual chamado do bash, zsh ou fish), passa
# argumentos em array e acha o ConfigMap em volume simples, `projected`,
# `envFrom` e `valueFrom`.
#
# Imprime uma linha por mudança de estado e, no fim, sempre o resumo:
#   deployment <ns>/<nome> geração <g> réplicas <prontas>/<desejadas> configmaps <nomes> imagens <imagens>
#
# Saída:
#   0  expectativa no template e rollout concluído (todas as réplicas novas prontas)
#   1  rollout falhou (ProgressDeadlineExceeded ou `rollout status` com erro)
#   2  uso / ambiente (kubectl, jq, contexto ou Deployment inexistente)
#   3  limite de tempo: a expectativa não chegou ao template, ou o rollout não terminou

set -u

CONTEXTO="" NS="" DEPLOY="" TEXTO_CM="" TEXTO_IMG="" LIMITE=900 INTERVALO=15

uso() { echo "uso: $0 --context <ctx> --namespace <ns> --deployment <nome> [--configmap-contem <texto>] [--imagem <texto>] [--limite <s>]" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --context) CONTEXTO="${2:-}"; shift 2 ;;
    --namespace|-n) NS="${2:-}"; shift 2 ;;
    --deployment) DEPLOY="${2:-}"; shift 2 ;;
    --configmap-contem) TEXTO_CM="${2:-}"; shift 2 ;;
    --imagem) TEXTO_IMG="${2:-}"; shift 2 ;;
    --limite) LIMITE="${2:-}"; shift 2 ;;
    *) uso ;;
  esac
done
[ -n "$CONTEXTO" ] && [ -n "$NS" ] && [ -n "$DEPLOY" ] || uso
[ -n "$TEXTO_CM" ] || [ -n "$TEXTO_IMG" ] || { echo "informe --configmap-contem e/ou --imagem: sem expectativa a espera não prova nada" >&2; exit 2; }
[[ "$LIMITE" =~ ^[0-9]+$ ]] || uso
for cmd in kubectl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "falta \`$cmd\` no PATH" >&2; exit 2; }
done

K=(kubectl --context "$CONTEXTO" -n "$NS")
inicio=$(date +%s)
ultimo=""
dep=""

restante() { echo $(( LIMITE - ($(date +%s) - inicio) )); }

ler_deploy() { dep=$("${K[@]}" get deployment "$DEPLOY" -o json 2>/dev/null); }

configmaps() {  # todo ConfigMap que o template referencia, por qualquer caminho
  jq -r '[.spec.template.spec | .. | objects
          | (.configMap?, .configMapRef?, .configMapKeyRef?) | objects | .name // empty]
         | unique | .[]' <<<"$dep"
}

imagens() { jq -r '[.spec.template.spec | (.initContainers // []) + .containers | .[].image] | join(" ")' <<<"$dep"; }

resumo() {
  ler_deploy
  [ -n "$dep" ] || { echo "deployment $NS/$DEPLOY ilegível no resumo"; return; }
  printf 'deployment %s/%s geração %s réplicas %s/%s configmaps %s imagens %s\n' "$NS" "$DEPLOY" \
    "$(jq -r '.metadata.generation' <<<"$dep")" \
    "$(jq -r '.status.updatedReplicas // 0' <<<"$dep")" "$(jq -r '.spec.replicas // 1' <<<"$dep")" \
    "$(configmaps | paste -sd, -)" "$(imagens)"
}

sair() { resumo; exit "$1"; }

ler_deploy
[ -n "$dep" ] || { echo "deployment $NS/$DEPLOY não encontrado no contexto $CONTEXTO" >&2; exit 2; }

# 1. A expectativa chega ao template do Deployment (o ArgoCD sincronizou).
while :; do
  ok_cm=1 ok_img=1 achado=""
  if [ -n "$TEXTO_CM" ]; then
    ok_cm=0
    for cm in $(configmaps); do
      if "${K[@]}" get configmap "$cm" -o json 2>/dev/null \
          | jq -e --arg t "$TEXTO_CM" '(.data // {}) | any(.[]; contains($t))' >/dev/null; then
        ok_cm=1 achado="$cm"; break
      fi
    done
  fi
  if [ -n "$TEXTO_IMG" ]; then
    case " $(imagens) " in *"$TEXTO_IMG"*) ok_img=1 ;; *) ok_img=0 ;; esac
  fi

  if [ "$ok_cm" = 1 ] && [ "$ok_img" = 1 ]; then
    printf '%s  template com a expectativa%s\n' "$(date +%H:%M:%S)" "${achado:+ (configmap $achado)}"
    break
  fi
  estado="aguardando o template:"
  [ -n "$TEXTO_CM" ] && estado+=" configmap $([ "$ok_cm" = 1 ] && echo ok || echo pendente)"
  [ -n "$TEXTO_IMG" ] && estado+=" imagem $([ "$ok_img" = 1 ] && echo ok || echo pendente)"
  [ "$estado" != "$ultimo" ] && { printf '%s  %s\n' "$(date +%H:%M:%S)" "$estado"; ultimo="$estado"; }
  [ "$(restante)" -le 0 ] && { echo "limite de ${LIMITE}s: a expectativa não chegou ao template (o ArgoCD sincronizou?)"; sair 3; }
  sleep "$INTERVALO"
  ler_deploy
done

# 2. O rollout do template novo termina.
r=$(restante); [ "$r" -gt 0 ] || { echo "limite de ${LIMITE}s antes do rollout"; sair 3; }
saida=$("${K[@]}" rollout status deployment/"$DEPLOY" --timeout="${r}s" 2>&1); rc=$?
printf '%s  %s\n' "$(date +%H:%M:%S)" "$(tail -1 <<<"$saida")"
if [ $rc -ne 0 ]; then
  grep -q 'exceeded its progress deadline' <<<"$saida" && sair 1
  [ "$(restante)" -le 0 ] && sair 3
  sair 1
fi
sair 0
