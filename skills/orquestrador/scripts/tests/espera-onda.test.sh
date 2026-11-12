#!/bin/bash
# Teste do espera-onda.sh com herdr, orq, gh e glab falsos no PATH.
# Nenhum comando age sobre agente, pane, onda ou MR reais. Os fakes registram os
# argumentos recebidos, e o teste os confere (um filtro errado ou um flag
# esquecido deixa de passar despercebido).
# Uso: bash scripts/tests/espera-onda.test.sh   (de qualquer shell, inclusive zsh)
set -uo pipefail

AQUI=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$AQUI/../espera-onda.sh"
RAIZ=$(mktemp -d "${TMPDIR:-/tmp}/espera-onda-test.XXXXXX")
[ -n "$RAIZ" ] && [ -d "$RAIZ" ] || { echo 'mktemp falhou' >&2; exit 2; }
trap 'case "$RAIZ" in */espera-onda-test.*) rm -rf "$RAIZ" ;; esac' EXIT  # só o mktemp deste teste
BIN="$RAIZ/bin"; EST="$RAIZ/estado"
mkdir -p "$BIN" "$EST"

# Todos os fakes: gravam "$*" em $EST/<cmd>.args; "<cmd>.trava" faz o comando
# dormir (comando travado); "<cmd>.falha" faz sair 1 com erro no stderr.
# herdr: estado em $EST/<agente>.st, ou fila em $EST/<agente>.seq (consome a
# primeira linha; a última fica). "sumido" => agent_not_found no stderr;
# "mudo" => texto em vez de JSON (o herdr-workers.sh o lê como `desconhecido`);
# "falha" => erro sem JSON, rc 1.
cat >"$BIN/herdr" <<'F'
#!/bin/bash
echo "$*" >>"$FAKE_EST/herdr.args"
[ -e "$FAKE_EST/herdr.trava" ] && sleep 60
[ "$1 $2" = "agent get" ] || exit 9
if [ -e "$FAKE_EST/$3.seq" ]; then
  st=$(head -1 "$FAKE_EST/$3.seq")
  [ "$(wc -l <"$FAKE_EST/$3.seq")" -gt 1 ] && sed -i 1d "$FAKE_EST/$3.seq"
elif [ -e "$FAKE_EST/$3.st" ]; then st=$(cat "$FAKE_EST/$3.st")
else st=sumido; fi
case "$st" in
  sumido) echo '{"error":{"code":"agent_not_found","message":"x"}}' >&2; exit 1 ;;
  mudo) echo 'Working... (esc to interrupt)'; exit 0 ;;
  falha) echo 'herdr: socket indisponível' >&2; exit 1 ;;
  *) printf '{"id":"cli:agent:get","result":{"agent":{"name":"%s","agent_status":"%s"}}}\n' "$3" "$st" ;;
esac
F
# orq: devolve $EST/pend.json, ou a fila $EST/pend.seq (nomes de arquivos pend.<x>.json).
cat >"$BIN/orq" <<'F'
#!/bin/bash
echo "$*" >>"$FAKE_EST/orq.args"
[ -e "$FAKE_EST/orq.trava" ] && sleep 60
[ -e "$FAKE_EST/orq.falha" ] && { echo "orq: erro de teste" >&2; exit 1; }
[ "$1 $2" = "pend list" ] || exit 9
if [ -e "$FAKE_EST/pend.seq" ]; then
  x=$(head -1 "$FAKE_EST/pend.seq")
  [ "$(wc -l <"$FAKE_EST/pend.seq")" -gt 1 ] && sed -i 1d "$FAKE_EST/pend.seq"
  cat "$FAKE_EST/pend.$x.json"
