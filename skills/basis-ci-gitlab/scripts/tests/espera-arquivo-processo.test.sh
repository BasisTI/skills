#!/bin/bash
# Testa espera-arquivo.sh e espera-processo.sh com arquivos, marcadores e
# processos criados pelo próprio teste (nada toca agente, pane, MR ou pod real).
# Os scripts são chamados direto (pega shebang e bit de execução).
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
  rm -f "$TMP/saida" "$TMP/log" "$TMP/marcador" "$TMP/zumbi.pid" "$TMP/com espaço.log" "$TMP/a1.log" "$TMP/semnl.log" "$TMP/fifo" "$TMP/negado.log" "$TMP/dois.log" "$TMP/term.out" 2>/dev/null || true
  rmdir "$TMP/dir" 2>/dev/null || true
  rmdir "$TMP" 2>/dev/null || true
}
trap limpar EXIT

falhas=0
caso() { # nome saida_esperada trecho_da_ultima_linha script [args...]
  local nome="$1" esperado="$2" trecho="$3" script="$4"; shift 4
  local codigo=0
  INTERVALO=1 "$script" "$@" >"$TMP/saida" 2>&1 || codigo=$?
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

prefixo() { # nome: a última linha da saída do último caso começa com "arquivo "
  if [[ "$(tail -n 1 "$TMP/saida")" == "arquivo "* ]]; then echo "ok   $1"
  else echo "FALHA $1"; cat "$TMP/saida"; falhas=$((falhas + 1)); fi
}

# ---- espera-arquivo ----
LOG="$TMP/log"
caso arquivo-ausente 2 "sinal arquivo-ausente" "$ARQ" "$LOG" --limite-s 2

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
caso sem-glob 2 "sinal arquivo-ausente" "$ARQ" "$TMP/a*.log" --limite-s 1

# --ultimas limita a cauda
printf '1\n2\n3\n4\n5\n' > "$LOG"
caso ultimas 0 "sinal existe" "$ARQ" "$LOG" --ultimas 2
if grep -qx 5 "$TMP/saida" && ! grep -qx 3 "$TMP/saida"; then echo "ok   ultimas-so-duas"; else echo "FALHA ultimas-so-duas"; cat "$TMP/saida"; falhas=$((falhas + 1)); fi

# 64: uso
caso uso-sem-arquivo 64 "uso:" "$ARQ" --limite-s 2
caso uso-limite-invalido 64 "uso:" "$ARQ" "$LOG" --limite-s abc
caso uso-limite-enorme 64 "uso:" "$ARQ" "$LOG" --limite-s 99999999999999999999
caso uso-limite-acima-do-teto 64 "uso:" "$ARQ" "$LOG" --limite-s 86401
caso uso-opcao-desconhecida 64 "uso:" "$ARQ" "$LOG" --foo --limite-s 2
caso uso-regex-invalida 64 "regex inválida" "$ARQ" "$LOG" --padrao '(' --limite-s 2
caso uso-padrao-vazio 64 "--padrao vazio" "$ARQ" "$LOG" --padrao '' --limite-s 2

# log sem newline final: o resumo fica sozinho na última linha (casou, existe, limite)
printf 'a\nBUILD SUCCESS' > "$TMP/semnl.log"
caso sem-newline-casou 0 "" "$ARQ" "$TMP/semnl.log" --padrao 'BUILD (SUCCESS|FAILURE)' --limite-s 2
prefixo sem-newline-casou-prefixo
caso sem-newline-existe 0 "sinal existe" "$ARQ" "$TMP/semnl.log" --limite-s 2
prefixo sem-newline-existe-prefixo
caso sem-newline-limite 3 "sinal padrao-nao-casou" "$ARQ" "$TMP/semnl.log" --padrao 'NUNCA' --limite-s 2
prefixo sem-newline-limite-prefixo

# o limite também imprime as últimas linhas (a US pede a cauda)
printf 'l1\nl2\nl3\n' > "$LOG"
caso limite-imprime-cauda 3 "sinal padrao-nao-casou" "$ARQ" "$LOG" --padrao 'NUNCA' --limite-s 2 --ultimas 2
contem limite-cauda-l3 l3

# -m 1: duas linhas casam, vale a primeira, e o resumo é uma linha só
printf 'x\nBUILD SUCCESS\ny\nBUILD SUCCESS\n' > "$TMP/dois.log"
caso primeira-linha-que-casa 0 "linha 2" "$ARQ" "$TMP/dois.log" --padrao 'BUILD SUCCESS' --limite-s 2

# erro de leitura: diretório, FIFO e sem permissão têm sinal próprio (saída 4)
mkdir "$TMP/dir"
caso erro-leitura-diretorio 4 "sinal erro-leitura" "$ARQ" "$TMP/dir" --limite-s 2
mkfifo "$TMP/fifo"
caso erro-leitura-fifo 4 "sinal erro-leitura" "$ARQ" "$TMP/fifo" --padrao x --limite-s 2
printf 'BUILD SUCCESS\n' > "$TMP/negado.log"; chmod 000 "$TMP/negado.log"
if [ -r "$TMP/negado.log" ]; then echo "pula erro-leitura-sem-permissao (usuário lê mesmo com chmod 000)"
else caso erro-leitura-sem-permissao 4 "sinal erro-leitura" "$ARQ" "$TMP/negado.log" --padrao 'BUILD SUCCESS' --limite-s 2; fi

# INTERVALO maior que o limite não estoura o limite
t0=$(date +%s)
INTERVALO=8 "$ARQ" "$TMP/nao-existe" --limite-s 2 >/dev/null 2>&1 || true
if [ $(( $(date +%s) - t0 )) -le 4 ]; then echo "ok   intervalo-limitado-ao-restante"; else echo "FALHA intervalo-limitado-ao-restante"; falhas=$((falhas + 1)); fi

# limite padrão abaixo de 2 h (3600) nos dois scripts
for f in "$ARQ" "$PROC"; do
  if grep -q '^LIMITE=3600$' "$f"; then echo "ok   limite-padrao-3600 ($(basename "$f"))"; else echo "FALHA limite-padrao-3600 ($(basename "$f"))"; falhas=$((falhas + 1)); fi
done

# TERM / INT imprimem a linha final e saem 143 / 130
for par in "TERM:143" "INT:130"; do
  sinal="${par%%:*}"; esperado="${par##*:}"
  ( trap - INT; exec "$ARQ" "$TMP/nao-existe" --limite-s 60 >"$TMP/term.out" 2>&1 ) &
  T=$!; PIDS+=("$T"); sleep 1
  kill -"$sinal" "$T" 2>/dev/null || true
  rc=0; wait "$T" 2>/dev/null || rc=$?
  if [ "$rc" = "$esperado" ] && tail -n 1 "$TMP/term.out" | grep -q 'sinal interrompido'; then echo "ok   interrompido-$sinal (saída $rc)"; else echo "FALHA interrompido-$sinal: saída $rc"; cat "$TMP/term.out"; falhas=$((falhas + 1)); fi
done

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
caso uso-sem-alvo 64 "uso:" "$PROC" --limite-s 2
caso uso-pid-e-marcador 64 "uso:" "$PROC" --pid 1 --marcador x --limite-s 2
caso uso-pid-invalido 64 "uso:" "$PROC" --pid abc --limite-s 2
caso uso-pid-zero 64 "uso:" "$PROC" --pid 0 --limite-s 2
caso uso-limite-invalido 64 "uso:" "$PROC" --pid 1 --limite-s x
caso uso-limite-enorme 64 "uso:" "$PROC" --pid 1 --limite-s 99999999999999999999

# PID 1 é de outro usuário (EPERM no kill -0): conta como vivo, sai pelo limite
caso pid-de-outro-usuario 3 "sinal limite" "$PROC" --pid 1 --limite-s 2

# PID com zero à esquerda é o mesmo PID
sleep 30 & V2=$!; PIDS+=("$V2")
caso pid-zero-a-esquerda 3 "sinal limite" "$PROC" --pid "0$V2" --limite-s 2
kill "$V2" 2>/dev/null || true; wait "$V2" 2>/dev/null || true

# INTERVALO maior que o limite não estoura o limite
t0=$(date +%s)
INTERVALO=8 "$PROC" --marcador "$TMP/marcador-que-nao-existe" --limite-s 2 >/dev/null 2>&1 || true
if [ $(( $(date +%s) - t0 )) -le 4 ]; then echo "ok   proc-intervalo-limitado-ao-restante"; else echo "FALHA proc-intervalo-limitado-ao-restante"; falhas=$((falhas + 1)); fi

# TERM imprime a linha final e sai 143
( exec "$PROC" --marcador "$TMP/marcador-que-nao-existe" --limite-s 60 >"$TMP/term.out" 2>&1 ) &
T=$!; PIDS+=("$T"); sleep 1
kill -TERM "$T" 2>/dev/null || true
rc=0; wait "$T" 2>/dev/null || rc=$?
if [ "$rc" = 143 ] && tail -n 1 "$TMP/term.out" | grep -q 'sinal interrompido'; then echo "ok   proc-interrompido-TERM"; else echo "FALHA proc-interrompido-TERM: saída $rc"; cat "$TMP/term.out"; falhas=$((falhas + 1)); fi

if [ "$falhas" -eq 0 ]; then echo "todos os casos passaram"; else echo "$falhas caso(s) falharam"; exit 1; fi
