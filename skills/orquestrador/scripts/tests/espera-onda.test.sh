#!/bin/bash
# Teste do espera-onda.sh com herdr, orq, gh e glab falsos no PATH.
# Nenhum comando age sobre agente, pane, onda ou MR reais.
# Uso: bash scripts/tests/espera-onda.test.sh   (de qualquer shell, inclusive zsh)
set -uo pipefail

AQUI=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$AQUI/../espera-onda.sh"
RAIZ=$(mktemp -d "${TMPDIR:-/tmp}/espera-onda-test.XXXXXX")
[ -n "$RAIZ" ] && [ -d "$RAIZ" ] || { echo 'mktemp falhou' >&2; exit 2; }
trap 'case "$RAIZ" in */espera-onda-test.*) rm -rf "$RAIZ" ;; esac' EXIT  # só o mktemp deste teste
BIN="$RAIZ/bin"; EST="$RAIZ/estado"
mkdir -p "$BIN" "$EST"

# herdr falso: estado do agente em $EST/<agente>.st; "sumido" => agent_not_found;
# "mudo" => saída ilegível (texto, como o `pane read`).
cat >"$BIN/herdr" <<'F'
#!/bin/bash
[ "$1 $2" = "agent get" ] || exit 9
f="$FAKE_EST/$3.st"
[ -e "$f" ] || { echo '{"error":{"code":"agent_not_found","message":"agent target not found"}}' >&2; exit 1; }
st=$(cat "$f")
case "$st" in
  sumido) echo '{"error":{"code":"agent_not_found","message":"x"}}' >&2; exit 1 ;;
  mudo) echo 'Working... (esc to interrupt)'; exit 0 ;;
  *) printf '{"id":"cli:agent:get","result":{"agent":{"name":"%s","agent_status":"%s"}}}\n' "$3" "$st" ;;