elif [ -e "$FAKE_EST/pend.json" ]; then cat "$FAKE_EST/pend.json"; else echo '[]'; fi
F
cat >"$BIN/gh" <<'F'
#!/bin/bash
echo "$*" >>"$FAKE_EST/gh.args"
[ -e "$FAKE_EST/gh.trava" ] && sleep 60
[ -e "$FAKE_EST/gh.falha" ] && { echo "gh: HTTP 401" >&2; exit 1; }
[ "$1 $2" = "pr view" ] || exit 9
cat "$FAKE_EST/mr.estado"
F
cat >"$BIN/glab" <<'F'
#!/bin/bash
echo "$*" >>"$FAKE_EST/glab.args"
[ -e "$FAKE_EST/glab.falha" ] && { echo "glab: 404" >&2; exit 1; }
[ "$1 $2" = "mr view" ] || exit 9
printf '{"state":"%s"}\n' "$(cat "$FAKE_EST/mr.estado")"
F
chmod +x "$BIN"/*
export FAKE_EST="$EST" PATH="$BIN:$PATH"

falhas=0
ERRO() { echo "FALHA $*"; falhas=$((falhas + 1)); }
limpa() { rm -f "$EST"/* "$RAIZ"/rel*.md; rmdir "$RAIZ/dir" 2>/dev/null || true; }
SAIDA="" RC=0
# rodar <args...>: guarda SAIDA e RC
rodar() { SAIDA=$(timeout 40 bash "$SCRIPT" "$@" 2>&1); RC=$?; }
ultima() { printf '%s\n' "$SAIDA" | grep '^espera-onda: sinal=' | tail -1; }
# caso <nome> <código> <sinal> -- args...
caso() {
  local nome=$1 cod=$2 sinal=$3; shift 4
  rodar "$@"
  local u; u=$(ultima)
  if [ "$RC" = "$cod" ] && [[ "$u" == "espera-onda: sinal=$sinal"* ]]; then
    echo "ok   $nome (saída $RC)"
  else
    ERRO "$nome: esperado $cod/$sinal, veio $RC/'$u'"; printf '%s\n' "$SAIDA" | sed 's/^/     | /'
  fi
}
# args <arquivo> <linha exata>: o fake recebeu exatamente essa linha de argumentos
args() {
  if grep -qxF -- "$2" "$EST/$1.args" 2>/dev/null; then echo "ok   $1 recebeu: $2"
  else ERRO "$1 não recebeu '$2'; recebeu: $(cat "$EST/$1.args" 2>/dev/null | head -3 | tr '\n' '|')"; fi
}
R1="$RAIZ/rel1.md"; R2="$RAIZ/rel2.md"
RAPIDO=(--intervalo-s 1 --limite-s 20)
NOVA='[{"chave":"orq/75#P1","estado":"respondida","respondida_em":"2099-01-01T00:00:00Z"}]'
VELHA='[{"chave":"orq/75#P1","estado":"respondida","respondida_em":"2020-01-01T00:00:00Z"}]'

limpa; echo working >"$EST/a.st"; echo "pronto" >"$R1"
caso "relatório já gravado" 0 relatorio -- a="$R1" "${RAPIDO[@]}"

limpa; echo working >"$EST/a.st"; : >"$R1"
caso "relatório vazio não conta" 3 limite -- a="$R1" --intervalo-s 1 --limite-s 2
args herdr "agent get a"

limpa; echo working >"$EST/a.st"; mkdir "$RAIZ/dir"
caso "diretório no lugar do relatório não conta" 3 limite -- a="$RAIZ/dir" --intervalo-s 1 --limite-s 2
rmdir "$RAIZ/dir"

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

# --- padrões ---------------------------------------------------------------
limpa; echo working >"$EST/a.st"
SAIDA=$(timeout 2 bash "$SCRIPT" a="$R1" 2>&1); 
if [[ "$SAIDA" == *"parado 600s, limite 6600s"* ]]; then echo "ok   padrões: parado 600, limite 6600"; else ERRO "padrões: $SAIDA"; fi

# --- falhas do herdr -------------------------------------------------------
limpa; echo mudo >"$EST/a.st"
caso "saída ilegível vale como desconhecido e cai em parado" 5 parado -- a="$R1" --parado-s 2 "${RAPIDO[@]}"

limpa; echo falha >"$EST/a.st"
caso "herdr sem leitura 5 voltas seguidas" 8 herdr-indisponivel -- a="$R1" "${RAPIDO[@]}"

limpa; printf 'falha\nfalha\nfalha\nfalha\nworking\nfalha\nfalha\nfalha\nfalha\nworking\n' >"$EST/a.seq"
caso "4 falhas, leitura boa, 4 falhas: o contador zera" 3 limite -- a="$R1" --intervalo-s 1 --limite-s 12

# --- pendência -------------------------------------------------------------
limpa; echo working >"$EST/a.st"; echo "$NOVA" >"$EST/pend.json"
caso "pendência respondida depois do início" 6 pendencia -- a="$R1" --onda 219 "${RAPIDO[@]}"
args orq "pend list --respondidas --onda 219 --output json"

limpa; echo working >"$EST/a.st"; echo "$VELHA" >"$EST/pend.json"
caso "resposta anterior à armada não dispara (armada 1)" 3 limite -- a="$R1" --onda 219 --intervalo-s 1 --limite-s 2
caso "a mesma pendência na armada 2" 3 limite -- a="$R1" --onda 219 --intervalo-s 1 --limite-s 2

limpa; echo working >"$EST/a.st"; echo "$VELHA" >"$EST/pend.velha.json"; echo "$NOVA" >"$EST/pend.nova.json"
printf 'velha\nvelha\nnova\n' >"$EST/pend.seq"
caso "resposta que chega durante a espera" 6 pendencia -- a="$R1" --onda 219 --intervalo-s 1 --limite-s 10

limpa; echo working >"$EST/a.st"; echo "$NOVA" >"$EST/pend.json"
caso "--ignorar cala a chave" 3 limite -- a="$R1" --onda 219 --ignorar "orq/75#P1" --intervalo-s 1 --limite-s 2

limpa; echo working >"$EST/a.st"; echo "$NOVA" >"$EST/pend.json"
caso "--ignorar de outra chave não cala" 6 pendencia -- a="$R1" --onda 219 --ignorar "orq/99#P1" "${RAPIDO[@]}"

limpa; echo working >"$EST/a.st"; echo "$NOVA" >"$EST/pend.json"
caso "pendência ignorada sem --onda" 3 limite -- a="$R1" --intervalo-s 1 --limite-s 2

limpa; echo working >"$EST/a.st"; echo '[]' >"$EST/pend.json"
caso "sem pendência segue esperando" 3 limite -- a="$R1" --onda 219 --intervalo-s 1 --limite-s 2

limpa; echo working >"$EST/a.st"; : >"$EST/orq.falha"
caso "orq falhando 5 voltas" 9 fonte-indisponivel -- a="$R1" --onda 219 "${RAPIDO[@]}"
if [[ "$(ultima)" == *"orq: erro de teste"* ]]; then echo "ok   a causa vai na linha final"; else ERRO "causa ausente: $(ultima)"; fi

limpa; echo working >"$EST/a.st"; echo "texto, não JSON" >"$EST/pend.json"
caso "orq com saída ilegível" 9 fonte-indisponivel -- a="$R1" --onda 219 "${RAPIDO[@]}"

# --- MR --------------------------------------------------------------------
limpa; echo working >"$EST/a.st"; echo MERGED >"$EST/mr.estado"
caso "PR do GitHub mesclado" 7 mr -- a="$R1" --mr https://github.com/BasisTI/skills/pull/1 "${RAPIDO[@]}"
args gh "pr view https://github.com/BasisTI/skills/pull/1 --json state -q .state"

limpa; echo working >"$EST/a.st"; echo OPEN >"$EST/mr.estado"
caso "PR aberto segue esperando" 3 limite -- a="$R1" --mr https://github.com/BasisTI/skills/pull/1 --intervalo-s 1 --limite-s 2

limpa; echo working >"$EST/a.st"; echo closed >"$EST/mr.estado"
caso "MR do GitLab fechada" 7 mr -- a="$R1" --mr https://gitlab.exemplo.com/g/sub/p/-/merge_requests/12 "${RAPIDO[@]}"
args glab "mr view 12 -R g/sub/p --output json"

limpa; echo working >"$EST/a.st"; echo merged >"$EST/mr.estado"
caso "URL de GitLab fora do padrão vai inteira" 7 mr -- a="$R1" --mr https://gitlab.exemplo.com/outra "${RAPIDO[@]}"
args glab "mr view https://gitlab.exemplo.com/outra --output json"

limpa; echo working >"$EST/a.st"; : >"$EST/gh.falha"
caso "gh falhando 5 voltas" 9 fonte-indisponivel -- a="$R1" --mr https://github.com/BasisTI/skills/pull/1 "${RAPIDO[@]}"
if [[ "$(ultima)" == *"HTTP 401"* ]]; then echo "ok   a causa do gh vai na linha final"; else ERRO "causa do gh ausente: $(ultima)"; fi

limpa; echo working >"$EST/a.st"; : >"$EST/glab.falha"
caso "glab falhando 5 voltas" 9 fonte-indisponivel -- a="$R1" --mr https://gitlab.exemplo.com/g/p/-/merge_requests/1 "${RAPIDO[@]}"

# --- comando travado: o limite vale ---------------------------------------
limpa; echo working >"$EST/a.st"; : >"$EST/gh.trava"; echo OPEN >"$EST/mr.estado"
t0=$(date +%s)
caso "gh travado não estoura o limite" 3 limite -- a="$R1" --mr https://github.com/BasisTI/skills/pull/1 --intervalo-s 1 --limite-s 3
d=$(( $(date +%s) - t0 )); if [ "$d" -le 8 ]; then echo "ok   terminou em ${d}s (limite 3s)"; else ERRO "demorou ${d}s com limite de 3s"; fi

limpa; echo working >"$EST/a.st"; : >"$EST/herdr.trava"
t0=$(date +%s)
caso "herdr travado não estoura o limite" 3 limite -- a="$R1" --intervalo-s 1 --limite-s 3
d=$(( $(date +%s) - t0 )); if [ "$d" -le 8 ]; then echo "ok   terminou em ${d}s (limite 3s)"; else ERRO "demorou ${d}s com limite de 3s"; fi

# --- uso -------------------------------------------------------------------
limpa
caso "sem agente" 2 uso -- "${RAPIDO[@]}"
caso "argumento sem =" 2 uso -- agente-sem-igual
caso "opção desconhecida" 2 uso -- a="$R1" --zzz
caso "número inválido" 2 uso -- a="$R1" --limite-s abc
caso "limite acima do teto" 2 uso -- a="$R1" --limite-s 7201
caso "limite acima de 64 bits" 2 uso -- a="$R1" --limite-s 99999999999999999999
caso "parado acima do teto" 2 uso -- a="$R1" --parado-s 7201
caso "--ignorar sem --onda" 2 uso -- a="$R1" --ignorar x
echo working >"$EST/a.st"; echo x >"$R1"
caso "zeros à esquerda não viram octal" 0 relatorio -- a="$R1" --limite-s 08 --intervalo-s 09

rodar --help
if [ "$RC" = 0 ] && [[ "$SAIDA" == *"Uso:"* ]] && ! printf '%s\n' "$SAIDA" | grep -q '^espera-onda: sinal='   && [[ "$SAIDA" != *"set -euo"* ]]; then echo "ok   --help (saída 0, só o cabeçalho)"; else ERRO "--help: rc=$RC"; fi

limpa
saida=$(PATH="$BIN" /bin/bash "$SCRIPT" a="$R1" 2>&1); rc=$?
if [ "$rc" = 2 ] && [[ "$saida" == *"sinal=uso falta"* ]]; then echo "ok   comando ausente (saída 2)"; else ERRO "comando ausente: $rc $saida"; fi

echo
if [ "$falhas" -eq 0 ]; then echo "todos os casos passaram"; else echo "$falhas caso(s) falharam"; exit 1; fi
