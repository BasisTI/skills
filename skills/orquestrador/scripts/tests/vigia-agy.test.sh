#!/bin/bash
# Teste do vigia-agy.sh com herdr falso no PATH. Nenhum comando age sobre pane
# ou agente reais: o fake lê a tela de um arquivo e registra as teclas enviadas,
# e o teste confere que o vigia só envia Enter quando deve.
# Uso: bash scripts/tests/vigia-agy.test.sh   (de qualquer shell, inclusive zsh)
set -uo pipefail
export LC_ALL=C.UTF-8

AQUI=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$AQUI/../vigia-agy.sh"
RAIZ=$(mktemp -d "${TMPDIR:-/tmp}/vigia-agy-test.XXXXXX")
[ -n "$RAIZ" ] && [ -d "$RAIZ" ] || { echo 'mktemp falhou' >&2; exit 2; }
trap 'rm -rf -- "$RAIZ"' EXIT
BIN="$RAIZ/bin"; EST="$RAIZ/estado"
mkdir -p "$BIN" "$EST"

# herdr falso:
#   agent get <a>     estado em $EST/st (working|idle|blocked|done|sumido|falha)
#   pane read <pane>  imprime $EST/tela (ausente = tela vazia)
#   pane send-keys    grava a tecla em $EST/keys; troca a tela por $EST/tela.depois
#                     (ou apaga) e, com $EST/cria.relatorio, grava o relatório
#                     cujo caminho está nele.
cat >"$BIN/herdr" <<'F'
#!/bin/bash
echo "$*" >>"$FAKE_EST/herdr.args"
case "$1 $2" in
  "agent get")
    st=$(cat "$FAKE_EST/st" 2>/dev/null || echo sumido)
    case "$st" in
      sumido) echo '{"error":{"code":"agent_not_found","message":"x"}}' >&2; exit 1 ;;
      falha) echo 'herdr: socket indisponível' >&2; exit 1 ;;
      *) printf '{"id":"cli:agent:get","result":{"agent":{"name":"%s","pane_id":"w9:pZ","agent_status":"%s"}}}\n' "$3" "$st" ;;
    esac ;;
  "pane read")
    [ "$(cat "$FAKE_EST/st" 2>/dev/null)" = falha ] && exit 1
    cat "$FAKE_EST/tela" 2>/dev/null; exit 0 ;;
  "pane send-keys")
    echo "$4" >>"$FAKE_EST/keys"
    if [ -e "$FAKE_EST/tela.depois" ]; then mv "$FAKE_EST/tela.depois" "$FAKE_EST/tela"; else rm -f "$FAKE_EST/tela"; fi
    [ -e "$FAKE_EST/cria.relatorio" ] && echo ok >"$(cat "$FAKE_EST/cria.relatorio")"
    exit 0 ;;
  *) exit 9 ;;
esac
F
chmod +x "$BIN/herdr"
export PATH="$BIN:$PATH" FAKE_EST="$EST"

falhas=0
ok() { printf 'ok   %s\n' "$1"; }
erro() { printf 'FALHA %s\n' "$1"; falhas=$((falhas + 1)); }

LARG=80
SEP=$(printf '─%.0s' $(seq 1 "$LARG"))

# tela_dialogo <opção selecionada 1..4> <linha1> [linha2...]: diálogo de comando
# como o agy 1.5.14 desenha (primeira linha com 3 espaços, as seguintes sem).
tela_dialogo() {
  local sel="$1"; shift
  {
    echo "● Running (comando) (ctrl+o to expand)"
    echo "Command"
    echo "$SEP"
    echo "Requesting permission for:"
    printf '   %s\n' "$1"; shift
    for l in "$@"; do printf '%s\n' "$l"; done
    echo "Run this command?"
    local i txt
    for i in 1 2 3 4; do
      case $i in
        1) txt="Yes, run command" ;;
        2) txt="Yes, and always allow in this conversation for commands that start with 'x'" ;;
        3) txt="Yes, and always allow for commands that start with 'x' (Persist to settings.json)" ;;
        4) txt="No, cancel" ;;
      esac
      if [ "$i" = "$sel" ]; then echo "> $i. $txt"; else echo "  $i. $txt"; fi
    done
    echo "  ↑/↓ Navigate · tab Amend · ctrl+g edit/expand command"
    echo "esc to cancel                                  accept-edits · qa-adversarial (Gemini 4 Neon · high)"
  } >"$EST/tela"
}