esac
F
# orq falso: devolve o conteúdo de $FAKE_EST/pend.json (ou []).
cat >"$BIN/orq" <<'F'
#!/bin/bash
[ "$1 $2" = "pend list" ] || exit 9
[ -e "$FAKE_EST/pend.json" ] && cat "$FAKE_EST/pend.json" || echo '[]'
F
cat >"$BIN/gh" <<'F'
#!/bin/bash
[ "$1 $2" = "pr view" ] || exit 9
cat "$FAKE_EST/mr.estado"
F
cat >"$BIN/glab" <<'F'
#!/bin/bash
[ "$1 $2" = "mr view" ] || exit 9
printf '{"state":"%s"}\n' "$(cat "$FAKE_EST/mr.estado")"
F
chmod +x "$BIN"/*
export FAKE_EST="$EST" PATH="$BIN:$PATH"

falhas=0
limpa() { rm -f "$EST"/*.st "$EST"/pend.json "$EST"/mr.estado "$RAIZ"/rel*.md; }
# caso <nome> <código esperado> <sinal esperado> -- args...
caso() {
  local nome=$1 cod=$2 sinal=$3; shift 4
  local saida rc
  saida=$(timeout 30 bash "$SCRIPT" "$@" 2>&1); rc=$?
  local ultima; ultima=$(printf '%s\n' "$saida" | grep '^espera-onda: sinal=' | tail -1)
  if [ "$rc" = "$cod" ] && [[ "$ultima" == "espera-onda: sinal=$sinal"* ]]; then
    echo "ok   $nome (saída $rc)"
  else
    echo "FALHA $nome: esperado $cod/$sinal, veio $rc/'$ultima'"; printf '%s\n' "$saida" | sed 's/^/     | /'
    falhas=$((falhas + 1))
  fi
}
R1="$RAIZ/rel1.md"; R2="$RAIZ/rel2.md"
RAPIDO=(--intervalo-s 1 --limite-s 20)

limpa; echo working >"$EST/a.st"; echo "pronto" >"$R1"
caso "relatório já gravado" 0 relatorio -- a="$R1" "${RAPIDO[@]}"

limpa; echo working >"$EST/a.st"; : >"$R1"
caso "relatório vazio não conta (cai no limite)" 3 limite -- a="$R1" --intervalo-s 1 --limite-s 2

limpa; echo blocked >"$EST/a.st"
caso "worker blocked" 1 blocked -- a="$R1" "${RAPIDO[@]}"

limpa
caso "pane sumido (agent_not_found)" 4 pane-sumido -- a="$R1" "${RAPIDO[@]}"

limpa; echo idle >"$EST/a.st"
caso "idle sem relatório por --parado-s" 5 parado -- a="$R1" --parado-s 2 "${RAPIDO[@]}"

limpa; echo "done" >"$EST/a.st"
caso "done sem relatório por --parado-s" 5 parado -- a="$R1" --parado-s 2 "${RAPIDO[@]}"

limpa; echo working >"$EST/a.st"
caso "working zera o contador e vai ao limite" 3 limite -- a="$R1" --parado-s 1 --intervalo-s 1 --limite-s 3

# working zera: idle por 1 volta, working, idle de novo; com --parado-s 3 não deve sair parado antes do limite de 4s
limpa; echo idle >"$EST/a.st"
( sleep 1.5; echo working >"$EST/a.st"; sleep 1; echo idle >"$EST/a.st" ) &
caso "idle intercalado com working não dispara parado" 3 limite -- a="$R1" --parado-s 3 --intervalo-s 1 --limite-s 4
wait

limpa; echo working >"$EST/a.st"; echo working >"$EST/b.st"
( sleep 1.5; echo "x" >"$R2" ) &
caso "dois agentes: o segundo grava" 0 relatorio -- a="$R1" b="$R2" "${RAPIDO[@]}"
wait

limpa; echo working >"$EST/a.st"; echo working >"$EST/b.st"
( sleep 1.5; echo blocked >"$EST/b.st" ) &
caso "dois agentes: o segundo bloqueia" 1 blocked -- a="$R1" b="$R2" "${RAPIDO[@]}"
wait

limpa; echo working >"$EST/a.st"; echo '[{"chave":"orq/75#P1","estado":"respondida"}]' >"$EST/pend.json"
caso "pendência respondida" 6 pendencia -- a="$R1" --onda 219 "${RAPIDO[@]}"

limpa; echo working >"$EST/a.st"; echo '[{"chave":"orq/75#P1"}]' >"$EST/pend.json"
caso "pendência ignorada sem --onda" 3 limite -- a="$R1" --intervalo-s 1 --limite-s 2

limpa; echo working >"$EST/a.st"; echo '[]' >"$EST/pend.json"
caso "sem pendência respondida segue esperando" 3 limite -- a="$R1" --onda 219 --intervalo-s 1 --limite-s 2

limpa; echo working >"$EST/a.st"; echo MERGED >"$EST/mr.estado"
caso "PR do GitHub mesclado" 7 mr -- a="$R1" --mr https://github.com/BasisTI/skills/pull/1 "${RAPIDO[@]}"

limpa; echo working >"$EST/a.st"; echo OPEN >"$EST/mr.estado"
caso "PR aberto segue esperando" 3 limite -- a="$R1" --mr https://github.com/BasisTI/skills/pull/1 --intervalo-s 1 --limite-s 2

limpa; echo working >"$EST/a.st"; echo closed >"$EST/mr.estado"
caso "MR do GitLab fechada" 7 mr -- a="$R1" --mr https://gitlab.exemplo.com/g/p/-/merge_requests/1 "${RAPIDO[@]}"

limpa; echo mudo >"$EST/a.st"
caso "herdr sem resposta legível" 8 herdr-indisponivel -- a="$R1" --intervalo-s 1 --limite-s 20

limpa
caso "sem agente" 2 uso -- "${RAPIDO[@]}"
caso "argumento sem =" 2 uso -- agente-sem-igual
caso "opção desconhecida" 2 uso -- a="$R1" --zzz
caso "número inválido" 2 uso -- a="$R1" --limite-s abc

# comando ausente: PATH sem jq
limpa
saida=$(PATH="$BIN" /bin/bash "$SCRIPT" a="$R1" 2>&1); rc=$?
if [ "$rc" = 2 ] && [[ "$saida" == *"sinal=uso falta"* ]]; then echo "ok   comando ausente (saída 2)"; else echo "FALHA comando ausente: $rc $saida"; falhas=$((falhas + 1)); fi

echo
if [ "$falhas" -eq 0 ]; then echo "todos os casos passaram"; else echo "$falhas caso(s) falharam"; exit 1; fi
