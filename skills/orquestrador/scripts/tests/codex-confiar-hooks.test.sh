#!/bin/bash
# Teste do codex-confiar-hooks.sh com repos git e config.toml falsos num diretório
# temporário. Nunca toca o ~/.codex real: toda chamada leva --config e CODEX_HOME
# apontando para o temporário.
# Uso: bash scripts/tests/codex-confiar-hooks.test.sh   (roda sob bash; chamá-lo de zsh também funciona)
set -uo pipefail

AQUI=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$AQUI/../codex-confiar-hooks.sh"
RAIZ=$(mktemp -d "${TMPDIR:-/tmp}/codex-confiar-test.XXXXXX")
[ -n "$RAIZ" ] && [ -d "$RAIZ" ] || { echo 'mktemp falhou' >&2; exit 2; }
trap 'case "$RAIZ" in */codex-confiar-test.*) rm -rf "$RAIZ" ;; esac' EXIT  # só o mktemp deste teste
export CODEX_HOME="$RAIZ/codex-home" HOME="$RAIZ/home"
mkdir -p "$CODEX_HOME" "$HOME"
CFG="$CODEX_HOME/config.toml"

falhas=0
ERRO() { echo "FAIL $1"; falhas=$((falhas+1)); }
OK() { echo "ok   $1"; }
confere() { # confere <descrição> <condição: 0 = ok>
  if [ "$2" = 0 ]; then OK "$1"; else ERRO "$1"; fi
}

H1='sha256:f217fbcf8ebe41da3413e01f17f17afcb1cae89c2b995feccd9ebbc4b2297fb6'
H2='sha256:6eb46df3fb741be24b7d49bd375f6a1b24257fa297b6f0f886c1e34a32ef4dfb'
HOOKS='{"hooks":{"PostToolUse":[],"Stop":[]}}'

git config --global user.email t@t; git config --global user.name t
git config --global init.defaultBranch main
CK="$RAIZ/repo"
mkdir -p "$CK/.codex"; printf '%s\n' "$HOOKS" >"$CK/.codex/hooks.json"
git -C "$CK" init -q; git -C "$CK" add -A; git -C "$CK" commit -qm init
WT="$RAIZ/repo.TG-1"; git -C "$CK" worktree add -q -b TG-1 "$WT"
CKP=$(cd "$CK" && pwd -P); WTP=$(cd "$WT" && pwd -P)

config_base() {
  cat >"$CFG" <<CFGEOF
model = "gpt-6"

[mcp_servers.segredo]
command = "nao-imprimir"
env = { TOKEN = "xyz" }

[hooks.state."$CKP/.codex/hooks.json:post_tool_use:0:0"]
trusted_hash = "$H1"

[hooks.state."$CKP/.codex/hooks.json:stop:0:0"]
trusted_hash = "$H2"

[projects."/x/y"]
trust_level = "trusted"
CFGEOF
}
rodar() { SAIDA=$("$SCRIPT" "$@" 2>&1); RC=$?; }
conta() { grep -c "^\[hooks\.state\.\"$1" "$CFG"; }

# --- hooks iguais: entradas copiadas ------------------------------------------
config_base; cp "$CFG" "$RAIZ/orig.toml"
rodar "$WT" --config "$CFG"
[ "$RC" = 0 ] && [ "$(conta "$WTP")" = 2 ] && grep -qF "trusted_hash = \"$H1\"" "$CFG"; confere "hooks iguais copiam as 2 entradas (saída 0)" $?
[[ "$SAIDA" == *"confiado: 2 entrada"* ]]; confere "a saída diz o que fez" $?
# o que havia antes continua igual, byte a byte, como prefixo
cmp -s "$RAIZ/orig.toml" <(head -c "$(wc -c <"$RAIZ/orig.toml")" "$CFG"); confere "as demais seções ficam byte a byte" $?
grep -qF "$H2" <<<"$(grep -A1 "$WTP/.codex/hooks.json:stop:0:0" "$CFG")"; confere "cada entrada leva o seu trusted_hash" $?
[ "$(ls "$CODEX_HOME" | grep -c '^config.toml.bak-')" = 1 ]; confere "um backup do config antes da escrita" $?
cmp -s "$RAIZ/orig.toml" "$CODEX_HOME"/config.toml.bak-*; confere "o backup é o config original" $?
[[ "$SAIDA" != *nao-imprimir* && "$SAIDA" != *xyz* ]]; confere "a saída não vaza outras seções" $?