limpar() { rm -f "$EST"/*; rm -f "$RAIZ"/relatorio.md "$RAIZ"/aprov.log; }
REL="$RAIZ/relatorio.md"; LOG="$RAIZ/aprov.log"
SLOT="$HOME/tmp/orquestrador/proj/build-slot.sh"

roda() {  # roda <args extras...>: vigia com intervalo curto; saída em $SAIDA, código em $RC
  SAIDA=$(timeout 60 bash "$SCRIPT" "tg-1_revisor=$REL" --log "$LOG" --intervalo-s 1 --build-slot "$SLOT" "$@" 2>&1)
  RC=$?
}

# --- 1. classificação -------------------------------------------------------
aprova=(
  "git rev-parse HEAD && git status --short && glab api user | jq -r .username"
  "glab api 'projects/5375/merge_requests/36/notes?per_page=100' | jq -r '.[] | select(.id == 51159) | .body'"
  "git log --oneline d99cf7d..HEAD && echo \"---STAT---\" && git diff --stat d99cf7d..HEAD"
  "glab mr view 38 -F json | jq '{iid, state, draft}'"
  "sonar qg status -p proj-core --pull-request 38 && echo x && sonar issues list -p proj-core --pull-request 38"
  "taiga story get 32 --project proj"
  "df -h ~ /tmp && echo \"---TRILHA---\" && grep -rn \"trilha\\.registrar\\|TrilhaProperties\" src/"
  "find src/main -type f | sort"
  "~/tmp/orquestrador/proj/build-slot.sh ./mvnw verify"
  "$SLOT ./mvnw verify -q 2>&1 | tail -20"
  "$SLOT uv run python -m pytest tests -q"
  "javap -cp \"\$(find ~/.m2/repository/org/springframework/spring-webmvc -name 'spring-webmvc-*.jar' | sort -V | tail -1)\" -c -p org.x.Y | grep -A 45 \"saveOutputFlashMap\\|x\""
  "tr -d '\\r' < /home/u/saida.txt | grep -E \"^\\[INFO\\] Tests run\""
  "sed -n '10,40p' src/A.java"
  "ps -p 3970978 -o pid,comm || true"
  "cat src/main/resources/application.yml 2>/dev/null"
  "herdr agent get coord-x"
  "grep -rn 'th:' src/main/resources/templates | wc -l"
)
para=(
  "./mvnw verify"
  "/outro/build-slot.sh ./mvnw verify"
  "$SLOT rm -rf target"
  "rm -rf target"
  "cat x > y"
  "echo \$(id)"
  "echo \`id\`"
  "find . -name '*.java' -exec cat {} +"
  "find . -name x -delete"
  "glab api projects/1/merge_requests/38/notes -X POST -f body=x"
  "glab api projects/1/merge_requests/38/notes -F body=@nota.md"
  "glab api 'projects/1/merge_requests/38/notes' --method POST -F 'body=@n.md' | jq '{id}'"
  "glab mr merge 38"
  "git branch -D x"
  "git push origin HEAD"
  "git -c core.pager=sh log"
  "sed -n '1w /tmp/x' a"
  "sed -i 's/a/b/' a"
  "sort -o saida entrada"
  "grep rm src | xargs rm"
  "cat .env"
  "cat ~/.kube/config"
  "grep -rn token src/"
  "TMPDIR=/x ls"
  "bash -c 'ls'"
  "python3 x.py"
  "mkdir -p /tmp/x && javac -d /tmp/x A.java"
  "java -cp target/classes QaRunner x"
  "mv a b"
  "ls; cp a b"
  "cat <<EOF"
  "diff <(ls a) <(ls b)"
  "rg --pre ./x.sh foo"
  "git grep -Ovi foo"
  "kill 123"
  "curl -s http://x"
  "git diff --output=/tmp/x"
  ""
)
for c in "${aprova[@]}"; do
  if out=$(bash "$SCRIPT" --classificar "$c" --build-slot "$SLOT" 2>&1); then ok "aprova: ${c:0:70}"; else erro "devia aprovar: $c => $out"; fi
done
for c in "${para[@]}"; do
  if out=$(bash "$SCRIPT" --classificar "$c" --build-slot "$SLOT" 2>&1); then erro "devia parar: $c"; else
    case "$out" in para:*) ok "para: ${c:0:70}" ;; *) erro "saída inesperada para $c: $out" ;; esac
  fi
done
# sem --build-slot, nem o caminho do slot passa
if bash "$SCRIPT" --classificar "$SLOT ./mvnw verify" >/dev/null 2>&1; then erro "slot sem --build-slot devia parar"; else ok "slot sem --build-slot para"; fi

# --- 2. laço: aprova da lista e sai no relatório ------------------------------
limpar; echo working >"$EST/st"
tela_dialogo 1 "git status --short"
echo "$REL" >"$EST/cria.relatorio"
roda --limite-s 30
if [ "$RC" -eq 0 ] && grep -q 'sinal=relatorio' <<<"$SAIDA" && [ "$(cat "$EST/keys")" = "Enter" ] &&
   grep -q $'\taprovado\tgit status --short\t' "$LOG"; then ok "aprova uma vez, registra e sai no relatório"; else erro "aprovação+relatório: rc=$RC saida=$SAIDA keys=$(cat "$EST/keys" 2>/dev/null)"; fi

# --- 3. comando proibido: não responde, sai com decisao ----------------------
limpar; echo blocked >"$EST/st"
tela_dialogo 1 "rm -rf target"
roda --limite-s 30
if [ "$RC" -eq 1 ] && grep -q 'sinal=decisao' <<<"$SAIDA" && [ ! -e "$EST/keys" ] &&
   grep -q $'\tparado\trm -rf target\t' "$LOG"; then ok "proibido para sem tecla"; else erro "proibido: rc=$RC saida=$SAIDA"; fi

# --- 4. opção 1 não selecionada -----------------------------------------------
limpar; echo blocked >"$EST/st"
tela_dialogo 2 "git status"
roda --limite-s 30
if [ "$RC" -eq 1 ] && grep -q 'opção 1 não selecionada' <<<"$SAIDA" && [ ! -e "$EST/keys" ]; then ok "outra opção selecionada para sem tecla"; else erro "opção: rc=$RC saida=$SAIDA"; fi

# --- 5. quebra da tela: linha cheia junta sem espaço e aprova ------------------
limpar; echo blocked >"$EST/st"
l1="git log --oneline --format=%h -- src/main/java/br/com/basis/projeto/modulo/in"   # 3 + 77 = 80 colunas
[ $(( ${#l1} + 3 )) -eq "$LARG" ] || erro "fixture l1 com largura errada: $(( ${#l1} + 3 ))"
tela_dialogo 1 "$l1" "ternal/Classe.java"
echo "$REL" >"$EST/cria.relatorio"
roda --limite-s 30
if [ "$RC" -eq 0 ] && grep -q $'\taprovado\tgit log --oneline --format=%h -- src/main/java/br/com/basis/projeto/modulo/internal/Classe.java\t' "$LOG"; then ok "quebra no meio da palavra junta sem espaço"; else erro "quebra cheia: rc=$RC saida=$SAIDA log=$(cat "$LOG")"; fi

# --- 6. quebra no espaço: palavra seguinte não cabia, junta com espaço --------
limpar; echo blocked >"$EST/st"
tela_dialogo 1 "grep -rn \"abc\" src/main/java/br/com/basis/projeto/modulo/internal/Um.java" "src/main/java/br/com/basis/projeto/modulo/internal/Dois.java"
echo "$REL" >"$EST/cria.relatorio"
roda --limite-s 30
if [ "$RC" -eq 0 ] && grep -q 'Um.java src/main' "$LOG"; then ok "quebra no espaço junta com espaço"; else erro "quebra no espaço: rc=$RC saida=$SAIDA log=$(cat "$LOG" 2>/dev/null)"; fi

# --- 7. nova linha de verdade esconde outro comando: para ---------------------
for segunda in "rm -rf /" "python3 x.py" "ls"; do
  limpar; echo blocked >"$EST/st"
  tela_dialogo 1 "echo a" "$segunda"
  roda --limite-s 30
  if [ "$RC" -eq 1 ] && grep -q 'quebra de linha que não é da tela' <<<"$SAIDA" && [ ! -e "$EST/keys" ]; then ok "nova linha real para: echo a / $segunda"; else erro "nova linha: $segunda rc=$RC saida=$SAIDA"; fi
done

# --- 8. diálogo de MCP e de arquivo ---------------------------------------------
limpar; echo blocked >"$EST/st"
printf 'Allow calling this tool?\n> 1. Yes\n' >"$EST/tela"
roda --limite-s 30
if [ "$RC" -eq 1 ] && grep -q 'diálogo de MCP' <<<"$SAIDA" && [ ! -e "$EST/keys" ]; then ok "MCP para"; else erro "MCP: rc=$RC saida=$SAIDA"; fi
limpar; echo done >"$EST/st"
printf 'Accept this file edit?\n> 1. Yes\n' >"$EST/tela"
roda --limite-s 30
if [ "$RC" -eq 1 ] && grep -q 'diálogo de arquivo' <<<"$SAIDA"; then ok "diálogo de arquivo para"; else erro "arquivo: rc=$RC saida=$SAIDA"; fi

# --- 9. blocked sem diálogo reconhecido -----------------------------------------
limpar; echo blocked >"$EST/st"
echo "algo diferente na tela" >"$EST/tela"
roda --limite-s 30 --bloqueado-s 2
if [ "$RC" -eq 1 ] && grep -q 'sem diálogo reconhecido' <<<"$SAIDA"; then ok "blocked sem diálogo para"; else erro "blocked: rc=$RC saida=$SAIDA"; fi

# --- 10. ocioso, sumido, limite, herdr fora ----------------------------------------
limpar; echo idle >"$EST/st"; echo "> " >"$EST/tela"
roda --limite-s 30 --ocioso-s 2
if [ "$RC" -eq 5 ] && grep -q 'sinal=ocioso' <<<"$SAIDA"; then ok "ocioso"; else erro "ocioso: rc=$RC saida=$SAIDA"; fi
limpar; echo sumido >"$EST/st"
roda --limite-s 30
if [ "$RC" -eq 4 ] && grep -q 'sinal=pane-sumido' <<<"$SAIDA"; then ok "pane sumido"; else erro "sumido: rc=$RC saida=$SAIDA"; fi
limpar; echo working >"$EST/st"; echo "trabalhando" >"$EST/tela"
roda --limite-s 2
if [ "$RC" -eq 3 ] && grep -q 'sinal=limite' <<<"$SAIDA"; then ok "limite"; else erro "limite: rc=$RC saida=$SAIDA"; fi
limpar; echo falha >"$EST/st"
roda --limite-s 30
if [ "$RC" -eq 8 ] && grep -q 'sinal=herdr-indisponivel' <<<"$SAIDA"; then ok "herdr indisponível"; else erro "herdr fora: rc=$RC saida=$SAIDA"; fi

# --- 11. uso ------------------------------------------------------------------------
SAIDA=$(bash "$SCRIPT" "a=$REL" 2>&1); RC=$?
[ "$RC" -eq 2 ] && grep -q 'sinal=uso' <<<"$SAIDA" && ok "uso: sem --log" || erro "uso sem --log: rc=$RC"
SAIDA=$(bash "$SCRIPT" "a=$REL" "b=$REL" --log "$LOG" 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok "uso: dois agentes" || erro "uso dois agentes: rc=$RC"
SAIDA=$(bash "$SCRIPT" "a=$REL" --classificar ls 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok "uso: --classificar com agente" || erro "uso classificar+agente: rc=$RC"
SAIDA=$(bash "$SCRIPT" "a=$REL" --log "$LOG" --intervalo-s 0 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok "uso: intervalo 0" || erro "uso intervalo 0: rc=$RC"

echo
if [ "$falhas" -eq 0 ]; then echo "vigia-agy.test.sh: tudo ok"; exit 0; fi
echo "vigia-agy.test.sh: $falhas falha(s)"; exit 1
