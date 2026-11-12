#!/bin/bash
# Lança, avisa e consulta workers do Herdr sem montar comando em variável.
# Usado pelo coordenador (references/despacho.md e references/acompanhamento.md).
#
# Não age sobre nada além do que o subcomando diz: `start` abre agentes em panes
# que você indicou, `prompt` envia UMA vez, `estado` só lê (`herdr agent get`).
#
# Uso:
#   herdr-workers.sh start  --kind <harness> [--timeout <ms>] <nome>=<pane>... [-- <arg do agente>...]
#   herdr-workers.sh prompt <agente> <texto> [--timeout <ms>]
#   herdr-workers.sh estado <agente>
#
#   <nome>=<pane>  um par por worker, já separado (`tg-77_executor=wA:p31`).
#                  O nome segue [a-z][a-z0-9_-]{0,31}. Tudo o que vier depois de
#                  `--` vai ao agente, na ordem (`-- --no-daemon` no Codex).
#   --timeout      em ms. start: espera o agente ficar pronto (padrão 30000).
#                  prompt: espera depois do envio (padrão 60000). Máximo 7200000
#                  (2 h); nenhuma espera é indefinida.
#
# Saída: SEMPRE um objeto JSON numa linha só, e é a última linha impressa. O campo
# `sinal` diz o que aconteceu e `resumo` repete em texto. Diagnóstico nunca vai
# para fora do JSON.
#
# Códigos de saída, por subcomando:
#   start   0 todos os agentes iniciados (sinal `iniciado`)
#           1 algum falhou (sinal `falhou`; `resultados` diz qual e por quê)
#           2 uso / ambiente (nada foi iniciado: os pares são validados antes)
#   prompt  0 entregue (`entregue`; ou `entregue_timeout`: o --wait estourou com
#             o agente `working`, o que prova a entrega e NÃO é falha)
#           1 erro inesperado do herdr
#           2 uso / ambiente
#           3 `nao_confirmado`: timeout sem o agente `working`. Nada foi
#             reenviado; leia a saída (`herdr agent read`) antes de decidir
#           4 `recusado_bloqueado`: o agente está `blocked` e nada foi enviado
#           5 `sumiu`: o alvo não existe (`agent_not_found`)
#   estado  0 working   10 idle   11 blocked   12 done   13 sumiu
#           14 desconhecido (status que o Herdr não classificou)   2 uso   1 erro
#
# Existe por duas falhas medidas em 2026-09-20 a 2026-11-12 nos transcripts dos
# agentes:
#   - o laço de disparo guardava os pares numa variável e fazia `set -- $x`; o
#     zsh (o Bash tool roda em zsh) não separa palavras de variável, então
#     `herdr agent start` recebeu `tg-245 w1:p3C_executor` como um alvo só
#     ("agent target ... not found", "unknown option: 90000"): 21 falhas em
#     6 sessões. Aqui os argumentos entram em array e o script é bash explícito.
#   - `herdr agent prompt --wait` com timeout curto devolveu `timeout` em 1.358
#     de 3.660 chamadas, na maioria com o prompt já entregue e o agente
#     `working`, e foi tratado como falha (e às vezes reenviado). Aqui o
#     timeout só é falha se o agente NÃO estiver `working`.
#
# Requer: herdr, jq.

set -euo pipefail

TIMEOUT_MAX=7200000

# --- saída -------------------------------------------------------------------

# emitir <sinal> <resumo> [jq-args...]: imprime o JSON final. Os campos extras
# chegam como `--arg k v` / `--argjson k v` e entram no objeto pelo nome.
emitir() {
  local sinal="$1" resumo="$2"
  shift 2
  jq -cn --arg sinal "$sinal" --arg resumo "$resumo" "$@" \
    '{sinal: $sinal, resumo: $resumo} + (
       [$ARGS.named | to_entries[] | select(.key != "sinal" and .key != "resumo")]
       | from_entries)'
}

uso() {
  emitir uso "$1" --arg uso "herdr-workers.sh start|prompt|estado (cabeçalho do script)"
  exit 2
}

# --- ambiente ----------------------------------------------------------------

for cmd in herdr jq; do
  command -v "$cmd" >/dev/null 2>&1 || {
    printf '{"sinal":"uso","resumo":"falta %s no PATH"}\n' "$cmd"
    exit 2
  }
done

validar_timeout() {  # <valor>
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le "$TIMEOUT_MAX" ] ||
    uso "--timeout deve ser um número de 1 a $TIMEOUT_MAX (ms), veio: $1"
}

# codigo_do_erro <saída do herdr>: o `.error.code` do JSON, ou vazio.
codigo_do_erro() {
  jq -r '.error.code // ""' <<<"$1" 2>/dev/null || true
}

