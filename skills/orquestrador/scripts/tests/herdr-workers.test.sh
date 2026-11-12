#!/bin/bash
# Teste do herdr-workers.sh com um `herdr` falso no PATH: nenhum agente, pane ou
# onda real é tocado. Rode de qualquer shell:
#   bash skills/orquestrador/scripts/tests/herdr-workers.test.sh
#   zsh -c 'bash skills/orquestrador/scripts/tests/herdr-workers.test.sh'
# Sai 0 se todos os casos passarem; 1 com a lista dos que falharam.
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$AQUI/../herdr-workers.sh"
BASE="${TMPDIR:-/tmp}"
TMP="$(mktemp -d "$BASE/herdr-workers-test.XXXXXX")"
trap 'rm -f "$TMP/bin/herdr" "$TMP/chamadas" "$TMP/saida"; rmdir "$TMP/bin" "$TMP" 2>/dev/null || true' EXIT
mkdir -p "$TMP/bin"

# herdr falso. Comportamento pelo ambiente:
#   FAKE_GET_STATUS   status devolvido por `agent get` (vazio = agent_not_found)
#   FAKE_PROMPT       ok | timeout | blocked | stalled | notfound | outro
#   FAKE_START_FALHA  nome do agente cujo `start` falha com agent_pane_not_found
# Cada chamada é registrada, um argumento por linha, em $TMP/chamadas.
cat > "$TMP/bin/herdr" <<'FAKE'
#!/bin/bash
{ printf 'CHAMADA'; for a in "$@"; do printf '\n%s' "$a"; done; printf '\n'; } >> "$FAKE_LOG"
erro() { printf '{"error":{"code":"%s","message":"%s"},"id":"x"}\n' "$1" "$2"; exit 1; }
case "$1 $2" in
  "agent get")
    [ -n "${FAKE_GET_STATUS:-}" ] || erro agent_not_found "agent target $3 not found"
    printf '{"id":"x","result":{"agent":{"agent_status":"%s"}}}\n' "$FAKE_GET_STATUS" ;;
  "agent prompt")
    case "${FAKE_PROMPT:-ok}" in
      ok) echo '{"id":"x","result":{"type":"ok"}}' ;;
      timeout) erro timeout "timed out" ;;
      blocked) erro agent_blocked "agent is blocked" ;;
      stalled) erro agent_prompt_stalled "stalled" ;;
      notfound) erro agent_not_found "agent target $3 not found" ;;
      *) echo 'falha sem json'; exit 1 ;;
    esac ;;
  "agent start")
    [ "$3" = "${FAKE_START_FALHA:-}" ] && erro agent_pane_not_found "agent target pane not found"
    echo '{"id":"x","result":{"type":"agent_started"}}' ;;
  *) erro desconhecido "$*" ;;
esac
FAKE
chmod +x "$TMP/bin/herdr"

export FAKE_LOG="$TMP/chamadas"
FALHAS=()
TOTAL=0

# caso <nome> <código esperado> <sinal esperado> -- <comando...>
# Usa as variáveis FAKE_* exportadas antes da chamada. Confere o código de saída,
# o campo `sinal` e que a ÚLTIMA linha da saída é JSON válido com esse sinal.
caso() {
  local nome="$1" rc_esp="$2" sinal_esp="$3" rc=0 sinal ultima
  shift 4
  : > "$FAKE_LOG"
  PATH="$TMP/bin:$PATH" "$@" > "$TMP/saida" 2>&1 || rc=$?
  ultima=$(tail -n 1 "$TMP/saida")
  sinal=$(jq -r '.sinal // ""' <<<"$ultima" 2>/dev/null || echo "JSON-INVÁLIDO")
  TOTAL=$((TOTAL + 1))
  if [ "$rc" -ne "$rc_esp" ] || [ "$sinal" != "$sinal_esp" ]; then
    FALHAS+=("$nome: esperava rc=$rc_esp sinal=$sinal_esp, veio rc=$rc sinal=$sinal ($ultima)")
  fi
}

chamadas() { grep -c '^CHAMADA' "$FAKE_LOG" || true; }
confere() {  # <nome> <condição em texto> <comando de teste...>
  local nome="$1"; shift
  TOTAL=$((TOTAL + 1))
  "$@" || FALHAS+=("$nome")
}

W() { "$SCRIPT" "$@"; }

# --- estado: um caso por sinal ----------------------------------------------
for par in working:0 idle:10 blocked:11 done:12 unknown:14; do
  st="${par%%:*}"; rc="${par##*:}"; sinal="$st"; [ "$st" = unknown ] && sinal=desconhecido
  export FAKE_GET_STATUS="$st"
  caso "estado $st" "$rc" "$sinal" -- W estado tg-1_executor
done
export FAKE_GET_STATUS=""
caso "estado sumiu" 13 sumiu -- W estado tg-1_executor
caso "estado sem agente" 2 uso -- W estado

