#!/bin/bash
# Testa espera-mr-mergeavel.sh com um `glab` falso no PATH (nada toca o GitLab).
# Uso: bash tests/espera-mr-mergeavel.test.sh   (também: zsh -c 'bash tests/espera-mr-mergeavel.test.sh')
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$AQUI/../espera-mr-mergeavel.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/espera-mr-mergeavel.XXXXXX")"
trap 'rm -r "$TMP/bin" "$TMP/f" "$TMP/saida" 2>/dev/null || true; rmdir "$TMP" 2>/dev/null || true' EXIT
mkdir -p "$TMP/bin" "$TMP/f"

# glab falso: registra os argumentos e devolve $FAKE/mr.json (ou falha, se houver mr.erro).
cat > "$TMP/bin/glab" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE/chamadas.txt"
[ "$1" = api ] || { echo "glab falso: chamada inesperada: $*" >&2; exit 99; }
if [ -e "$FAKE/mr.erro" ]; then cat "$FAKE/mr.erro"; exit 1; fi
cat "$FAKE/mr.json"
FAKE
chmod +x "$TMP/bin/glab"

falhas=0
caso() { # nome saida_esperada trecho_da_ultima_linha [args...]
  local nome="$1" esperado="$2" trecho="$3"; shift 3
  local codigo=0
  PATH="$TMP/bin:$PATH" FAKE="$TMP/f" INTERVALO=1 \
    bash "$SCRIPT" "$@" >"$TMP/saida" 2>&1 || codigo=$?
  local ultima; ultima=$(tail -n 1 "$TMP/saida")
  if [ "$codigo" = "$esperado" ] && [[ "$ultima" == *"$trecho"* ]]; then
    echo "ok   $nome (saída $codigo)"
  else
    echo "FALHA $nome: saída $codigo (esperado $esperado), última linha: $ultima"; cat "$TMP/saida"
    falhas=$((falhas + 1))
  fi
}
# mr estado detalhe conflito pipeline_status pipeline_sha
mr() {
  local pipe="null"
  [ -n "${4:-}" ] && pipe="{\"id\":9,\"sha\":\"${5:-$sha}\",\"status\":\"$4\"}"
  printf '{"iid":7,"state":"%s","detailed_merge_status":"%s","has_conflicts":%s,"sha":"%s","head_pipeline":%s,"description":"x"}' \
    "$1" "$2" "${3:-false}" "$sha" "$pipe" > "$TMP/f/mr.json"
}

sha=aaaaaaaa11111111aaaaaaaa11111111aaaaaaaa
P=grupo/sub/repo

# 0: mesclável com pipeline do head verde
mr opened mergeable false success
caso mergeavel 0 "sinal mergeavel estado opened detalhe mergeable pipeline success" $P 7
# a URL vai inteira, com o caminho codificado e sem `?` solto
if grep -qx 'api projects/grupo%2Fsub%2Frepo/merge_requests/7' "$TMP/f/chamadas.txt"; then
  echo "ok   url codificada e entre aspas"
else
  echo "FALHA url: $(cat "$TMP/f/chamadas.txt")"; falhas=$((falhas + 1))
fi

# 0: projeto por id numérico, MR sem nenhuma pipeline (head_pipeline nulo)
mr opened mergeable false ""
caso sem-pipeline 0 "sinal mergeavel estado opened detalhe mergeable pipeline nenhuma" 123 7

# 4 e 5
mr merged not_open false success
caso mesclada 4 "sinal mesclada" $P 7
mr closed not_open false success
caso fechada 5 "sinal fechada" $P 7

# 2: conflito, por has_conflicts e por detailed_merge_status
mr opened conflict true running
caso conflito 2 "sinal conflito" $P 7
mr opened need_rebase true ""
caso conflito-flag 2 "sinal conflito" $P 7

# 1: pipeline do head falhou; cancelada também
mr opened ci_must_pass false failed
caso pipeline-falhou 1 "sinal pipeline-falhou" $P 7
mr opened ci_must_pass false canceled
caso pipeline-cancelada 1 "sinal pipeline-falhou" $P 7

# pipeline de SHA antigo, vermelha ou verde, não vale: espera até o limite
mr opened mergeable false failed bbbbbbbb22222222
caso pipeline-velha-vermelha 3 "sinal limite estado opened detalhe mergeable pipeline velha(9)" $P 7 2
mr opened mergeable false success bbbbbbbb22222222
caso pipeline-velha-verde 3 "sinal limite" $P 7 2

# 3: pipeline rodando, draft, aprovação pendente: só o limite encerra
mr opened ci_still_running false running
caso rodando 3 "sinal limite estado opened detalhe ci_still_running pipeline running" $P 7 2
mr opened draft_status false success
caso draft 3 "detalhe draft_status" $P 7 2
mr opened mergeable false running
caso mergeavel-com-pipeline-rodando 3 "sinal limite" $P 7 2

# campos nulos e ausentes não derrubam o jq
printf '{"iid":7,"state":"opened","detailed_merge_status":null,"has_conflicts":null,"sha":null,"head_pipeline":{"id":null,"sha":null,"status":null}}' > "$TMP/f/mr.json"
caso campos-nulos 3 "sinal limite estado opened detalhe ?" $P 7 2

# caractere de controle cru dentro de string (tab, 0x01) não derruba o jq
printf '{"iid":7,"state":"opened","detailed_merge_status":"mergeable","has_conflicts":false,"sha":"%s","head_pipeline":null,"description":"a\tb\001c"}' "$sha" > "$TMP/f/mr.json"
caso controle 0 "sinal mergeavel" $P 7

# corpo de erro do GitLab (JSON sem iid) ou falha do glab: 5 leituras ruins = 64
printf '{"message":"404 Not found"}' > "$TMP/f/mr.json"
caso corpo-de-erro 64 "5 vezes seguidas" $P 7
printf '"so uma string"' > "$TMP/f/mr.json"
caso corpo-string 64 "5 vezes seguidas" $P 7
printf '{"message":"500 boom"}' > "$TMP/f/mr.erro"
caso glab-falha 64 "5 vezes seguidas" $P 7
printf '{"message":"404 Not found"}glab: 404 Not found (HTTP 404)' > "$TMP/f/mr.erro"
: > "$TMP/f/chamadas.txt"
caso erro-permanente 64 "erro permanente" $P 7 600
leituras=$(wc -l < "$TMP/f/chamadas.txt")
if [ "$leituras" -eq 1 ]; then echo "ok   erro permanente lê uma vez só"; else echo "FALHA: leu $leituras vezes"; falhas=$((falhas + 1)); fi
rm "$TMP/f/mr.erro"

# 64: uso
caso uso-sem-args 64 "uso:"
caso uso-mr-invalida 64 "uso:" $P abc
caso uso-projeto-invalido 64 "uso:" 'a b' 7
caso uso-limite-invalido 64 "uso:" $P 7 -1

echo
if [ "$falhas" -eq 0 ]; then echo "todos os casos passaram"; else echo "$falhas caso(s) falharam"; exit 1; fi
