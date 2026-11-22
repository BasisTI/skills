#!/bin/bash
# Vigia de aprovações do worker agy (references/harnesses/agy.md#aprovações-do-coordenador).
#
# O agy em `--mode accept-edits` ainda pede aprovação para cada comando de
# shell, e quem responde é o coordenador. Este script lê o pane do worker e,
# quando aparece o diálogo "Requesting permission for: … Run this command?",
# passa o comando pelo vigia_agy_classificar.py (lista fechada por palavra):
#   - aprovado: responde "uma vez" (Enter com a opção 1 selecionada) e registra;
#   - qualquer outra coisa: NÃO responde, registra e sai com o sinal `decisao`,
#     para o coordenador ler o pane e decidir.
# Nunca escolhe "sempre nesta conversa" nem a opção que persiste em
# settings.json: só envia Enter, e só com "> 1. Yes, run command" logo abaixo de
# "Run this command?". Comando que ocupa mais de uma linha na tela sempre para:
# na tela, a quebra feita pela largura do pane não se distingue de uma nova linha
# do comando, que seria outro comando.
#
# Feito para `run_in_background` no Claude Code: substitui a espera-onda.sh
# para o worker agy (ela acordaria a cada diálogo, porque o diálogo deixa o
# agente `blocked`). Sai também no relatório gravado, como a espera. Não vigia
# MR nem pendência: a pendência respondida chega pelo aviso do daemon.
#
# Uso:
#   vigia-agy.sh <agente>=<relatorio> --log <arquivo>
#                [--build-slot <caminho>] (repetível) build-slot.sh do projeto
#                [--raiz <dir>]      (repetível) onde caminho absoluto pode ser lido:
#                                    worktree, pasta da US, TMPDIR, ~/.m2/repository…
#                [--limite-s N]      (padrão 6600, máx. 7200)
#                [--ocioso-s N]      (padrão 600, máx. 7200) idle/done sem relatório
#                [--bloqueado-s N]   (padrão 20, máx. 600) blocked sem diálogo reconhecido
#                [--intervalo-s N]   (padrão 3, 1 a 60) pausa entre leituras do pane
#   vigia-agy.sh --classificar '<comando>' [--build-slot <caminho>] [--raiz <dir>]
#                só classifica (sem Herdr): imprime `aprova` ou `para: <motivo>`
#                e sai 0 (aprova) ou 1 (para).
#
# Log (TSV): instante UTC, decisão (`aprovado`, `parado`, `falha`), comando como
# apareceu na tela, motivo. É o registro de permissões da rodada: o autorrelato
# do agy não serve para isso.
#
# Saída: sempre a linha final `vigia-agy: sinal=<nome> <detalhe>`.
#   0  relatorio          relatório gravado (arquivo regular não vazio)
#   1  decisao            diálogo fora da lista, ou que não saiu da tela depois do
#                         Enter: o coordenador lê o pane e responde
#   2  uso                argumento inválido ou comando ausente
#   3  limite             --limite-s sem outro sinal
#   4  pane-sumido        o agente não existe mais
#   5  ocioso             idle/done sem relatório por --ocioso-s (o agy fica idle
#                         esperando tarefa em background: confira /tasks no pane)
#   8  herdr-indisponivel estado, leitura do pane ou envio da tecla falhou
#
# Origem: onda 317 (TG-32 do trabalhe-conosco, 2026-11-22), revisor agy
# gemini-4-neon-high. A primeira versão deste script, com lista proibida por
# regex, foi reprovada na revisão do PR skills#88: `< $(…)`, `&` sozinho, aspas
# desemparelhadas, `sed -n 1p -e`, `git grep -lO`, `sort -uo` e linhas juntadas
# aprovavam comandos que apagavam ou executavam. Cada caso virou teste em
# scripts/tests/vigia-agy.test.sh. Textos do diálogo conferidos no agy 1.5.14.

set -uo pipefail
export LC_ALL=C.UTF-8

AQUI=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKERS="$AQUI/herdr-workers.sh"
CLASSIFICADOR="$AQUI/vigia_agy_classificar.py"

LIMITE_S=6600
OCIOSO_S=600
BLOQUEADO_S=20
INTERVALO_S=3
FALHAS_MAX=5
AGENTE=""
RELATORIO=""
LOG=""
CLASSIFICAR=""
MODO_CLASSIFICAR=0
OPC_CLASSIF=()

uso() {
  echo "uso: $0 <agente>=<relatorio> --log <arquivo> [--build-slot <caminho>] [--raiz <dir>] [--limite-s N] [--ocioso-s N] [--bloqueado-s N] [--intervalo-s N] | --classificar '<comando>' [--build-slot <caminho>] [--raiz <dir>]" >&2
  echo "vigia-agy: sinal=uso $1"
  exit 2
}