# --- prompt: um caso por sinal ----------------------------------------------
export FAKE_GET_STATUS=idle FAKE_PROMPT=ok
caso "prompt entregue" 0 entregue -- W prompt tg-1_executor "olá mundo"
export FAKE_GET_STATUS=working FAKE_PROMPT=timeout
caso "prompt timeout com working" 0 entregue_timeout -- W prompt tg-1_executor "olá" --timeout 1000
confere "timeout com working não reenvia" test "$(grep -c '^prompt$' "$FAKE_LOG")" -eq 1
export FAKE_GET_STATUS=idle FAKE_PROMPT=timeout
caso "prompt timeout sem working" 3 nao_confirmado -- W prompt tg-1_executor "olá"
confere "timeout sem working não reenvia" test "$(grep -c '^prompt$' "$FAKE_LOG")" -eq 1
export FAKE_GET_STATUS=working FAKE_PROMPT=stalled
caso "prompt stalled com working" 0 entregue_timeout -- W prompt tg-1_executor "olá"
export FAKE_GET_STATUS=blocked FAKE_PROMPT=blocked
caso "prompt agente blocked" 4 recusado_bloqueado -- W prompt tg-1_executor "olá"
export FAKE_GET_STATUS="" FAKE_PROMPT=notfound
caso "prompt agente sumiu" 5 sumiu -- W prompt tg-1_executor "olá"
export FAKE_GET_STATUS=idle FAKE_PROMPT=outro
caso "prompt erro inesperado" 1 erro -- W prompt tg-1_executor "olá"
caso "prompt sem texto" 2 uso -- W prompt tg-1_executor
caso "prompt timeout inválido" 2 uso -- W prompt tg-1_executor "olá" --timeout abc
caso "prompt timeout acima de 2 h" 2 uso -- W prompt tg-1_executor "olá" --timeout 7200001

# O texto chega ao herdr como UM argumento, com espaço, aspas e `=`.
export FAKE_GET_STATUS=idle FAKE_PROMPT=ok
caso "prompt texto com espaços" 0 entregue -- W prompt tg-1_executor 'a "b" c=d  e'
confere "texto intacto" grep -qxF 'a "b" c=d  e' "$FAKE_LOG"
confere "prompt usa --wait e --timeout" grep -qx -- '--wait' "$FAKE_LOG"

# --- start -------------------------------------------------------------------
unset FAKE_START_FALHA
caso "start dois pares" 0 iniciado -- W start --kind claude tg-1_executor=w1:p3 tg-2_executor=w1:p4
confere "start fez duas chamadas" test "$(chamadas)" -eq 2
confere "start passou o pane do segundo par" grep -qx 'w1:p4' "$FAKE_LOG"
caso "start com argumentos do agente" 0 iniciado -- W start --kind codex --timeout 5000 tg-1_executor=w1:p3 -- --no-daemon --foo
confere "args do agente depois de --" grep -qx -- '--no-daemon' "$FAKE_LOG"
export FAKE_START_FALHA=tg-2_executor
caso "start com uma falha" 1 falhou -- W start --kind claude tg-1_executor=w1:p3 tg-2_executor=w1:p4 tg-3_executor=w1:p5
confere "start segue depois da falha" test "$(chamadas)" -eq 3
confere "start reporta o código da falha" grep -q agent_pane_not_found "$TMP/saida"
unset FAKE_START_FALHA
caso "start par sem =" 2 uso -- W start --kind claude tg-1_executor
confere "start inválido não lança nada" test "$(chamadas)" -eq 0
caso "start par ruim no meio não lança o primeiro" 2 uso -- W start --kind claude tg-1_executor=w1:p3 ruim
confere "nada lançado" test "$(chamadas)" -eq 0
caso "start nome inválido" 2 uso -- W start --kind claude Tg-1=w1:p3
caso "start sem --kind" 2 uso -- W start tg-1_executor=w1:p3
caso "start sem pares" 2 uso -- W start --kind claude

# --- uso ---------------------------------------------------------------------
caso "sem subcomando" 2 uso -- W
caso "subcomando desconhecido" 2 uso -- W parar

# --- zsh e herdr ausente -----------------------------------------------------
if command -v zsh >/dev/null 2>&1; then
  export FAKE_GET_STATUS=working
  caso "chamado a partir do zsh" 0 working -- zsh -c "\"$SCRIPT\" estado tg-1_executor"
  export FAKE_GET_STATUS=""
  caso "start do zsh com pares" 0 iniciado -- zsh -c "\"$SCRIPT\" start --kind claude a=w1:p1 b=w1:p2"
fi
TOTAL=$((TOTAL + 1))
SEMHERDR="$TMP/semherdr"; mkdir -p "$SEMHERDR"
ln -s "$(command -v jq)" "$SEMHERDR/jq"; ln -s "$(command -v bash)" "$SEMHERDR/bash"
rc=0; out=$(PATH="$SEMHERDR" /bin/bash "$SCRIPT" estado x 2>&1) || rc=$?
{ [ "$rc" -eq 2 ] && grep -q '"sinal":"uso"' <<<"$out"; } || FALHAS+=("sem herdr no PATH: rc=$rc out=$out")
rm -f "$SEMHERDR/jq" "$SEMHERDR/bash"; rmdir "$SEMHERDR"

if [ "${#FALHAS[@]}" -gt 0 ]; then
  printf 'FALHOU %d de %d:\n' "${#FALHAS[@]}" "$TOTAL"
  printf '  - %s\n' "${FALHAS[@]}"
  exit 1
fi
printf 'OK: %d verificações passaram\n' "$TOTAL"
