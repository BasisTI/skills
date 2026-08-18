#!/usr/bin/env bash
# Reconcilia, numa tela só, o estado da CI de um projeto Basis.
#
# SOMENTE LEITURA. Não dispara pipeline, não altera variável, não abre nem
# fecha MR. Nunca imprime VALOR de variável de CI -- só nome e presença.
#
# Uso:
#   estado-pipeline.sh [branch]
#
# Sem argumento usa a branch atual. Rode de dentro do repositório.
#
# O que ele resolve que a interface não mostra junto:
#   - a pipeline da BRANCH e a da MR aberta lado a lado. Elas divergem, e a da
#     MR aparece `skipped` quando o bump de versão empurrou com `ci.skip` --
#     o que não bloqueia merge e assusta quem não sabe.
#   - quais das variáveis exigidas pelo template EXISTEM, sem revelar valor.
#   - o `ref` do ci-templates em uso, que difere entre projetos.

# Sem `set -e`: a graça é justamente reportar o que falhou, não abortar no
# primeiro comando que devolve não-zero.
set -u

PROBLEMAS=0

titulo() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()     { printf '  \033[32m✓\033[0m %s\n' "$1"; }
alerta() { printf '  \033[33m!\033[0m %s\n' "$1"; PROBLEMAS=$((PROBLEMAS + 1)); }
erro()   { printf '  \033[31m✗\033[0m %s\n' "$1"; PROBLEMAS=$((PROBLEMAS + 1)); }
info()   { printf '    %s\n' "$1"; }

# --- pré-requisitos ----------------------------------------------------------

for cmd in glab jq git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Falta o comando `%s` no PATH. Este script precisa de glab, jq e git.\n' "$cmd" >&2
    exit 2
  fi
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  printf 'Não é um repositório git. Rode de dentro do repositório do projeto.\n' >&2
  exit 2
fi

BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null)}"

# --- 1. identidade -----------------------------------------------------------

titulo "Projeto"

PROJ_JSON=$(glab repo view -F json 2>/dev/null)
if [ -z "$PROJ_JSON" ]; then
  erro "glab não conseguiu ler o projeto. Autenticado? \`glab auth status\`"
  exit 1
fi

PROJ_ID=$(printf '%s' "$PROJ_JSON"   | jq -r '.id // empty')
PROJ_PATH=$(printf '%s' "$PROJ_JSON" | jq -r '.path_with_namespace // .name // empty')

ok "${PROJ_PATH:-?} (id ${PROJ_ID:-?})"
info "branch: $BRANCH"

# --- 2. configuração de CI no repositório ------------------------------------

titulo "Configuração no repositório"

if [ -f .gitlab-ci.yml ]; then
  REF=$(grep -E '^\s*ref:' .gitlab-ci.yml | head -1 | sed 's/.*ref:[[:space:]]*//;s/["'\'']//g')
  if [ -n "$REF" ]; then
    ok "ci-templates em $REF"
  else
    alerta ".gitlab-ci.yml sem \`ref:\` pinado — herda de main, e uma mudança no template atinge o projeto sem janela"
  fi
  MODULO=$(grep -E '^\s*DAGGER_MODULE:' .gitlab-ci.yml | head -1 | sed 's/.*DAGGER_MODULE:[[:space:]]*//;s/["'\'']//g')
  [ -n "$MODULO" ] && info "DAGGER_MODULE sobrescrito: $MODULO"
else
  erro ".gitlab-ci.yml ausente — o projeto não está na CI"
fi

if [ -f ci/pipeline.toml ]; then
  GRUPO=$(grep -E '^\s*group\s*=' ci/pipeline.toml | head -1 | sed 's/.*=[[:space:]]*//;s/"//g')
  ALVOS=$(grep -cE '^\[targets\.' ci/pipeline.toml)
  ok "ci/pipeline.toml — grupo '${GRUPO:-?}', $ALVOS target(s)"
  SONAR_N=$(grep -cE '^\s*sonar\s*=\s*true' ci/pipeline.toml)
  info "targets com sonar: $SONAR_N"
else
  erro "ci/pipeline.toml ausente — sem ele o orchestrator não tem o que buildar"
fi

# --- 3. variáveis exigidas (nome e presença, NUNCA valor) --------------------

titulo "Variáveis exigidas pelo template"

# Três estados distintos, e confundi-los produz alarme falso:
#   sem resposta válida  -> sem permissão, não dá para afirmar nada
#   respondeu vazio      -> nada NESTE nível; as variáveis compartilhadas da Basis
#                           são de instância e não aparecem pela API a não-admin
#   respondeu com chaves -> aí sim dá para cobrar item a item
PRESENTES=""
RESPONDEU=0
ONDE=""

coletar() {
  saida=$(glab api "$1" 2>/dev/null)
  printf '%s' "$saida" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  RESPONDEU=1
  ONDE="${ONDE:+$ONDE, }$2"
  k=$(printf '%s' "$saida" | jq -r '.[].key')
  [ -n "$k" ] && PRESENTES=$(printf '%s\n%s' "$PRESENTES" "$k")
  return 0
}

coletar "projects/$PROJ_ID/variables" "projeto"