numero() {  # numero <opção> <valor> <mínimo> <máximo>
  [[ "${2:-}" =~ ^[0-9]{1,9}$ ]] || uso "$1 pede um número inteiro"
  NUM=$((10#$2))
  [ "$NUM" -ge "$3" ] && [ "$NUM" -le "$4" ] || uso "$1 aceita de $3 a $4"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --log) [ -n "${2:-}" ] || uso "--log pede o arquivo"; LOG=$2; shift 2 ;;
    --build-slot) [ -n "${2:-}" ] || uso "--build-slot pede o caminho"; OPC_CLASSIF+=(--build-slot "$2"); shift 2 ;;
    --raiz) [ -n "${2:-}" ] || uso "--raiz pede o diretório"; OPC_CLASSIF+=(--raiz "$2"); shift 2 ;;
    --limite-s) numero "$1" "${2:-}" 1 7200; LIMITE_S=$NUM; shift 2 ;;
    --ocioso-s) numero "$1" "${2:-}" 1 7200; OCIOSO_S=$NUM; shift 2 ;;
    --bloqueado-s) numero "$1" "${2:-}" 1 600; BLOQUEADO_S=$NUM; shift 2 ;;
    --intervalo-s) numero "$1" "${2:-}" 1 60; INTERVALO_S=$NUM; shift 2 ;;
    --classificar) [ $# -ge 2 ] || uso "--classificar pede o comando"; MODO_CLASSIFICAR=1; CLASSIFICAR=$2; shift 2 ;;
    -h|--help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
      exit 0 ;;
    --*) uso "opção desconhecida: $1" ;;
    *=*)
      [ -z "$AGENTE" ] || uso "um agente por vigia"
      [ -n "${1%%=*}" ] && [ -n "${1#*=}" ] || uso "esperava <agente>=<relatorio>, veio: $1"
      AGENTE=${1%%=*}; RELATORIO=${1#*=}; shift ;;
    *) uso "esperava <agente>=<relatorio>, veio: $1" ;;
  esac
done

command -v python3 >/dev/null 2>&1 || uso "falta python3 no PATH"
[ -f "$CLASSIFICADOR" ] || uso "falta $CLASSIFICADOR"

