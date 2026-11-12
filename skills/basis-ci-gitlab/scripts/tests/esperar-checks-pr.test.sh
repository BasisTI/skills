#!/bin/bash
# Testa esperar-checks-pr.sh com um `gh` falso no PATH (nada toca o GitHub).
# Uso: bash tests/esperar-checks-pr.test.sh   (também: zsh -c 'bash tests/esperar-checks-pr.test.sh')
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$AQUI/../esperar-checks-pr.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/esperar-checks-pr.XXXXXX")"
trap 'rm -r "$TMP/bin" "$TMP/f" "$TMP/saida" 2>/dev/null || true; rmdir "$TMP" 2>/dev/null || true' EXIT
mkdir -p "$TMP/bin" "$TMP/f"

# gh falso: lê fixtures de $FAKE (pr.json, runs.json, status.json) e aplica --jq com o jq real.
cat > "$TMP/bin/gh" <<'FAKE'
#!/bin/bash
f=""; jqexpr="."
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [ "${args[$i]}" = "--jq" ] && jqexpr="${args[$((i + 1))]}"
done
case "$1 $2" in
  "pr view") [ -e "$FAKE/pr.erro" ] && exit 1; cat "$FAKE/pr.json"; exit 0 ;;
  "api --paginate"|"api repos/"*)
    case "$*" in
      *check-runs*) f="$FAKE/runs.json" ;;
      *status*) f="$FAKE/status.json" ;;
    esac
    jq -c "$jqexpr" "$f" ;;
  *) echo "gh falso: chamada inesperada: $*" >&2; exit 99 ;;
esac
FAKE
chmod +x "$TMP/bin/gh"

falhas=0
caso() { # nome saida_esperada trecho_da_ultima_linha [args...]; fixtures já em $TMP/f
  local nome="$1" esperado="$2" trecho="$3"; shift 3
  local codigo=0
  PATH="$TMP/bin:$PATH" FAKE="$TMP/f" INTERVALO=1 CARENCIA_SEM_CHECKS=2 \
    bash "$SCRIPT" "$@" >"$TMP/saida" 2>&1 || codigo=$?
  local ultima; ultima=$(tail -n 1 "$TMP/saida")
  if [ "$codigo" = "$esperado" ] && [[ "$ultima" == *"$trecho"* ]]; then
    echo "ok   $nome (saída $codigo)"
  else
    echo "FALHA $nome: saída $codigo (esperado $esperado), última linha: $ultima"; cat "$TMP/saida"
    falhas=$((falhas + 1))
  fi
}
pr()     { printf '{"headRefOid":"%s","mergeStateStatus":"%s"}' "$1" "${2:-CLEAN}" > "$TMP/f/pr.json"; }
runs()   { printf '{"check_runs":%s}' "$1" > "$TMP/f/runs.json"; }
status() { printf '{"statuses":%s}' "$1" > "$TMP/f/status.json"; }
run()    { printf '{"name":"%s","status":"%s","conclusion":%s}' "$1" "$2" "$3"; }

sha=aaaaaaaa11111111aaaaaaaa11111111aaaaaaaa

# 0: tudo verde (success, neutral, skipped + status de commit success)
pr $sha; status '[{"context":"sonar","state":"success"}]'
runs "[$(run build completed '"success"'),$(run lint completed '"neutral"'),$(run docs completed '"skipped"')]"
caso verde 0 "sinal verde total 4 ok 4" BasisTI/skills 12

# 1: um falhou, outro ainda pendente: sai na hora
runs "[$(run build completed '"failure"'),$(run lint in_progress null)]"
caso falhou 1 "sinal falhou total 3 ok 1 falhou 1 pendente 1" BasisTI/skills 12

# 1: cancelado e status de commit com erro também contam como falha
runs "[$(run build completed '"cancelled"')]"; status '[]'
caso cancelado 1 "sinal falhou" BasisTI/skills 12
runs "[$(run build completed '"success"')]"; status '[{"context":"sonar","state":"error"}]'
caso status-erro 1 "sinal falhou" BasisTI/skills 12

# 2: nenhum check dentro da carência
runs '[]'; status '[]'
caso sem-checks 2 "sinal sem-checks" BasisTI/skills 12

# 3: limite com check pendente (campo conclusion nulo não derruba o jq)
runs "[$(run build in_progress null)]"
caso limite 3 "sinal limite total 1 ok 0 falhou 0 pendente 1" BasisTI/skills 12 3

# 3: status de commit pendente também segura o verde
runs "[$(run build completed '"success"')]"; status '[{"context":"sonar","state":"pending"}]'
caso status-pendente 3 "pendente 1" BasisTI/skills 12 2

# aviso de base atrasada não muda o sinal
pr $sha BEHIND; status '[]'; runs "[$(run build completed '"success"')]"
caso base-atrasada 0 "sinal verde" BasisTI/skills 12
if grep -q '^aviso: PR BEHIND' "$TMP/saida"; then echo "ok   aviso BEHIND impresso"; else echo "FALHA aviso BEHIND ausente"; falhas=$((falhas + 1)); fi

# o SHA lido é o do head atual (aparece no resumo)
pr bbbbbbbb22222222bbbbbbbb22222222bbbbbbbb
caso sha-do-head 0 "sha bbbbbbbb22222222bbbbbbbb22222222bbbbbbbb" BasisTI/skills 12

# 64: uso e leitura impossível do PR
caso uso 64 "uso:" BasisTI/skills abc
caso repo-invalido 64 "uso:" skills 12
: > "$TMP/f/pr.erro"
caso pr-ilegivel 64 "5 vezes seguidas" BasisTI/skills 12 100

if [ "$falhas" -eq 0 ]; then echo "todos os casos passaram"; else echo "$falhas caso(s) falharam"; exit 1; fi
