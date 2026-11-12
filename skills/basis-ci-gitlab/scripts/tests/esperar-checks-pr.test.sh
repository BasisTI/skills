#!/bin/bash
# Testa esperar-checks-pr.sh com um `gh` falso no PATH (nada toca o GitHub).
# Uso: bash tests/esperar-checks-pr.test.sh   (também: zsh -c 'bash tests/esperar-checks-pr.test.sh')
#
# Fixtures em $FAKE. Para cada tipo de leitura (pr, runs, status, compare) o gh
# falso conta as chamadas: a n-ésima usa `<tipo>.<n>.json` se existir; senão,
# `<tipo>.json` (e, para runs/status, `<tipo>.<sha>.json` tem prioridade, o que
# prova que o script consulta o SHA do head). Fixture que muda entre leituras
# simula push, reexecução e check que nasce tarde.
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$AQUI/../esperar-checks-pr.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/esperar-checks-pr.XXXXXX")"
trap 'rm -r "$TMP/bin" "$TMP/f" "$TMP/saida" 2>/dev/null || true; rmdir "$TMP" 2>/dev/null || true' EXIT
mkdir -p "$TMP/bin" "$TMP/f"

cat > "$TMP/bin/gh" <<'FAKE'
#!/bin/bash
jqexpr="."; sha=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [ "${args[$i]}" = "--jq" ] && jqexpr="${args[$((i + 1))]}"
done
case "$*" in
  "pr view"*) tipo=pr ;;
  *compare*) tipo=compare ;;
  *check-runs*) tipo=runs ;;
  *status*) tipo=status ;;
  *) echo "gh falso: chamada inesperada: $*" >&2; exit 99 ;;
esac
case "$tipo" in
  runs|status) sha=$(sed -E 's#.*commits/([0-9a-f]+)/.*#\1#' <<<"$*" | cut -d' ' -f1) ;;