MOTIVO=""
# classificar <comando>: 0 aprova; 1 para, com o motivo em MOTIVO.
classificar() {
  local out rc
  out=$(python3 -I "$CLASSIFICADOR" "${OPC_CLASSIF[@]+"${OPC_CLASSIF[@]}"}" -- "$1" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "aprova" ]; then MOTIVO="na lista"; return 0; fi
  MOTIVO=${out#para: }
  [ -n "$MOTIVO" ] || MOTIVO="classificador falhou (rc $rc)"
  return 1
}

if [ "$MODO_CLASSIFICAR" -eq 1 ]; then
  [ -z "$AGENTE" ] || uso "--classificar não leva <agente>=<relatorio>"
  if classificar "$CLASSIFICAR"; then echo "aprova"; exit 0; fi
  echo "para: $MOTIVO"; exit 1
fi

# --- vigia -------------------------------------------------------------------

[ -n "$AGENTE" ] || uso "informe <agente>=<relatorio>"
[ -n "$LOG" ] || uso "informe --log <arquivo>"
for cmd in herdr jq timeout; do
  command -v "$cmd" >/dev/null 2>&1 || uso "falta $cmd no PATH"
done
[ -x "$WORKERS" ] || uso "falta $WORKERS"
touch "$LOG" 2>/dev/null || uso "não consigo gravar o log $LOG"

fim() {  # fim <código> <sinal> <detalhe>
  printf 'vigia-agy: sinal=%s %s\n' "$2" "$3"
  exit "$1"
}
registra() {  # registra <decisão> <comando> <motivo>
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$1" "$2" "$3" >>"$LOG"
}

inicio=$(date +%s)
ocioso_desde=0
bloq_desde=0
falhas=0
PANE=""

estado() {  # working|idle|blocked|done|sumiu|erro (via herdr-workers.sh, JSON)
  local out
  out=$(timeout 20 "$WORKERS" estado "$AGENTE" 2>/dev/null) || true
  jq -r '.estado // .sinal // "erro"' <<<"$out" 2>/dev/null || echo erro
}
pane_do_agente() {
  timeout 20 herdr agent get "$AGENTE" 2>/dev/null | jq -r '.result.agent.pane_id // empty' 2>/dev/null
}
ler_tela() { timeout 20 herdr pane read "$PANE" --source visible 2>/dev/null; }

# dialogo <tela>: imprime as linhas do comando do ÚLTIMO diálogo de comando da
# tela, entre a linha exata "Requesting permission for:" e a linha exata "Run
# this command?", e, na última linha da saída, a linha logo abaixo (a opção
# selecionada), com o prefixo @@SEL@@. Sai 1 se não há diálogo completo.
dialogo() {
  awk '
    /^Requesting permission for: *$/ { em = 1; n = 0; fechado = 0; sel = ""; next }
    em && /^Run this command\? *$/ { em = 0; fechado = 1; pega = 1; next }
    em { cmd[++n] = $0; next }
    pega { sel = $0; pega = 0 }
    END {
      if (!fechado) exit 1
      for (i = 1; i <= n; i++) print cmd[i]
      print "@@SEL@@" sel
    }' <<<"$1"
}
comando_do() { sed '$d' <<<"$1" | grep . | sed -E 's/^ +//; s/ +$//' | paste -sd ' ' -; }

printf 'vigia-agy: armada para %s, ocioso %ss, limite %ss, log %s\n' "$AGENTE" "$OCIOSO_S" "$LIMITE_S" "$LOG"

while :; do
  agora=$(date +%s)
  if [ -f "$RELATORIO" ] && [ -s "$RELATORIO" ]; then fim 0 relatorio "$AGENTE gravou $RELATORIO"; fi
  [ $((agora - inicio)) -lt "$LIMITE_S" ] || fim 3 limite "${LIMITE_S}s sem relatório de $AGENTE"

  st=$(estado)
  case "$st" in
    sumiu) fim 4 pane-sumido "$AGENTE não existe mais" ;;
    erro|desconhecido|"")
      falhas=$((falhas + 1))
      [ "$falhas" -lt "$FALHAS_MAX" ] || fim 8 herdr-indisponivel "estado de $AGENTE falhou $falhas voltas seguidas"
      sleep "$INTERVALO_S"; continue ;;
  esac
  [ -n "$PANE" ] || PANE=$(pane_do_agente)
  if [ -z "$PANE" ] || ! tela=$(ler_tela); then
    falhas=$((falhas + 1))
    [ "$falhas" -lt "$FALHAS_MAX" ] || fim 8 herdr-indisponivel "leitura do pane de $AGENTE falhou $falhas voltas seguidas"
    sleep "$INTERVALO_S"; continue
  fi
  falhas=0

  if [ "$st" = "idle" ] || [ "$st" = "done" ]; then
    [ "$ocioso_desde" -gt 0 ] || ocioso_desde=$agora
    [ $((agora - ocioso_desde)) -lt "$OCIOSO_S" ] ||
      fim 5 ocioso "$AGENTE $st sem relatório há ${OCIOSO_S}s (agy idle pode estar esperando tarefa em background: /tasks no pane)"
  else
    ocioso_desde=0
  fi

  if grep -q 'Allow calling this tool?' <<<"$tela"; then
    registra parado "-" "diálogo de MCP"
    fim 1 decisao "diálogo de MCP no pane de $AGENTE"
  fi
  if grep -Eq 'Allow creation of this file\?|Accept this file edit\?' <<<"$tela"; then
    registra parado "-" "diálogo de arquivo (o worker não está em accept-edits?)"
    fim 1 decisao "diálogo de arquivo no pane de $AGENTE"
  fi

  if grep -q 'Requesting permission for:' <<<"$tela"; then
    if ! d=$(dialogo "$tela"); then
      sleep "$INTERVALO_S"; continue  # diálogo ainda desenhando
    fi
    sel=$(tail -1 <<<"$d"); sel=${sel#@@SEL@@}
    linhas=$(sed '$d' <<<"$d" | grep -c .)
    cmd=$(comando_do "$d")
    if [ "$linhas" -ne 1 ]; then
      registra parado "$cmd" "comando em $linhas linhas na tela"
      fim 1 decisao "comando em $linhas linhas na tela (quebra da tela não se distingue de outro comando): $cmd"
    fi
    if ! [[ "$sel" =~ ^\ *\>\ 1\.\ Yes,\ run\ command\ *$ ]]; then
      registra parado "$cmd" "opção 1 não está selecionada"
      fim 1 decisao "opção 1 não selecionada no diálogo: $cmd"
    fi
    if ! classificar "$cmd"; then
      registra parado "$cmd" "$MOTIVO"
      fim 1 decisao "$MOTIVO :: $cmd"
    fi
    if ! timeout 20 herdr pane send-keys "$PANE" Enter >/dev/null 2>&1; then
      registra falha "$cmd" "send-keys falhou; nada aprovado"
      fim 8 herdr-indisponivel "send-keys falhou no pane de $AGENTE"
    fi
    registra aprovado "$cmd" "$MOTIVO (opção 1, uma vez)"
    # O diálogo deste comando precisa sair da tela. Se continuar, não reenvia:
    # o coordenador olha (um segundo Enter poderia responder a outro diálogo).
    saiu=0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 1
      t2=$(ler_tela) || continue
      d2=$(dialogo "$t2") || { saiu=1; break; }
      [ "$(comando_do "$d2")" = "$cmd" ] || { saiu=1; break; }
    done
    [ "$saiu" -eq 1 ] || fim 1 decisao "o diálogo continua na tela 10 s depois do Enter: $cmd"
    bloq_desde=0
    continue
  fi

  if [ "$st" = "blocked" ]; then
    [ "$bloq_desde" -gt 0 ] || bloq_desde=$agora
    if [ $((agora - bloq_desde)) -ge "$BLOQUEADO_S" ]; then
      registra parado "-" "blocked sem diálogo de comando reconhecido"
      fim 1 decisao "$AGENTE blocked há ${BLOQUEADO_S}s sem diálogo reconhecido"
    fi
  else
    bloq_desde=0
  fi
  sleep "$INTERVALO_S"
done
