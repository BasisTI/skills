#!/bin/bash
# Espera um arquivo (log de build ou de teste) existir e, com --padrao, ter uma
# linha que case; imprime as últimas linhas ao sair.
#
# SOMENTE LEITURA. Funciona de qualquer diretório.
#
# Uso:
#   espera-arquivo.sh <arquivo> [--padrao <regex>] [--limite-s <segundos>] [--ultimas <n>]
#
#   --padrao    regex estendida (grep -E) procurada nas linhas do arquivo, ex.:
#               'BUILD (SUCCESS|FAILURE)'. Sem ela, basta o arquivo existir.
#   --limite-s  tempo máximo de espera (padrão 3600; máximo 86400).
#   --ultimas   quantas linhas finais imprimir ao sair (padrão 20).
# Variável opcional: INTERVALO (segundos entre leituras, padrão 5, mínimo 1; a
# última pausa é encurtada para não passar do limite).
#
# Existe para que ninguém improvise essa espera: `sleep N; grep ... suite.log`
# é bloqueado pelo harness (485 bloqueios em 245 sessões no levantamento de
# 2026-11-12) e o laço improvisado costuma depender do shell de quem chama.
# Feito para `run_in_background` (Claude Code) ou para o laço dentro do turno
# (Codex), sem `sleep` do agente. O caminho é testado com `[ -e ]`, nunca com glob.
#
# Imprime as últimas linhas do arquivo (sempre terminadas em newline, mesmo que
# o log termine no meio de uma linha) e, por último, uma linha de resumo:
#   arquivo <caminho> sinal <nome> [padrao <regex>] [linha <n>]
#
# Saída (um código por sinal):
#   0  sinal casou (ou existe, sem --padrao): o arquivo existe e, com --padrao,
#      uma linha casou
#   2  sinal arquivo-ausente: limite de tempo e o arquivo nunca apareceu
#   3  sinal padrao-nao-casou: limite de tempo, o arquivo existe e nenhuma linha casou
#   4  sinal erro-leitura: o caminho existe mas não é arquivo comum legível
#      (diretório, FIFO, sem permissão) ou o grep falhou ao lê-lo
#  64  uso / ambiente (argumento inválido, regex inválida, falta grep)
# 129/130/143  interrompido por HUP/INT/TERM; imprime `sinal interrompido`.
#
# Limites aceitos: uma linha antiga de log reaproveitado casa na hora (limpe ou
# use um log novo por rodada); o padrão é procurado no arquivo inteiro, não só
# no que foi escrito depois de o script começar.

set -euo pipefail

uso() { echo "uso: $0 <arquivo> [--padrao <regex>] [--limite-s <segundos>] [--ultimas <n>]" >&2; exit 64; }

ARQUIVO=""
PADRAO=""
TEM_PADRAO=0
LIMITE=3600
ULTIMAS=20
INTERVALO="${INTERVALO:-5}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --padrao)   [ "$#" -ge 2 ] || uso; PADRAO="$2"; TEM_PADRAO=1; shift 2 ;;
    --limite-s) [ "$#" -ge 2 ] || uso; LIMITE="$2"; shift 2 ;;
    --ultimas)  [ "$#" -ge 2 ] || uso; ULTIMAS="$2"; shift 2 ;;
    -h|--help)  uso ;;
    --*)        uso ;;
    *)          [ -z "$ARQUIVO" ] || uso; ARQUIVO="$1"; shift ;;
  esac
done

[ -n "$ARQUIVO" ] || uso
[[ "$LIMITE" =~ ^[0-9]{1,6}$ ]] || uso
[ "$((10#$LIMITE))" -le 86400 ] || uso
LIMITE=$((10#$LIMITE))
[[ "$ULTIMAS" =~ ^[0-9]{1,4}$ ]] || uso
[[ "$INTERVALO" =~ ^[0-9]{1,5}$ ]] || uso
INTERVALO=$((10#$INTERVALO))
[ "$INTERVALO" -ge 1 ] || uso
command -v grep >/dev/null 2>&1 || { echo "falta \`grep\` no PATH" >&2; exit 64; }
if [ "$TEM_PADRAO" = 1 ]; then
  [ -n "$PADRAO" ] || { echo "--padrao vazio" >&2; exit 64; }
  rc=0
  grep -E -- "$PADRAO" </dev/null >/dev/null 2>&1 || rc=$?
  [ "$rc" -le 1 ] || { echo "regex inválida: $PADRAO" >&2; exit 64; }
fi

resumo() { # sinal [linha]
  printf 'arquivo %s sinal %s' "$ARQUIVO" "$1"
  [ "$TEM_PADRAO" = 0 ] || printf ' padrao %s' "${PADRAO//$'\n'/ }"
  [ -z "${2:-}" ] || printf ' linha %s' "$2"
  printf '\n'
}

cauda() { # últimas linhas, sempre terminadas em newline; linha gigante é cortada
  local texto
  texto=$(tail -n "$ULTIMAS" -- "$ARQUIVO" 2>/dev/null | tail -c 65536 | tr -d '\0') || true
  [ -z "$texto" ] || printf '%s\n' "$texto"
}

SONO_PID=""
interrompido() { # nome codigo
  [ -z "$SONO_PID" ] || kill "$SONO_PID" 2>/dev/null || true
  printf '%s  interrompido por %s\n' "$(date +%H:%M:%S)" "$1"
  resumo interrompido
  exit "$2"
}
trap 'interrompido HUP 129' HUP
trap 'interrompido INT 130' INT
trap 'interrompido TERM 143' TERM

dormir() { # segundos; em segundo plano + wait para o trap agir na hora
  sleep "$1" & SONO_PID=$!
  wait "$SONO_PID" 2>/dev/null || true
  SONO_PID=""
}

inicio=$(date +%s)
ultimo=""

while :; do
  if [ -e "$ARQUIVO" ]; then
    if [ ! -f "$ARQUIVO" ] || [ ! -r "$ARQUIVO" ]; then
      echo "não consigo ler como arquivo comum: $ARQUIVO" >&2
      resumo erro-leitura
      exit 4
    fi
    if [ "$TEM_PADRAO" = 0 ]; then
      cauda
      resumo existe
      exit 0
    fi
    rc=0
    achado=$(grep -a -n -E -m 1 -- "$PADRAO" "$ARQUIVO" 2>/dev/null) || rc=$?
    if [ "$rc" -gt 1 ]; then
      echo "grep falhou ao ler: $ARQUIVO" >&2
      resumo erro-leitura
      exit 4
    fi
    linha="${achado%%:*}"
    if [ -n "$linha" ]; then
      cauda
      resumo casou "$linha"
      exit 0
    fi
    estado="arquivo existe, padrão ainda não casou"
  else
    estado="arquivo ainda não existe"
  fi
  if [ "$estado" != "$ultimo" ]; then
    printf '%s  %s\n' "$(date +%H:%M:%S)" "$estado"
    ultimo="$estado"
  fi

  restante=$(( LIMITE - ($(date +%s) - inicio) ))
  if [ "$restante" -le 0 ]; then
    if [ -e "$ARQUIVO" ]; then
      cauda
      resumo padrao-nao-casou
      exit 3
    fi
    resumo arquivo-ausente
    exit 2
  fi
  dormir $(( INTERVALO < restante ? INTERVALO : restante ))
done
