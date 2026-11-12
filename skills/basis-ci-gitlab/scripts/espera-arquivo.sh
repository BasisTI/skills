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
#   --limite-s  tempo máximo de espera (padrão 3600).
#   --ultimas   quantas linhas finais imprimir ao sair (padrão 20).
# Variável opcional: INTERVALO (segundos entre leituras, padrão 5).
#
# Existe para que ninguém improvise essa espera: `sleep N; grep ... suite.log`
# é bloqueado pelo harness (485 bloqueios em 245 sessões no levantamento de
# 2026-11-12) e o laço improvisado costuma depender do shell de quem chama.
# Feito para `run_in_background` (Claude Code) ou para o laço dentro do turno
# (Codex), sem `sleep` do agente. O caminho é testado com `[ -e ]`, nunca com glob.
#
# Imprime as últimas linhas do arquivo e, no fim, uma linha de resumo:
#   arquivo <caminho> sinal <nome> [padrao <regex>] [linha <n>]
#
# Saída:
#   0  sinal casou: o arquivo existe e, com --padrao, uma linha casou
#   3  limite de tempo atingido (sinal arquivo-ausente ou padrao-nao-casou)
#  64  uso / ambiente (argumento inválido, regex inválida, falta grep)

set -euo pipefail

uso() { echo "uso: $0 <arquivo> [--padrao <regex>] [--limite-s <segundos>] [--ultimas <n>]" >&2; exit 64; }

ARQUIVO=""
PADRAO=""
LIMITE=3600
ULTIMAS=20
INTERVALO="${INTERVALO:-5}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --padrao)   [ "$#" -ge 2 ] || uso; PADRAO="$2"; shift 2 ;;
    --limite-s) [ "$#" -ge 2 ] || uso; LIMITE="$2"; shift 2 ;;
    --ultimas)  [ "$#" -ge 2 ] || uso; ULTIMAS="$2"; shift 2 ;;
    -h|--help)  uso ;;
    --*)        uso ;;
    *)          [ -z "$ARQUIVO" ] || uso; ARQUIVO="$1"; shift ;;
  esac
done

[ -n "$ARQUIVO" ] || uso
[[ "$LIMITE" =~ ^[0-9]+$ ]] || uso
[[ "$ULTIMAS" =~ ^[0-9]+$ ]] || uso
[[ "$INTERVALO" =~ ^[0-9]+$ ]] || uso
command -v grep >/dev/null 2>&1 || { echo "falta \`grep\` no PATH" >&2; exit 64; }
if [ -n "$PADRAO" ]; then
  rc=0
  grep -E -- "$PADRAO" </dev/null >/dev/null 2>&1 || rc=$?
  [ "$rc" -le 1 ] || { echo "regex inválida: $PADRAO" >&2; exit 64; }
fi

resumo() { # sinal [linha]
  printf 'arquivo %s sinal %s' "$ARQUIVO" "$1"
  [ -z "$PADRAO" ] || printf ' padrao %s' "$PADRAO"
  [ -z "${2:-}" ] || printf ' linha %s' "$2"
  printf '\n'
}

inicio=$(date +%s)
ultimo=""

while :; do
  if [ -e "$ARQUIVO" ]; then
    if [ -z "$PADRAO" ]; then
      tail -n "$ULTIMAS" -- "$ARQUIVO" 2>/dev/null || true
      resumo existe
      exit 0
    fi
    linha=$(grep -a -n -E -m 1 -- "$PADRAO" "$ARQUIVO" 2>/dev/null | cut -d: -f1 || true)
    if [ -n "$linha" ]; then
      tail -n "$ULTIMAS" -- "$ARQUIVO" 2>/dev/null || true
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

  if [ $(( $(date +%s) - inicio )) -ge "$LIMITE" ]; then
    if [ -e "$ARQUIVO" ]; then
      tail -n "$ULTIMAS" -- "$ARQUIVO" 2>/dev/null || true
      resumo padrao-nao-casou
    else
      resumo arquivo-ausente
    fi
    exit 3
  fi
  sleep "$INTERVALO"
done
