#!/bin/bash
# Vigia de aprovações do worker agy (references/harnesses/agy.md#aprovações-do-coordenador).
#
# O agy em `--mode accept-edits` ainda pede aprovação para cada comando de
# shell, e quem responde é o coordenador. Este script lê o pane do worker, e,
# quando aparece o diálogo "Requesting permission for: … Run this command?",
# classifica o comando por uma LISTA FECHADA:
#   - leitura (git de leitura, grep, ls, cat, jq, glab api GET, sonar/taiga de
#     leitura…) e build pelo build-slot informado em --build-slot: responde
#     "uma vez" (opção 1, Enter) e registra no log;
#   - todo o resto (escrita, rede, processo, `$(...)`, redirecionamento para
#     arquivo, comando desconhecido, diálogo de MCP ou de arquivo): NÃO responde,
#     registra e sai com o sinal `decisao`, para o coordenador decidir.
# Nunca escolhe "sempre nesta conversa" nem a opção que persiste em
# settings.json: só envia Enter, e só com a opção 1 selecionada na tela.
#
# Feito para `run_in_background` no Claude Code: substitui a espera-onda.sh
# para o worker agy (ela acordaria a cada diálogo, porque o diálogo deixa o
# agente `blocked`). Sai também no relatório gravado, como a espera.
#
# Uso:
#   vigia-agy.sh <agente>=<relatorio> --log <arquivo>
#                [--build-slot <caminho>] (repetível) build-slot.sh do projeto
#                [--limite-s N]    (padrão 6600, máx. 7200)
#                [--ocioso-s N]    (padrão 600, máx. 7200) idle/done sem relatório
#                [--bloqueado-s N] (padrão 20, máx. 600) blocked sem diálogo reconhecido
#                [--intervalo-s N] (padrão 3, 1 a 60) pausa entre leituras do pane
#   vigia-agy.sh --classificar '<comando>' [--build-slot <caminho>]
#                só classifica (sem Herdr): imprime `aprova` ou `para: <motivo>`
#                e sai 0 (aprova) ou 1 (para). Serve para conferir a lista.
#
# Log (TSV, um por linha): instante UTC, decisão (`aprovado` ou `parado`),
# comando como apareceu na tela, motivo. É o registro de permissões da rodada
# ([agy](../references/harnesses/agy.md#aprovações-do-coordenador)): o
# autorrelato do agy não serve para isso.
#
# Saída: sempre a linha final `vigia-agy: sinal=<nome> <detalhe>`.
#   0  relatorio          relatório gravado (arquivo regular não vazio)
#   1  decisao            diálogo fora da lista: o coordenador lê o pane e responde
#   2  uso                argumento inválido ou comando ausente
#   3  limite             --limite-s sem outro sinal
#   4  pane-sumido        o agente não existe mais
#   5  ocioso             idle/done sem relatório por --ocioso-s (o agy fica idle
#                         esperando tarefa em background: confira /tasks no pane)
#   8  herdr-indisponivel estado ou leitura do pane falhou 5 voltas seguidas
#
# Origem: onda 317 (TG-32 do trabalhe-conosco, 2026-11-22), revisor agy
# gemini-4-neon-high. O vigia de scratchpad precisou de oito ajustes na mesma
# revisão; cada caso virou teste em scripts/tests/vigia-agy.test.sh. Textos do
# diálogo conferidos no agy 1.5.14.

set -uo pipefail
export LC_ALL=C.UTF-8

AQUI=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
WORKERS="$AQUI/herdr-workers.sh"

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
SLOTS=()

uso() {
  echo "uso: $0 <agente>=<relatorio> --log <arquivo> [--build-slot <caminho>] [--limite-s N] [--ocioso-s N] [--bloqueado-s N] [--intervalo-s N] | --classificar '<comando>' [--build-slot <caminho>]" >&2
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
    --build-slot) [ -n "${2:-}" ] || uso "--build-slot pede o caminho"; SLOTS+=("$2"); shift 2 ;;
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

# --- classificação -----------------------------------------------------------

# Escapa um caminho literal para uso dentro de uma ERE.
ere_literal() { printf '%s' "$1" | sed -e 's/[][\.*^$+?(){}|/]/\\&/g'; }