# Sobe a hierarquia de grupos: produtos/ponto/repo -> produtos/ponto -> produtos
NS=$(printf '%s' "$PROJ_PATH" | sed 's#/[^/]*$##')
while [ -n "$NS" ] && [ "$NS" != "$PROJ_PATH" ]; do
  ENC=$(printf '%s' "$NS" | sed 's#/#%2F#g')
  coletar "groups/$ENC/variables" "grupo $NS"
  case "$NS" in */*) NS=$(printf '%s' "$NS" | sed 's#/[^/]*$##') ;; *) break ;; esac
done

if [ "$RESPONDEU" -eq 0 ]; then
  alerta "sem permissão para listar variáveis — checagem pulada"
elif [ -z "$(printf '%s' "$PRESENTES" | tr -d '[:space:]')" ]; then
  ok "nenhuma variável definida em $ONDE"
  info "As credenciais compartilhadas (registry, Sonar, status token) costumam ser"
  info "variáveis de INSTÂNCIA, invisíveis pela API a quem não é admin. Vazio aqui"
  info "não significa ausente — se a pipeline autentica, elas existem."
else
  info "consultado: $ONDE"
  for v in EXTERNAL_REGISTRY_URL EXTERNAL_REGISTRY_USER EXTERNAL_REGISTRY_PASSWORD \
           SONAR_HOST SONAR_TOKEN GITLAB_STATUS_TOKEN; do
    if printf '%s\n' "$PRESENTES" | grep -qx "$v"; then
      ok "$v definida"
    else
      info "$v não aparece neste nível (pode ser de instância)"
    fi
  done
  info "(valores nunca são lidos nem impressos)"
fi

# --- 4. pipeline da branch E da MR, lado a lado ------------------------------

titulo "Pipelines"

resumo_pipeline() {
  # $1 = id da pipeline, $2 = rótulo
  pj=$(glab api "projects/$PROJ_ID/pipelines/$1" 2>/dev/null)
  st=$(printf '%s' "$pj" | jq -r '.status // "?"')
  printf '  %-28s #%-8s %s\n' "$2" "$1" "$st"
  jobs=$(glab api "projects/$PROJ_ID/pipelines/$1/jobs" 2>/dev/null)
  if printf '%s' "$jobs" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    printf '%s' "$jobs" | jq -r '.[] | "      " + (.status // "?") + "\t" + (.name // "?")'
  else
    printf '      (nenhum job)\n'
  fi
}

PIPE_BRANCH=$(glab api "projects/$PROJ_ID/pipelines?ref=$BRANCH&per_page=1" 2>/dev/null \
              | jq -r '.[0].id // empty')

MR_IID=$(glab api "projects/$PROJ_ID/merge_requests?source_branch=$BRANCH&state=opened&per_page=1" 2>/dev/null \
         | jq -r '.[0].iid // empty')

if [ -n "$PIPE_BRANCH" ]; then
  resumo_pipeline "$PIPE_BRANCH" "branch $BRANCH"
else
  alerta "nenhuma pipeline para a branch $BRANCH"
fi

if [ -n "$MR_IID" ]; then
  MR=$(glab api "projects/$PROJ_ID/merge_requests/$MR_IID" 2>/dev/null)
  ALVO=$(printf '%s' "$MR" | jq -r '.target_branch // "?"')
  PIPE_MR=$(printf '%s' "$MR" | jq -r '.head_pipeline.id // empty')
  if [ -n "$PIPE_MR" ]; then
    resumo_pipeline "$PIPE_MR" "MR !$MR_IID → $ALVO"
  else
    printf '  %-28s %s\n' "MR !$MR_IID → $ALVO" "sem pipeline no head"
  fi
  if [ "$ALVO" = "main" ]; then
    info "MR para main: NÃO marcar Squash. Pipeline 'skipped' aqui costuma ser o ci.skip do bump de versão."
  fi
else
  info "nenhuma MR aberta a partir desta branch"
fi

# --- 5. trace do primeiro job que falhou -------------------------------------

PRIMEIRA_FALHA=""
for pid in $PIPE_BRANCH ${PIPE_MR:-}; do
  [ -z "$pid" ] && continue
  jid=$(glab api "projects/$PROJ_ID/pipelines/$pid/jobs" 2>/dev/null \
        | jq -r '[.[] | select(.status == "failed")] | .[0].id // empty')
  if [ -n "$jid" ]; then PRIMEIRA_FALHA="$jid"; break; fi
done

if [ -n "$PRIMEIRA_FALHA" ]; then
  titulo "Últimas linhas do primeiro job que falhou (job $PRIMEIRA_FALHA)"
  glab api "projects/$PROJ_ID/jobs/$PRIMEIRA_FALHA/trace" 2>/dev/null | tail -30
  printf '\n'
  info "Leia até o fim antes de concluir: 'cleanup failed' / 'context deadline exceeded'"
  info "é ruído de shutdown do Dagger e pode vir DEPOIS do trabalho ter dado certo."
fi

# --- veredito ----------------------------------------------------------------

titulo "Veredito"
if [ "$PROBLEMAS" -eq 0 ]; then
  ok "nada fora do lugar na configuração"
  exit 0
else
  erro "$PROBLEMAS ponto(s) merecem olhada acima"
  exit 1
fi
