#!/bin/bash
# Testa espera-argocd-sync.sh com um `kubectl` falso no PATH (nada toca um cluster).
# Uso: bash tests/espera-argocd-sync.test.sh   (também: zsh -c 'bash tests/espera-argocd-sync.test.sh')
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$AQUI/../espera-argocd-sync.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/espera-argocd-sync.XXXXXX")"
trap 'rm -r "$TMP/bin" "$TMP/f" 2>/dev/null || true; rm -f "$TMP/saida" "$TMP/args"; rmdir "$TMP" 2>/dev/null || true' EXIT
mkdir -p "$TMP/bin" "$TMP/f"

# kubectl falso: devolve $FAKE/app.json; registra os argumentos em $FAKE/../args.
cat > "$TMP/bin/kubectl" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE/../args"
[ -e "$FAKE/app.erro" ] && { echo "Error from server (NotFound)" >&2; exit 1; }
cat "$FAKE/app.json"
FAKE
chmod +x "$TMP/bin/kubectl"

falhas=0
caso() { # nome saida_esperada trecho_da_ultima_linha [args...]
  local nome="$1" esperado="$2" trecho="$3"; shift 3
  local codigo=0
  PATH="$TMP/bin:$PATH" FAKE="$TMP/f" INTERVALO=1 CARENCIA_DEGRADED=2 \
    bash "$SCRIPT" "$@" >"$TMP/saida" 2>&1 || codigo=$?
  local ultima; ultima=$(tail -n 1 "$TMP/saida")
  if [ "$codigo" = "$esperado" ] && [[ "$ultima" == *"$trecho"* ]]; then
    echo "ok   $nome (saída $codigo)"
  else
    echo "FALHA $nome: saída $codigo (esperado $esperado), última linha: $ultima"; cat "$TMP/saida"
    falhas=$((falhas + 1))
  fi
}
app() { printf '%s' "$1" > "$TMP/f/app.json"; }
APP_OK='{"status":{"sync":{"status":"Synced","revision":"abc1234def5678"},"health":{"status":"Healthy"}}}'
BASE=(--context eks-teste --app portal-prod)

app "$APP_OK"
caso verde-na-revisao 0 "sinal ok sync Synced saude Healthy" "${BASE[@]}" --revisao abc1234 --limite-s 5
caso verde-sem-revisao 0 "sinal ok" "${BASE[@]}" --limite-s 5
caso revisao-completa 0 "sinal ok" "${BASE[@]}" --revisao abc1234def5678 --limite-s 5

# kubectl recebeu contexto e namespace como argumentos separados
if grep -q -- '--context eks-teste -n argocd get application.argoproj.io portal-prod -o json' "$TMP/args"; then
  echo "ok   argumentos do kubectl"
else
  echo "FALHA argumentos do kubectl: $(head -1 "$TMP/args")"; falhas=$((falhas + 1))
fi

# 2: Synced+Healthy, mas em outra revisão, até o limite
caso outra-revisao 2 "sinal revisao-diferente" "${BASE[@]}" --revisao 9999999 --limite-s 2

# 1: Degraded além da carência
app '{"status":{"sync":{"status":"Synced","revision":"abc1234def5678"},"health":{"status":"Degraded"}}}'
caso degraded 1 "sinal degradado sync Synced saude Degraded" "${BASE[@]}" --revisao abc1234 --limite-s 30

# 1: operação de sync falhou
app '{"status":{"sync":{"status":"OutOfSync","revision":"abc1234def5678"},"health":{"status":"Progressing"},"operationState":{"phase":"Failed","syncResult":{"revision":"abc1234def5678"}}}}'
caso operacao-falhou 1 "sinal degradado" "${BASE[@]}" --revisao abc1234 --limite-s 30

# 3: OutOfSync/Progressing até o limite
app '{"status":{"sync":{"status":"OutOfSync","revision":"abc1234def5678"},"health":{"status":"Progressing"}}}'
caso limite 3 "sinal limite sync OutOfSync saude Progressing" "${BASE[@]}" --revisao abc1234 --limite-s 2

# campos ausentes (app recém-criado): sem `jq: error`, cai no limite
app '{}'
caso campos-ausentes 3 "sinal limite sync Desconhecido saude Desconhecido" "${BASE[@]}" --limite-s 2
if grep -q 'jq: error' "$TMP/saida"; then echo "FALHA campos-ausentes: erro do jq"; falhas=$((falhas + 1)); fi

# várias fontes: revisão em status.sync.revisions
app '{"status":{"sync":{"status":"Synced","revisions":["1111111aaa","abc1234def5678"]},"health":{"status":"Healthy"}}}'
caso multiplas-fontes 0 "sinal ok" "${BASE[@]}" --revisao abc1234 --limite-s 5

# 64: app ilegível 5 vezes
: > "$TMP/f/app.erro"
caso app-ilegivel 64 "5 vezes seguidas" "${BASE[@]}" --limite-s 30
rm -f "$TMP/f/app.erro"

# 64: uso
caso sem-app 64 "uso:" --context x
caso limite-invalido 64 "uso:" "${BASE[@]}" --limite-s abc
caso revisao-invalida 64 "SHA hexadecimal" "${BASE[@]}" --revisao 'main'
caso flag-desconhecida 64 "uso:" "${BASE[@]}" --foo

# 64: falta jq no PATH
codigo=0
PATH="$TMP/bin" /bin/bash "$SCRIPT" "${BASE[@]}" >"$TMP/saida" 2>&1 || codigo=$?
if [ "$codigo" = 64 ] && grep -q "falta .jq." "$TMP/saida"; then echo "ok   sem-jq (saída 64)"; else echo "FALHA sem-jq: $codigo"; cat "$TMP/saida"; falhas=$((falhas + 1)); fi

if [ "$falhas" = 0 ]; then echo "todos os casos passaram"; else echo "$falhas caso(s) falharam"; exit 1; fi
