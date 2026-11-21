#!/bin/bash
# Testa os códigos de saída de uso/pré-requisito (64) do esperar-rollout.sh com um
# `kubectl` falso no PATH: nada toca um cluster. Uso: tests/esperar-rollout.test.sh
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$AQUI/../esperar-rollout.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/esperar-rollout.XXXXXX")"
# shellcheck disable=SC2064  # expande agora de propósito: o caminho validado fica fixo no trap
case "$TMP" in
  */esperar-rollout.??????) trap "rm -rf -- '$TMP'" EXIT ;;
  *) echo "diretório temporário fora do padrão do mktemp: $TMP" >&2; exit 1 ;;
esac
mkdir -p "$TMP/bin" "$TMP/vazio"

# kubectl falso: `get deployment` falha (Deployment inexistente); `rollout status` e o resto, não.
cat > "$TMP/bin/kubectl" <<'FAKE'
#!/bin/bash
exit 1
FAKE
chmod +x "$TMP/bin/kubectl"

falhas=0
caso() { # nome saida_esperada trecho_da_saida path_extra [args...]
  local nome="$1" esperado="$2" trecho="$3" caminho="$4"; shift 4
  local codigo=0
  PATH="$caminho" "$BASH" "$SCRIPT" "$@" >"$TMP/saida" 2>&1 || codigo=$?
  if [ "$codigo" = "$esperado" ] && grep -qF -- "$trecho" "$TMP/saida"; then
    echo "ok   $nome (saída $codigo)"
  else
    echo "FALHA $nome: saída $codigo (esperado $esperado)"; cat "$TMP/saida"
    falhas=$((falhas + 1))
  fi
}

COM_FAKE="$TMP/bin:$PATH"
BASE=(--context c --namespace n --deployment d)

caso "sem argumentos" 64 "uso:" "$COM_FAKE"
caso "opção desconhecida" 64 "uso:" "$COM_FAKE" --foo
caso "falta --deployment" 64 "uso:" "$COM_FAKE" --context c --namespace n --imagem x
caso "sem expectativa" 64 "sem expectativa" "$COM_FAKE" "${BASE[@]}"
caso "limite não numérico" 64 "uso:" "$COM_FAKE" "${BASE[@]}" --imagem x --limite abc
caso "sem kubectl nem jq no PATH" 64 "falta" "$TMP/vazio" "${BASE[@]}" --imagem x
caso "deployment inexistente" 64 "não encontrado" "$COM_FAKE" "${BASE[@]}" --imagem x

[ "$falhas" = 0 ] || { echo "$falhas caso(s) falharam"; exit 1; }
echo "todos os casos passaram"
