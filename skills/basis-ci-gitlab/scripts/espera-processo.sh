#!/bin/bash
# Espera um processo local terminar, por PID ou por arquivo marcador, sem
# nunca olhar linha de comando.
#
# SOMENTE LEITURA. Funciona de qualquer diretório.
#
# Uso:
#   espera-processo.sh --pid <pid>          [--limite-s <segundos>]
#   espera-processo.sh --marcador <arquivo> [--limite-s <segundos>]
#
#   --pid        termina quando o PID some (`kill -0` falha e /proc/<pid> não existe)
#                ou vira zumbi.
#   --marcador   termina quando o arquivo existe (o processo, ou quem o lançou, o
#                cria ao acabar: `comando; touch /tmp/x.fim`). Serve quando o PID
#                não é conhecido ou pertence a outro usuário.
#   --limite-s   tempo máximo de espera (padrão 3600; máximo 86400).
# Variável opcional: INTERVALO (segundos entre leituras, padrão 5, mínimo 1; a
# última pausa é encurtada para não passar do limite).
#
# Existe para que ninguém improvise essa espera: `until ! pgrep -f <padrão>`
# apareceu em 110 laços do levantamento de 2026-11-12 e 25 estouraram o limite,
# porque o `pgrep -f` acha a própria linha de comando do laço (confirmado em
# duas sessões de agente); `sleep N; ...` é bloqueado pelo harness. Feito para
# `run_in_background` (Claude Code) ou para o laço dentro do turno (Codex), sem
# `sleep` do agente. O marcador é testado com `[ -e ]`, nunca com glob.
#
# Imprime uma linha por mudança de estado e, no fim, o resumo:
#   processo <pid|marcador> sinal <nome>
#
# Saída:
#   0  terminou: PID sumiu (sinal terminou) ou marcador apareceu (sinal marcador)
#   2  --pid já não existia ao começar (sinal pid-inexistente): o processo já
#      terminou (um build que falha em 1 s cai aqui) ou o PID está errado
#   3  limite de tempo atingido (sinal limite, o processo ainda vivo / sem marcador)
#  64  uso / ambiente (argumento inválido)
# 129/130/143  interrompido por HUP/INT/TERM; imprime `sinal interrompido`.
#
# Limites aceitos: PID reciclado entre duas leituras conta como vivo (inerente ao
# --pid; para processo longo prefira --marcador); PID de thread (TID) conta como
# vivo; marcador que sobrou de rodada anterior sai na hora, então remova-o antes
# de lançar o comando (`rm -f /tmp/x.fim; comando; touch /tmp/x.fim`). Processo de
# outro usuário (EPERM no `kill -0`) conta como vivo enquanto /proc/<pid> existir.

set -euo pipefail

uso() { echo "uso: $0 --pid <pid> | --marcador <arquivo> [--limite-s <segundos>]" >&2; exit 64; }

PID=""
MARCADOR=""
LIMITE=3600
INTERVALO="${INTERVALO:-5}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pid)      [ "$#" -ge 2 ] || uso; PID="$2"; shift 2 ;;
    --marcador) [ "$#" -ge 2 ] || uso; MARCADOR="$2"; shift 2 ;;
    --limite-s) [ "$#" -ge 2 ] || uso; LIMITE="$2"; shift 2 ;;
    *)          uso ;;
  esac
done

{ [ -n "$PID" ] || [ -n "$MARCADOR" ]; } || uso
{ [ -z "$PID" ] || [ -z "$MARCADOR" ]; } || uso
[[ "$LIMITE" =~ ^[0-9]{1,6}$ ]] || uso
[ "$((10#$LIMITE))" -le 86400 ] || uso
LIMITE=$((10#$LIMITE))
[[ "$INTERVALO" =~ ^[0-9]{1,5}$ ]] || uso
INTERVALO=$((10#$INTERVALO))
[ "$INTERVALO" -ge 1 ] || uso
if [ -n "$PID" ]; then
  [[ "$PID" =~ ^[0-9]{1,10}$ ]] || uso
  PID=$((10#$PID))
  [ "$PID" -gt 0 ] || uso
fi

vivo() { # PID existe e não é zumbi
  if ! kill -0 "$PID" 2>/dev/null && [ ! -e "/proc/$PID" ]; then return 1; fi
  if [ -r "/proc/$PID/stat" ]; then
    local estado
    estado=$(sed -e 's/^.*) //' -e 's/ .*$//' "/proc/$PID/stat" 2>/dev/null || true)
    [ "$estado" != "Z" ] || return 1
  fi
  return 0
}

ALVO="${PID:-$MARCADOR}"
fim() { printf 'processo %s sinal %s\n' "$ALVO" "$1"; exit "$2"; }

SONO_PID=""
interrompido() { # nome codigo
  [ -z "$SONO_PID" ] || kill "$SONO_PID" 2>/dev/null || true
  printf '%s  interrompido por %s\n' "$(date +%H:%M:%S)" "$1"
  fim interrompido "$2"
}
trap 'interrompido HUP 129' HUP
trap 'interrompido INT 130' INT
trap 'interrompido TERM 143' TERM

dormir() { # segundos; em segundo plano + wait para o trap agir na hora
  sleep "$1" & SONO_PID=$!
  wait "$SONO_PID" 2>/dev/null || true
  SONO_PID=""
}

if [ -n "$PID" ] && ! vivo; then
  fim pid-inexistente 2
fi

inicio=$(date +%s)
echo "$(date +%H:%M:%S)  aguardando ${PID:+PID $PID}${MARCADOR:+marcador $MARCADOR}"

while :; do
  if [ -n "$PID" ]; then
    vivo || fim terminou 0
  elif [ -e "$MARCADOR" ]; then
    fim marcador 0
  fi
  restante=$(( LIMITE - ($(date +%s) - inicio) ))
  if [ "$restante" -le 0 ]; then
    echo "limite de ${LIMITE}s atingido"
    fim limite 3
  fi
  dormir $(( INTERVALO < restante ? INTERVALO : restante ))
done