# --- segunda execução não duplica ---------------------------------------------
cp "$CFG" "$RAIZ/depois1.toml"
rodar "$WT" --config "$CFG"
cmp -s "$RAIZ/depois1.toml" "$CFG" && [ "$RC" = 0 ] && [[ "$SAIDA" == *"já confiado"* ]]; confere "segunda execução não muda nada nem duplica" $?
[ "$(ls "$CODEX_HOME" | grep -c '^config.toml.bak-')" = 1 ]; confere "sem escrita, sem backup novo" $?

# --- hooks diferentes: nada gravado -------------------------------------------
config_base; cp "$CFG" "$RAIZ/orig.toml"
printf '%s\n' '{"hooks":{"Stop":[]}}' >"$WT/.codex/hooks.json"
rodar "$WT" --config "$CFG"
[ "$RC" = 3 ] && cmp -s "$RAIZ/orig.toml" "$CFG" && [[ "$SAIDA" == *"difere"* ]]; confere "hooks diferentes: saída 3, nada gravado, explica por quê" $?
printf '%s\n' "$HOOKS" >"$WT/.codex/hooks.json"

# --- checkout sem entradas ----------------------------------------------------
printf 'model = "gpt-6"\n' >"$CFG"; cp "$CFG" "$RAIZ/orig.toml"
rodar "$WT" --config "$CFG"
[ "$RC" = 3 ] && cmp -s "$RAIZ/orig.toml" "$CFG" && [[ "$SAIDA" == *"não tem entradas"* ]]; confere "checkout sem entradas: saída 3, nada gravado" $?
config_base
printf '[hooks.state."/outro/repo/.codex/hooks.json:stop:0:0"]\ntrusted_hash = "%s"\n' "$H1" >"$CFG"; cp "$CFG" "$RAIZ/orig.toml"
rodar "$WT" --config "$CFG"
[ "$RC" = 3 ] && cmp -s "$RAIZ/orig.toml" "$CFG"; confere "só entradas de outro repo: nada copiado" $?
rodar "$WT" --config "$RAIZ/nao-existe.toml"
[ "$RC" = 3 ] && [ ! -e "$RAIZ/nao-existe.toml" ]; confere "config inexistente: saída 3 e não cria o arquivo" $?

# --- sem hooks.json no worktree -----------------------------------------------
SEM="$RAIZ/sem-hooks"; mkdir -p "$SEM"; config_base; cp "$CFG" "$RAIZ/orig.toml"
rodar "$SEM" --checkout "$CK" --config "$CFG"
[ "$RC" = 0 ] && cmp -s "$RAIZ/orig.toml" "$CFG" && [[ "$SAIDA" == *"nada a fazer"* ]]; confere "worktree sem .codex/hooks.json: sai 0 sem escrever" $?

# --- --checkout explícito e config padrão via CODEX_HOME ----------------------
config_base; cp "$CFG" "$RAIZ/orig.toml"
CP="$RAIZ/copia"; mkdir -p "$CP/.codex"; printf '%s\n' "$HOOKS" >"$CP/.codex/hooks.json"
rodar "$CP" --checkout "$CK"
CPP=$(cd "$CP" && pwd -P)
[ "$RC" = 0 ] && [ "$(conta "$CPP")" = 2 ]; confere "--checkout explícito e config padrão (CODEX_HOME)" $?