# Comandos que o build-slot pode rodar.
BUILD='(\./mvnw|mvn|go (test|build|vet)|npm (test|run build)|uv run (pytest|python -m pytest))( .*)?'
SLOT_RE=""
for s in "${SLOTS[@]+"${SLOTS[@]}"}"; do
  alt=$(ere_literal "$s")
  case "$s" in
    "$HOME"/*) alt="($alt|~$(ere_literal "${s#"$HOME"}"))" ;;
  esac
  SLOT_RE+="|$alt $BUILD"
done

# Lista fechada de segmentos. Cada segmento entre `&&`, `||`, `;` e `|` (fora de
# aspas) precisa casar com uma destas formas, inteira.
OK_SEG="^(cd [^ ]+|true|pwd"
OK_SEG+="|git (rev-parse|status|log|diff|show|ls-files|blame|grep|merge-base|cat-file)( .*)?"
OK_SEG+="|glab api [^ ]+( --paginate)?|glab mr view [0-9]+( -F json)?"
OK_SEG+="|sonar (qg status|issues( list)?|hotspots? list)( .*)?"
OK_SEG+="|taiga story (get|comments) [0-9]+( .*)?"
OK_SEG+="|herdr agent get [^ ]+"
OK_SEG+="|jq( .*)?|grep( .*)?|rg( .*)?|ls( .*)?|cat [^ ]+( [^ ]+)*|head( .*)?|tail( .*)?|wc( .*)?"
OK_SEG+="|SEDOK( [^ ]+)*|sort( -[a-zA-Z]+)*( [^ -][^ ]*)*|uniq( -[a-zA-Z]+)*|cut( .*)?|tr( .*)?"
OK_SEG+="|diff( .*)?|stat( .*)?|df( .*)?|du( .*)?|echo( .*)?|printf( .*)?|which( .*)?|date( .*)?"
OK_SEG+="|find( .*)?|ps -p [0-9,]+( .*)?|javap( .*)?"
OK_SEG+="$SLOT_RE)$"

# Construções que param mesmo dentro de um comando da lista (conferidas com as
# aspas ainda no texto: aspas não protegem nada aqui).
CMD_POS='(^|[;&|(] *)'
PROIBIDO='\$\(|`|<\(|<<|(^|[;&|] *)\. '
PROIBIDO+="|${CMD_POS}(eval|exec|source|rm|rmdir|mv|cp|dd|chmod|chown|ln|touch|truncate|mkfifo|kill|pkill|killall"
PROIBIDO+="|docker|podman|kubectl|helm|sudo|su|ssh|scp|rsync|curl|wget|nc|tee|xargs|sh|bash|zsh|perl|ruby|node|awk)\\b"
PROIBIDO+='|\b(sh|bash|zsh) +-c\b|system\(|-delete\b|-exec|-ok\b|-fprint|-fls|--output|\bsort\b[^|;&]* -o|\bsed\b'
PROIBIDO+='|\bgit +(push|commit|checkout|switch|reset|rebase|merge|branch|tag|stash|clean|restore|apply|am|worktree|config|remote|fetch|pull|gc)\b'
PROIBIDO+='|\bgh\b|\bglab +(mr +(merge|approve|close|note|update|create)|api [^|;&]*(-X|--method|-f |-F |--field|--raw-field|--input))'
PROIBIDO+='|--pre\b|--open-files-in-pager|\bgit +grep[^|;&]* -O'
PROIBIDO+='|secret|credential|\.env\b|token|password|senha|\.pem\b|id_rsa|kube/config|vault'

MOTIVO=""
# classificar <comando>: 0 aprova; 1 para, com o motivo em MOTIVO.
classificar() {
  local cmd="$1" limpo seg falha=""
  [ -n "${cmd// /}" ] || { MOTIVO="comando vazio"; return 1; }
  # Redirecionamentos inofensivos e formas conferidas, antes da lista.
  limpo=$(printf '%s' "$cmd" | sed -E \
    -e 's#[0-9]?>/dev/null##g; s#&>/dev/null##g; s#2>&1##g' \
    -e 's#(^| )< ?[^ <>(|&;]+# #g' \
    -e "s#\\bsed -n '?[0-9]+(,([0-9]+|\\\$))?p'?#SEDOK#g" \
    -e "s#^javap -cp \"\\\$\\(find ~/\\.m2/repository/[A-Za-z0-9/._-]+ -name '[A-Za-z0-9*._-]+' \\| sort -V \\| tail -1\\)\"#javap -cp Q#")
  if printf '%s' "$limpo" | grep -Eq -- "$PROIBIDO"; then
    MOTIVO="construção proibida: $(printf '%s' "$limpo" | grep -Eo -- "$PROIBIDO" | head -1)"; return 1
  fi
  if printf '%s' "$limpo" | grep -q '[<>]'; then MOTIVO="redirecionamento"; return 1; fi
  while IFS= read -r seg; do
    seg=$(printf '%s' "$seg" | sed -E 's/^ +//; s/ +$//')
    [ -n "$seg" ] || continue
    printf '%s' "$seg" | grep -Eq -- "$OK_SEG" || { falha=$seg; break; }
  done < <(printf '%s\n' "$limpo" | sed -E "s/'[^']*'/Q/g" | sed -E 's/"[^"]*"/Q/g' | sed -E 's/(&&|\|\||;|\|)/\n/g')
  if [ -n "$falha" ]; then MOTIVO="fora da lista: $falha"; return 1; fi
  MOTIVO="na lista"
  return 0
}

# juntar_linhas <largura> < linhas do diálogo: junta as linhas que a tela
# quebrou e imprime o comando numa linha só. A quebra só é aceita como quebra
# de tela quando a linha estava cheia (palavra cortada no meio: junta sem
# espaço) ou quando a primeira palavra da linha seguinte não caberia nela
# (quebra no espaço: junta com espaço). Qualquer outra quebra é uma nova linha
# de verdade no comando, ou seja, outro comando escondido: "echo a" seguido de
# "rm -rf /" passaria pela lista se fosse juntado. Nesse caso sai 1.
juntar_linhas() {
  local largura="$1" linha ant="" tem_ant=0 cmd="" palavra
  while IFS= read -r linha; do
    linha="${linha%"${linha##*[! ]}"}"
    [ -n "$linha" ] || continue
    if [ "$tem_ant" -eq 0 ]; then
      cmd="${linha#"${linha%%[! ]*}"}"
    else
      palavra="${linha#"${linha%%[! ]*}"}"; palavra="${palavra%% *}"
      if [ "${#ant}" -ge $((largura - 1)) ]; then
        cmd+="${linha#"${linha%%[! ]*}"}"
      elif [ $(( ${#ant} + 1 + ${#palavra} )) -gt "$largura" ]; then
        cmd+=" ${linha#"${linha%%[! ]*}"}"
      else
        MOTIVO="quebra de linha que não é da tela (comando em várias linhas)"; return 1
      fi
    fi
    ant="$linha"; tem_ant=1
  done
  printf '%s' "$cmd"
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

# estado: working|idle|blocked|done|sumiu|erro (via herdr-workers.sh, JSON).
estado() {
  local out
  out=$(timeout 20 "$WORKERS" estado "$AGENTE" 2>/dev/null) || true
  jq -r '.estado // .sinal // "erro"' <<<"$out" 2>/dev/null || echo erro
}

pane_do_agente() {
  timeout 20 herdr agent get "$AGENTE" 2>/dev/null | jq -r '.result.agent.pane_id // empty' 2>/dev/null
}

ler_tela() { timeout 20 herdr pane read "$PANE" --source visible 2>/dev/null; }

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

  if printf '%s\n' "$tela" | grep -q 'Allow calling this tool?'; then
    registra parado "-" "diálogo de MCP"
    fim 1 decisao "diálogo de MCP no pane de $AGENTE"
  fi
  if printf '%s\n' "$tela" | grep -Eq 'Allow creation of this file\?|Accept this file edit\?'; then
    registra parado "-" "diálogo de arquivo (o worker não está em accept-edits?)"
    fim 1 decisao "diálogo de arquivo no pane de $AGENTE"
  fi

  if printf '%s\n' "$tela" | grep -q 'Requesting permission for:'; then
    bloco=$(printf '%s\n' "$tela" | sed -n '/Requesting permission for:/,/Run this command?/p' | sed '1d;$d')
    linhas=$(printf '%s\n' "$bloco" | grep -c .)
    # A tela quebra comando longo em várias linhas; junta sem espaço (a quebra
    # cai num espaço ou no meio de uma palavra, e juntar sem espaço nunca cria
    # fronteira de palavra nova que esconda um comando proibido).
    if ! printf '%s\n' "$tela" | grep -q 'Run this command?'; then
      sleep "$INTERVALO_S"; continue  # diálogo ainda desenhando
    fi
    cru=$(printf '%s\n' "$bloco" | sed -E 's/^ +//; s/ +$//' | grep . | tr '\n' ' ')
    if [ "$linhas" -gt 8 ]; then
      registra parado "$cru" "comando com mais de 8 linhas"
      fim 1 decisao "comando longo demais para conferir: $cru"
    fi
    # Largura do pane: a linha de separação "────" do diálogo ocupa a largura toda.
    largura=$(printf '%s\n' "$tela" | grep -E '^─{20,}$' | head -1)
    largura=${#largura}
    if [ "$linhas" -gt 1 ] && [ "$largura" -lt 20 ]; then
      registra parado "$cru" "comando em várias linhas sem largura do pane para conferir a quebra"
      fim 1 decisao "comando em várias linhas, sem largura do pane: $cru"
    fi
    if ! cmd=$(printf '%s\n' "$bloco" | juntar_linhas "$largura"); then
      MOTIVO="quebra de linha que não é da tela (comando em várias linhas)"
      registra parado "$cru" "$MOTIVO"
      fim 1 decisao "$MOTIVO :: $cru"
    fi
    if ! printf '%s\n' "$tela" | grep -Eq '^ *> 1\. Yes, run command *$'; then
      registra parado "$cmd" "opção 1 não está selecionada"
      fim 1 decisao "opção 1 não selecionada no diálogo: $cmd"
    fi
    if ! classificar "$cmd"; then
      registra parado "$cmd" "$MOTIVO"
      fim 1 decisao "$MOTIVO :: $cmd"
    fi
    timeout 20 herdr pane send-keys "$PANE" Enter >/dev/null 2>&1
    registra aprovado "$cmd" "$MOTIVO (opção 1, uma vez)"
    # Espera o diálogo deste comando sair da tela antes de olhar de novo, para
    # não responder duas vezes ao mesmo diálogo.
    primeira=$(printf '%s\n' "$bloco" | grep . | head -1 | sed -E 's/^ +//')
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 1
      ler_tela | grep -qF -- "${primeira:0:40}" || break
    done
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