esac
n=$(( $(cat "$FAKE/n.$tipo" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE/n.$tipo"
if [ -e "$FAKE/$tipo.erro" ]; then exit 1; fi
for f in "$FAKE/$tipo.$n.json" "$FAKE/$tipo.$sha.json" "$FAKE/$tipo.json"; do
  [ -e "$f" ] || continue
  if [ "$tipo" = pr ]; then cat "$f"; else jq -c "$jqexpr" "$f"; fi
  exit 0
done
echo "gh falso: sem fixture para $tipo (n=$n sha=$sha)" >&2; exit 1
FAKE
chmod +x "$TMP/bin/gh"

falhas=0
limpa() { find "$TMP/f" -type f -exec rm {} +; }
caso() { # nome saida_esperada trecho_da_ultima_linha [args...]
  local nome="$1" esperado="$2" trecho="$3"; shift 3
  local codigo=0
  find "$TMP/f" -name 'n.*' -exec rm {} +
  PATH="$TMP/bin:$PATH" FAKE="$TMP/f" INTERVALO="${INT:-1}" CARENCIA_SEM_CHECKS="${CAR:-2}" \
    bash "$SCRIPT" "$@" >"$TMP/saida" 2>&1 || codigo=$?
  local ultima; ultima=$(tail -n 1 "$TMP/saida")
  if [ "$codigo" = "$esperado" ] && [[ "$ultima" == *"$trecho"* ]]; then
    echo "ok   $nome (saída $codigo)"
  else
    echo "FALHA $nome: saída $codigo (esperado $esperado), última linha: $ultima"; cat "$TMP/saida"
    falhas=$((falhas + 1))
  fi
}
tem() { # nome trecho: a saída completa do último caso contém o trecho
  if grep -qF -- "$2" "$TMP/saida"; then echo "ok   $1"; else echo "FALHA $1: sem \"$2\""; cat "$TMP/saida"; falhas=$((falhas + 1)); fi
}
pr()      { printf '{"headRefOid":"%s","baseRefName":"main","state":"%s","mergeStateStatus":"%s"}' "$1" "${3:-OPEN}" "${2:-CLEAN}" > "$TMP/f/${4:-pr.json}"; }
runs()    { printf '{"check_runs":%s}' "$1" > "$TMP/f/${2:-runs.json}"; }
status()  { printf '{"statuses":%s}' "$1" > "$TMP/f/${2:-status.json}"; }
behind()  { printf '{"behind_by":%s}' "$1" > "$TMP/f/${2:-compare.json}"; }
run()     { # id nome status conclusão-json [app]
  printf '{"id":%s,"name":"%s","status":"%s","conclusion":%s,"app":{"slug":"%s"}}' "$1" "$2" "$3" "$4" "${5:-github-actions}"; }
base() { limpa; pr "$sha"; behind 0; status '[]'; }

sha=aaaaaaaa11111111aaaaaaaa11111111aaaaaaaa
shb=bbbbbbbb22222222bbbbbbbb22222222bbbbbbbb

# 0: tudo verde (success, neutral, skipped + status de commit success)
base; status '[{"context":"sonar","state":"success"}]'
runs "[$(run 1 build completed '"success"'),$(run 2 lint completed '"neutral"'),$(run 3 docs completed '"skipped"')]"
caso verde 0 "sinal verde total 4 ok 4" BasisTI/skills 12

# 1: um falhou, outro ainda pendente: sai na hora
base; runs "[$(run 1 build completed '"failure"'),$(run 2 lint in_progress null)]"
caso falhou 1 "sinal falhou total 2 ok 0 falhou 1 pendente 1" BasisTI/skills 12

# 1: cancelado e status de commit com erro também contam como falha
base; runs "[$(run 1 build completed '"cancelled"')]"
caso cancelado 1 "sinal falhou" BasisTI/skills 12
base; runs "[$(run 1 build completed '"success"')]"; status '[{"context":"sonar","state":"error"}]'
caso status-erro 1 "sinal falhou" BasisTI/skills 12

# Achado r1 sério 1: CI re-disparado no mesmo SHA, várias suites; vale a mais recente de cada check
base; runs "[$(run 10 build completed '"cancelled"'),$(run 11 test completed '"failure"'),$(run 12 build completed '"failure"'),$(run 20 build completed '"success"'),$(run 21 test completed '"success"'),$(run 22 'Detect deps' completed '"cancelled"'),$(run 30 'Detect deps' completed '"success"')]"
caso reexecucao-mesmo-sha 0 "sinal verde total 3 ok 3 falhou 0" BasisTI/skills 12
# o mesmo nome em apps diferentes não se funde
base; runs "[$(run 1 build completed '"failure"' app-a),$(run 2 build completed '"success"' app-b)]"
caso mesmo-nome-apps-diferentes 1 "total 2 ok 1 falhou 1" BasisTI/skills 12
# a execução mais recente pendente prevalece sobre a antiga verde
base; runs "[$(run 1 build completed '"success"'),$(run 2 build in_progress null)]"
caso mais-recente-pendente 3 "total 1 ok 0 falhou 0 pendente 1" BasisTI/skills 12 2

# 2: nenhum check dentro da carência
base; runs '[]'
caso sem-checks 2 "sinal sem-checks" BasisTI/skills 12

# Achado r1 sério 2: push depois da carência. Head A pendente 5 leituras; head B vazio 2 leituras
# (menos que a carência de 3 s contada da troca), depois in_progress e success.
base; CAR=3
runs "[$(run 1 build in_progress null)]" runs.json
for i in 1 2 3 4 5; do pr "$sha" CLEAN OPEN pr.$i.json; done
pr "$shb" CLEAN OPEN pr.json
runs '[]' "runs.$shb.json"
runs '[]' "runs.6.json"; runs '[]' "runs.7.json"
runs "[$(run 2 build in_progress null)]" "runs.8.json"
runs "[$(run 2 build completed '"success"')]" "runs.9.json"
caso push-apos-carencia 0 "sha $shb sinal verde" BasisTI/skills 12
tem push-apos-carencia-aviso "head mudou: aaaaaaaa -> bbbbbbbb"
unset CAR

# 3: limite com check pendente (conclusion nulo não derruba o jq); resumo do limite traz o head atual
base; runs "[$(run 1 build in_progress null)]"
caso limite 3 "sinal limite total 1 ok 0 falhou 0 pendente 1" BasisTI/skills 12 3
base; status '[{"context":"sonar","state":"pending"}]'; runs "[$(run 1 build completed '"success"')]"
caso status-pendente 3 "pendente 1" BasisTI/skills 12 2

# Check que muda entre leituras: pendente, depois verde
base; runs "[$(run 1 build in_progress null)]" runs.1.json; runs "[$(run 1 build completed '"success"')]" runs.json
caso pendente-vira-verde 0 "sinal verde" BasisTI/skills 12

# Achado r1 sério 3: base atrasada pelo compare, com mergeStateStatus enganoso (UNSTABLE)
base; pr "$sha" UNSTABLE; behind 2; runs "[$(run 1 build completed '"success"')]"
caso base-atrasada 0 "sinal verde" BasisTI/skills 12
tem aviso-behind-by "aviso: head aaaaaaaa está 2 commit(s) atrás de main"
base; runs "[$(run 1 build completed '"success"')]"
caso base-em-dia 0 "sinal verde" BasisTI/skills 12
if grep -q '^aviso' "$TMP/saida"; then echo "FALHA base-em-dia: aviso indevido"; falhas=$((falhas + 1)); else echo "ok   base-em-dia sem aviso"; fi
base; touch "$TMP/f/compare.erro"; runs "[$(run 1 build completed '"success"')]"
caso compare-falha 0 "sinal verde" BasisTI/skills 12
tem aviso-compare-falhou "atraso não verificado"

# PR mesclado durante a espera: avisa e segue com os checks do head
base; pr "$sha" CLEAN MERGED; runs "[$(run 1 build completed '"success"')]"
caso pr-mesclado 0 "sinal verde" BasisTI/skills 12
tem aviso-pr-mesclado "aviso: PR MERGED"

# O SHA consultado é o do head atual (só existe fixture para o SHA b)
base; pr "$shb"; rm "$TMP/f/runs.json" 2>/dev/null || true; runs "[$(run 1 build completed '"success"')]" "runs.$shb.json"
caso sha-do-head 0 "sha $shb sinal verde" BasisTI/skills 12

# Falha persistente do gh api: 64 com a causa, não limite depois de 1 h
base; touch "$TMP/f/runs.erro"
caso gh-api-falha 64 "vezes seguidas (gh api)" BasisTI/skills 12 100
limpa; touch "$TMP/f/pr.erro"
caso pr-ilegivel 64 "vezes seguidas" BasisTI/skills 12 100

# Uso e validação: nenhum deve cair em código de `set -e`
caso uso-pr 64 "uso:" BasisTI/skills abc
caso uso-repo 64 "uso:" skills 12
caso uso-repo-ponto-ponto 64 "uso:" ../skills 12
caso uso-limite-longo 64 "uso:" BasisTI/skills 12 99999999999999999999
INT=abc caso intervalo-invalido 64 "INTERVALO inválido" BasisTI/skills 12
INT=0 caso intervalo-zero 64 "INTERVALO inválido" BasisTI/skills 12
CAR=abc caso carencia-invalida 64 "CARENCIA_SEM_CHECKS inválida" BasisTI/skills 12

if [ "$falhas" -eq 0 ]; then echo "todos os casos passaram"; else echo "$falhas caso(s) falharam"; exit 1; fi