# --- config sem newline final -------------------------------------------------
config_base; printf '\nfim = "sem-quebra"' >>"$CFG"
rodar "$WT" --config "$CFG"
[ "$RC" = 0 ] && [ "$(conta "$WTP")" = 2 ] && grep -qx 'fim = "sem-quebra"' "$CFG"; confere "config sem newline final: tabela nova em linha própria" $?

# --- --podar ------------------------------------------------------------------
config_base
VIVO="$RAIZ/vivo"; mkdir -p "$VIVO/.codex"; : >"$VIVO/.codex/hooks.json"
{ printf '\n[hooks.state."%s/.codex/hooks.json:stop:0:0"]\ntrusted_hash = "%s"\n' "$RAIZ/morto" "$H1"
  printf '\n[hooks.state."%s/.codex/hooks.json:post_tool_use:0:0"]\ntrusted_hash = "%s"\n' "$RAIZ/morto" "$H2"
  printf '\n[hooks.state."%s/.codex/hooks.json:stop:0:0"]\ntrusted_hash = "%s"\n' "$VIVO" "$H1"
  printf '\n[depois]\nx = 1\n'; } >>"$CFG"
rodar --podar --config "$CFG"
[ "$RC" = 0 ] && [ "$(conta "$RAIZ/morto")" = 0 ] && [ "$(conta "$VIVO")" = 1 ] && [ "$(conta "$CKP")" = 2 ]; confere "--podar remove só as de caminho inexistente" $?
grep -qx 'model = "gpt-6"' "$CFG" && grep -qx 'command = "nao-imprimir"' "$CFG" && grep -qx 'trust_level = "trusted"' "$CFG" && grep -qx 'x = 1' "$CFG"; confere "--podar preserva as demais seções" $?
# o resultado é o config sem o bloco morto, byte a byte
config_base
printf '\n[hooks.state."%s/.codex/hooks.json:stop:0:0"]\ntrusted_hash = "%s"\n\n[depois]\nx = 1\n' "$VIVO" "$H1" >>"$CFG"
cp "$CFG" "$RAIZ/esperado.toml"
config_base
{ printf '\n[hooks.state."%s/.codex/hooks.json:stop:0:0"]\ntrusted_hash = "%s"\n' "$RAIZ/morto" "$H1"
  printf '\n[hooks.state."%s/.codex/hooks.json:stop:0:0"]\ntrusted_hash = "%s"\n' "$VIVO" "$H1"
  printf '\n[depois]\nx = 1\n'; } >>"$CFG"
rodar --podar --config "$CFG"
cmp -s "$RAIZ/esperado.toml" "$CFG"; confere "--podar: resultado idêntico ao config sem o bloco morto" $?
cp "$CFG" "$RAIZ/antes.toml"; rodar --podar --config "$CFG"
cmp -s "$RAIZ/antes.toml" "$CFG" && [ "$RC" = 0 ] && [[ "$SAIDA" == *"nenhuma entrada"* ]]; confere "--podar sem o que podar não escreve" $?
rodar "$WT" --podar --config "$CFG"
[ "$RC" = 0 ]; confere "worktree e --podar juntos" $?

# --- uso ----------------------------------------------------------------------
rodar; [ "$RC" = 2 ]; confere "sem argumentos: saída 2" $?
rodar --zzz; [ "$RC" = 2 ]; confere "opção desconhecida: saída 2" $?
rodar "$WT" --config; [ "$RC" = 2 ]; confere "--config sem valor: saída 2" $?
rodar "$WT" outro; [ "$RC" = 2 ]; confere "argumento a mais: saída 2" $?
rodar --help; [ "$RC" = 0 ] && [[ "$SAIDA" == *uso:* ]]; confere "--help: saída 0" $?
[ "$(head -1 "$SCRIPT")" = '#!/bin/bash' ] && [ -x "$SCRIPT" ]; confere "shebang #!/bin/bash e executável" $?

echo
if [ "$falhas" -eq 0 ]; then echo "todos os casos passaram"; else echo "$falhas caso(s) falharam"; exit 1; fi
