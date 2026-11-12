#!/bin/bash
# Testa espera-arquivo.sh e espera-processo.sh com arquivos, marcadores e
# processos criados pelo próprio teste (nada toca agente, pane, MR ou pod real).
# Uso: bash tests/espera-arquivo-processo.test.sh
#      zsh -c 'bash tests/espera-arquivo-processo.test.sh'
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARQ="$AQUI/../espera-arquivo.sh"
PROC="$AQUI/../espera-processo.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/espera-arquivo-processo.XXXXXX")"
PIDS=()
limpar() {
  local p
  for p in "${PIDS[@]:-}"; do [ -z "$p" ] || kill "$p" 2>/dev/null || true; done
  rm -f "$TMP/saida" "$TMP/log" "$TMP/marcador" "$TMP/zumbi.pid" "$TMP/com espaço.log" "$TMP/a1.log" 2>/dev/null || true
  rmdir "$TMP" 2>/dev/null || true
}
trap limpar EXIT

falhas=0
caso() { # nome saida_esperada trecho_da_ultima_linha script [args...]
  local nome="$1" esperado="$2" trecho="$3" script="$4"; shift 4
  local codigo=0
  INTERVALO=1 bash "$script" "$@" >"$TMP/saida" 2>&1 || codigo=$?
  local ultima; ultima=$(tail -n 1 "$TMP/saida")
  if [ "$codigo" = "$esperado" ] && [[ "$ultima" == *"$trecho"* ]]; then
    echo "ok   $nome (saída $codigo)"
  else
    echo "FALHA $nome: saída $codigo (esperado $esperado), última linha: $ultima"; cat "$TMP/saida"
    falhas=$((falhas + 1))
  fi
}
contem() { # nome trecho (na saída do último caso)
  if grep -qF -- "$2" "$TMP/saida"; then echo "ok   $1"; else echo "FALHA $1: sem '$2'"; cat "$TMP/saida"; falhas=$((falhas + 1)); fi
}

# ---- espera-arquivo ----
LOG="$TMP/log"
caso arquivo-ausente 3 "sinal arquivo-ausente" "$ARQ" "$LOG" --limite-s 2

printf 'compilando\n' > "$LOG"
caso existe-sem-padrao 0 "sinal existe" "$ARQ" "$LOG" --limite-s 5
contem existe-imprime-linhas compilando

caso padrao-nao-casou 3 "sinal padrao-nao-casou" "$ARQ" "$LOG" --padrao 'BUILD (SUCCESS|FAILURE)' --limite-s 2

printf 'x\n[INFO] BUILD FAILURE\n' >> "$LOG"
caso padrao-casou 0 "sinal casou padrao BUILD (SUCCESS|FAILURE) linha 3" "$ARQ" "$LOG" --padrao 'BUILD (SUCCESS|FAILURE)' --limite-s 5
contem padrao-imprime-linha-casada "BUILD FAILURE"

# arquivo que aparece depois, com o padrão chegando depois
rm -f "$LOG"
( sleep 2; printf 'a\n' > "$LOG"; sleep 2; printf 'BUILD SUCCESS\n' >> "$LOG" ) &
PIDS+=("$!")
caso aparece-depois 0 "sinal casou" "$ARQ" "$LOG" --padrao 'BUILD SUCCESS' --limite-s 15

# caminho com espaço e caractere de glob não é expandido
printf 'ok\n' > "$TMP/com espaço.log"
caso caminho-com-espaco 0 "sinal existe" "$ARQ" "$TMP/com espaço.log" --limite-s 3
printf 'ok\n' > "$TMP/a1.log"
caso sem-glob 3 "sinal arquivo-ausente" "$ARQ" "$TMP/a*.log" --limite-s 1

# --ultimas limita a cauda
printf '1\n2\n3\n4\n5\n' > "$LOG"
caso ultimas 0 "sinal existe" "$ARQ" "$LOG" --ultimas 2
if grep -qx 5 "$TMP/saida" && ! grep -qx 3 "$TMP/saida"; then echo "ok   ultimas-so-duas"; else echo "FALHA ultimas-so-duas"; cat "$TMP/saida"; falhas=$((falhas + 1)); fi

# 64: uso
caso uso-sem-arquivo 64 "uso:" "$ARQ"
caso uso-limite-invalido 64 "uso:" "$ARQ" "$LOG" --limite-s abc
caso uso-opcao-desconhecida 64 "uso:" "$ARQ" "$LOG" --foo
caso uso-regex-invalida 64 "regex inválida" "$ARQ" "$LOG" --padrao '('

# ---- espera-processo ----
# PID some
sleep 2 & P=$!; PIDS+=("$P")
caso pid-terminou 0 "sinal terminou" "$PROC" --pid "$P" --limite-s 15
wait "$P" 2>/dev/null || true

# PID inexistente (já recolhido)
caso pid-inexistente 2 "sinal pid-inexistente" "$PROC" --pid "$P" --limite-s 3

# limite com processo vivo
sleep 30 & V=$!; PIDS+=("$V")
caso pid-limite 3 "sinal limite" "$PROC" --pid "$V" --limite-s 2
kill "$V" 2>/dev/null || true; wait "$V" 2>/dev/null || true

# o script nunca consulta linha de comando (só pode citar pgrep em comentário)
if grep -vE '^[[:space:]]*#' "$PROC" | grep -qE 'pgrep|pkill'; then
  echo "FALHA espera-processo usa pgrep/pkill"; falhas=$((falhas + 1))
else echo "ok   sem-pgrep-no-codigo"; fi

# zumbi conta como terminado: o pai (exec sleep) nunca recolhe o filho, que
# vira zumbi 2 s depois de a espera começar
( sleep 2 & echo $! > "$TMP/zumbi.pid"; exec sleep 30 ) &
PIDS+=("$!")
sleep 1
Z="$(cat "$TMP/zumbi.pid")"
caso pid-vira-zumbi 0 "sinal terminou" "$PROC" --pid "$Z" --limite-s 10
caso pid-ja-zumbi 2 "sinal pid-inexistente" "$PROC" --pid "$Z" --limite-s 3

# marcador
MARC="$TMP/marcador"
caso marcador-limite 3 "sinal limite" "$PROC" --marcador "$MARC" --limite-s 2
( sleep 2; : > "$MARC" ) &
PIDS+=("$!")
caso marcador-aparece 0 "sinal marcador" "$PROC" --marcador "$MARC" --limite-s 15
caso marcador-sem-glob 3 "sinal limite" "$PROC" --marcador "$TMP/a*.log" --limite-s 1

# 64: uso
caso uso-sem-alvo 64 "uso:" "$PROC"
caso uso-pid-e-marcador 64 "uso:" "$PROC" --pid 1 --marcador x
caso uso-pid-invalido 64 "uso:" "$PROC" --pid abc
caso uso-pid-zero 64 "uso:" "$PROC" --pid 0
caso uso-limite-invalido 64 "uso:" "$PROC" --pid 1 --limite-s x

if [ "$falhas" -eq 0 ]; then echo "todos os casos passaram"; else echo "$falhas caso(s) falharam"; exit 1; fi
