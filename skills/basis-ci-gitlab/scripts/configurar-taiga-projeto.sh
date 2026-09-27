#!/usr/bin/env bash
# Prepara o board de um projeto no Taiga para o fluxo da story desta skill:
# os status opcionais `In revision` e `Waiting for deployment` e os campos
# customizados de User Story que guardam o registro de início e o de teste
# (references/taiga-mcp.md).
#
# Por padrão SÓ MOSTRA o plano. Grava apenas com --apply.
#
# Uso:
#   configurar-taiga-projeto.sh <project_id> [--apply]
#
# Credencial, por ambiente (nunca por argumento, para não cair no histórico):
#   TAIGA_BASE_URL                  ex.: https://agile.basis.com.br
#   TAIGA_TOKEN                     token de uma sessão já autenticada, ou
#   TAIGA_USERNAME + TAIGA_PASSWORD para autenticar em /auth
#
# Quem aplica precisa de `admin_project_values` no projeto. A conta de serviço
# do servidor MCP normalmente NÃO tem: rode com a credencial de um admin do
# projeto. O script confere a permissão antes de gravar.
#
# Idempotente: status e campo que já existem (mesmo nome, sem diferenciar
# maiúsculas) são mantidos como estão. Rodar de novo não duplica nada.
#
# Saída: 0 feito (ou plano sem pendência), 1 falha na API, 2 uso/ambiente,
#        3 sem permissão, 4 board fora do esperado (status âncora ausente).

set -u

APPLY=0
PROJECT=""
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) PROJECT="$arg" ;;
  esac
done

falha() { printf '✗ %s\n' "$1" >&2; exit "${2:-1}"; }

[[ "$PROJECT" =~ ^[0-9]+$ ]] || falha "Informe o id numérico do projeto no Taiga (ver o AGENTS.md do repositório)." 2
for cmd in curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || falha "Falta \`$cmd\` no PATH." 2
done
[ -n "${TAIGA_BASE_URL:-}" ] || falha "Defina TAIGA_BASE_URL." 2

API="${TAIGA_BASE_URL%/}/api/v1"

# --- autenticação --------------------------------------------------------------

TOKEN="${TAIGA_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  [ -n "${TAIGA_USERNAME:-}" ] && [ -n "${TAIGA_PASSWORD:-}" ] \
    || falha "Defina TAIGA_TOKEN, ou TAIGA_USERNAME e TAIGA_PASSWORD." 2
  TOKEN=$(jq -n --arg u "$TAIGA_USERNAME" --arg p "$TAIGA_PASSWORD" \
      '{type: "normal", username: $u, password: $p}' \
    | curl -s -X POST -H 'Content-Type: application/json' -d @- "$API/auth" \
    | jq -r '.auth_token // empty')
  [ -n "$TOKEN" ] || falha "Autenticação recusada em $API/auth." 1
fi