# status_do_agente <agente>: imprime o status, `sumiu` ou `erro`.
status_do_agente() {
  local out rc=0 cod st
  out=$(herdr agent get "$1" 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    cod=$(codigo_do_erro "$out")
    if [ "$cod" = "agent_not_found" ]; then echo sumiu; else echo erro; fi
    return 0
  fi
  st=$(jq -r '.result.agent.agent_status // ""' <<<"$out" 2>/dev/null || true)
  echo "${st:-desconhecido}"
}

# --- start -------------------------------------------------------------------

cmd_start() {
  local kind="" timeout=30000 pares=() args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind) [ $# -ge 2 ] || uso "--kind sem valor"; kind="$2"; shift 2 ;;
      --timeout) [ $# -ge 2 ] || uso "--timeout sem valor"; timeout="$2"; shift 2 ;;
      --) shift; args=("$@"); break ;;
      -*) uso "opção desconhecida: $1" ;;
      *) pares+=("$1"); shift ;;
    esac
  done
  [ -n "$kind" ] || uso "start exige --kind <harness>"
  [ "${#pares[@]}" -gt 0 ] || uso "start exige ao menos um par <nome>=<pane>"
  validar_timeout "$timeout"

  local par nome pane
  for par in "${pares[@]}"; do
    [[ "$par" == *=* ]] || uso "par sem '=': $par (esperado <nome>=<pane>)"
    nome="${par%%=*}"
    pane="${par#*=}"
    [[ "$nome" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || uso "nome de agente inválido: $nome"
    [ -n "$pane" ] || uso "pane vazio no par: $par"
  done

  local resultados="[]" falhas=0 out rc cod msg ok
  for par in "${pares[@]}"; do
    nome="${par%%=*}"
    pane="${par#*=}"
    rc=0
    out=$(herdr agent start "$nome" --kind "$kind" --pane "$pane" \
      --timeout "$timeout" ${args[@]+-- "${args[@]}"} 2>&1) || rc=$?
    if [ "$rc" -eq 0 ]; then
      ok=true; cod=""; msg=""
    else
      ok=false
      falhas=$((falhas + 1))
      cod=$(codigo_do_erro "$out")
      msg=$(jq -r '.error.message // ""' <<<"$out" 2>/dev/null || true)
      [ -n "$msg" ] || msg="$out"
    fi
    resultados=$(jq -c --arg nome "$nome" --arg pane "$pane" --argjson ok "$ok" \
      --arg codigo "$cod" --arg mensagem "$msg" \
      '. + [{nome: $nome, pane: $pane, ok: $ok, codigo: $codigo, mensagem: $mensagem}]' \
      <<<"$resultados")
  done

  if [ "$falhas" -eq 0 ]; then
    emitir iniciado "${#pares[@]} agente(s) iniciado(s)" --argjson resultados "$resultados"
  else
    emitir falhou "$falhas de ${#pares[@]} agente(s) não iniciaram" --argjson resultados "$resultados"
    exit 1
  fi
}

# --- prompt ------------------------------------------------------------------

cmd_prompt() {
  local agente="" texto="" timeout=60000 pos=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --timeout) [ $# -ge 2 ] || uso "--timeout sem valor"; timeout="$2"; shift 2 ;;
      *) pos+=("$1"); shift ;;
    esac
  done
  [ "${#pos[@]}" -eq 2 ] || uso "prompt exige <agente> <texto>"
  agente="${pos[0]}"
  texto="${pos[1]}"
  [ -n "$agente" ] && [ -n "$texto" ] || uso "agente e texto não podem ser vazios"
  validar_timeout "$timeout"

  local out rc=0 cod st
  out=$(herdr agent prompt "$agente" "$texto" --wait --timeout "$timeout" 2>&1) || rc=$?

  if [ "$rc" -eq 0 ]; then
    st=$(status_do_agente "$agente")
    emitir entregue "prompt entregue a $agente (agora $st)" --arg agente "$agente" --arg estado "$st"
    return 0
  fi

  cod=$(codigo_do_erro "$out")
  case "$cod" in
    agent_not_found)
      emitir sumiu "$agente não existe; nada foi enviado" --arg agente "$agente"
      exit 5 ;;
    agent_blocked)
      emitir recusado_bloqueado "$agente está blocked; o Herdr recusou e nada foi enviado" \
        --arg agente "$agente"
      exit 4 ;;
    timeout|agent_prompt_stalled)
      st=$(status_do_agente "$agente")
      if [ "$st" = working ]; then
        emitir entregue_timeout \
          "$cod com $agente working: entrega confirmada, não reenvie" \
          --arg agente "$agente" --arg estado "$st" --arg codigo "$cod"
        return 0
      fi
      emitir nao_confirmado \
        "$cod e $agente está $st, sem estar working: entrega não confirmada; nada foi reenviado, leia a saída antes de decidir" \
        --arg agente "$agente" --arg estado "$st" --arg codigo "$cod"
      exit 3 ;;
    *)
      emitir erro "herdr agent prompt falhou (${cod:-sem código}); nada foi reenviado" \
        --arg agente "$agente" --arg codigo "$cod" --arg saida "$out"
      exit 1 ;;
  esac
}

# --- estado ------------------------------------------------------------------

cmd_estado() {
  [ $# -eq 1 ] && [ -n "$1" ] || uso "estado exige <agente>"
  local agente="$1" st
  st=$(status_do_agente "$agente")
  case "$st" in
    working) emitir working "$agente está working" --arg agente "$agente" --arg estado "$st"; exit 0 ;;
    idle) emitir idle "$agente está idle" --arg agente "$agente" --arg estado "$st"; exit 10 ;;
    blocked) emitir blocked "$agente está blocked" --arg agente "$agente" --arg estado "$st"; exit 11 ;;
    done) emitir "done" "$agente está done" --arg agente "$agente" --arg estado "$st"; exit 12 ;;
    sumiu) emitir sumiu "$agente não existe (agent_not_found)" --arg agente "$agente" --arg estado "$st"; exit 13 ;;
    erro) emitir erro "herdr agent get falhou para $agente" --arg agente "$agente" --arg estado "$st"; exit 1 ;;
    *) emitir desconhecido "$agente com status não classificado: $st" --arg agente "$agente" --arg estado "$st"; exit 14 ;;
  esac
}

# --- despacho ----------------------------------------------------------------

sub="${1:-}"
[ $# -gt 0 ] && shift
case "$sub" in
  start) cmd_start "$@" ;;
  prompt) cmd_prompt "$@" ;;
  estado) cmd_estado "$@" ;;
  *) uso "subcomando desconhecido ou ausente: ${sub:-<nenhum>}" ;;
esac