# Chamada à API: método, caminho, corpo opcional. Falha alto em HTTP >= 400,
# mostrando o corpo da resposta (que nunca contém o token).
api() {
  local metodo="$1" caminho="$2" corpo="${3:-}" resp codigo
  if [ -n "$corpo" ]; then
    resp=$(curl -s -w '\n%{http_code}' -X "$metodo" -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' -d "$corpo" "$API/$caminho")
  else
    resp=$(curl -s -w '\n%{http_code}' -X "$metodo" -H "Authorization: Bearer $TOKEN" "$API/$caminho")
  fi
  codigo=${resp##*$'\n'}
  resp=${resp%$'\n'*}
  if [ "$codigo" -ge 400 ]; then
    printf '✗ %s %s → HTTP %s\n%s\n' "$metodo" "$caminho" "$codigo" "$resp" >&2
    return 1
  fi
  printf '%s' "$resp"
}

# --- estado atual --------------------------------------------------------------

PROJ=$(api GET "projects/$PROJECT") || exit 1
NOME=$(jq -r '.name' <<<"$PROJ")
ADMIN=$(jq -r 'if (.my_permissions | index("admin_project_values")) then "sim" else "não" end' <<<"$PROJ")
STATUSES=$(api GET "userstory-statuses?project=$PROJECT") || exit 1
ATTRS=$(api GET "userstory-custom-attributes?project=$PROJECT") || exit 1

printf 'Projeto: %s (id %s) — admin_project_values: %s\n' "$NOME" "$PROJECT" "$ADMIN"
printf 'Modo: %s\n\n' "$([ $APPLY -eq 1 ] && echo 'APLICAR' || echo 'plano (nada é gravado; use --apply)')"

tem_status() { jq -e --arg n "$1" 'any(.[]; (.name | ascii_downcase) == ($n | ascii_downcase))' <<<"$STATUSES" >/dev/null; }
tem_attr()   { jq -e --arg n "$1" 'any(.[]; (.name | ascii_downcase) == ($n | ascii_downcase))' <<<"$ATTRS" >/dev/null; }

# --- o que o fluxo precisa -----------------------------------------------------

# Status novo | cor | slug do status existente depois do qual ele entra.
STATUS_NOVOS=(
  "In revision|#5178D3|in-progress"
  "Waiting for deployment|#40A8E4|ready-for-test"
)

# Campo | tipo do Taiga | descrição.
CAMPOS=(
  "Início da implementação|date|Registro de início: data em que o executor começou de fato (a hora exata fica no histórico da story)"
  "Executor|text|Registro de início: agente + modelo, ou pessoa"
  "Worktree|text|Registro de início: branch TG-xxx e caminho do worktree"
  "Testado em staging|checkbox|Registro de teste: a versão atual foi testada em staging"
  "Testado por|text|Registro de teste: quem testou"
  "Data do teste|date|Registro de teste: data do teste em staging"
)

PENDENTE=0

printf 'Status de User Story\n'
for linha in "${STATUS_NOVOS[@]}"; do
  IFS='|' read -r nome cor ancora <<<"$linha"
  if tem_status "$nome"; then
    printf '  = %s (já existe)\n' "$nome"
    continue
  fi
  jq -e --arg s "$ancora" 'any(.[]; .slug == $s)' <<<"$STATUSES" >/dev/null \
    || falha "Não há status com slug \`$ancora\` para posicionar \`$nome\`. Board fora do padrão: confira com quem administra o projeto." 4
  printf '  + %s (depois de `%s`)\n' "$nome" "$ancora"
  PENDENTE=1
done

printf '\nCampos customizados de User Story\n'
for linha in "${CAMPOS[@]}"; do
  IFS='|' read -r nome tipo _ <<<"$linha"
  if tem_attr "$nome"; then
    printf '  = %s (já existe, tipo %s)\n' "$nome" "$(jq -r --arg n "$nome" '.[] | select((.name | ascii_downcase) == ($n | ascii_downcase)) | .type' <<<"$ATTRS")"
  else
    printf '  + %s (%s)\n' "$nome" "$tipo"
    PENDENTE=1
  fi
done

if [ $PENDENTE -eq 0 ]; then
  printf '\nNada a fazer: o board já está configurado.\n'
  exit 0
fi
if [ $APPLY -eq 0 ]; then
  printf '\nPlano apenas. Para gravar: %s %s --apply\n' "$0" "$PROJECT"
  [ "$ADMIN" = "sim" ] || printf 'Atenção: esta credencial não tem admin_project_values; o --apply vai recusar.\n'
  exit 0
fi
[ "$ADMIN" = "sim" ] || falha "Esta credencial não tem admin_project_values no projeto $PROJECT. Rode com a de um admin." 3

# --- aplicar -------------------------------------------------------------------

printf '\nAplicando…\n'

for linha in "${STATUS_NOVOS[@]}"; do
  IFS='|' read -r nome cor ancora <<<"$linha"
  tem_status "$nome" && continue
  corpo=$(jq -n --argjson p "$PROJECT" --arg n "$nome" --arg c "$cor" \
    '{project: $p, name: $n, color: $c, is_closed: false, is_archived: false}')
  novo=$(api POST "userstory-statuses" "$corpo") || exit 1
  novo_id=$(jq -r '.id' <<<"$novo")
  printf '  ✓ status %s criado (id %s)\n' "$nome" "$novo_id"
  # Reordena: o novo entra logo depois da âncora, o resto mantém a sequência.
  STATUSES=$(jq --argjson novo "$novo" --arg a "$ancora" '
    sort_by(.order)
    | map(if .slug == $a then ., $novo else . end)
    | to_entries | map(.value.order = .key + 1 | .value)' <<<"$STATUSES")
  ordem=$(jq -c --argjson p "$PROJECT" \
    '{project: $p, bulk_userstory_statuses: [to_entries[] | [.value.id, .key + 1]]}' <<<"$STATUSES")
  api POST "userstory-statuses/bulk_update_order" "$ordem" >/dev/null || exit 1
done

ordem_attr=$(jq 'map(.order) | max // 0' <<<"$ATTRS")
for linha in "${CAMPOS[@]}"; do
  IFS='|' read -r nome tipo descricao <<<"$linha"
  tem_attr "$nome" && continue
  ordem_attr=$((ordem_attr + 1))
  corpo=$(jq -n --argjson p "$PROJECT" --arg n "$nome" --arg t "$tipo" --arg d "$descricao" --argjson o "$ordem_attr" \
    '{project: $p, name: $n, type: $t, description: $d, order: $o}')
  api POST "userstory-custom-attributes" "$corpo" >/dev/null || exit 1
  printf '  ✓ campo %s (%s) criado\n' "$nome" "$tipo"
done

# --- conferir, relendo da API --------------------------------------------------

printf '\nEstado final\n'
api GET "userstory-statuses?project=$PROJECT" \
  | jq -r 'sort_by(.order)[] | "  \(.order). \(.name)\(if .is_closed then " (fechado)" else "" end)\(if .is_archived then " (arquivado)" else "" end)"'
api GET "userstory-custom-attributes?project=$PROJECT" \
  | jq -r 'sort_by(.order)[] | "  • \(.name) (\(.type), id \(.id))"'
