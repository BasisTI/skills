#!/bin/bash
# Teste do agy-gerar-papeis.sh com agentes e destino falsos num diretório temporário.
# Nunca toca o ~/.gemini real: toda chamada leva --agentes e --destino.
# Uso: bash skills/orquestrador/scripts/tests/agy-gerar-papeis.test.sh
# Sai 0 se todos os casos passarem; 1 com a lista dos que falharam.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$AQUI/../agy-gerar-papeis.sh"
RAIZ="$(mktemp -d "${TMPDIR:-/tmp}/agy-gerar-test.XXXXXX")"
[ -n "$RAIZ" ] && [ -d "$RAIZ" ] || { echo 'mktemp falhou' >&2; exit 2; }
trap 'case "$RAIZ" in */agy-gerar-test.*) rm -rf "$RAIZ" ;; esac' EXIT
AG="$RAIZ/agents"; DEST="$RAIZ/destino"
mkdir -p "$AG" "$DEST"

falhas=0
confere() { # confere <descrição> <0 = ok>
  if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; falhas=$((falhas+1)); fi
}
roda() { rc=0; bash "$SCRIPT" --agentes "$AG" --destino "$DEST" "$@" >"$RAIZ/saida" 2>&1 || rc=$?; }

cat >"$AG/alfa.md" <<'EOF'
---
name: alfa
description: >-
  Papel de teste com descrição
  em duas linhas.
mode: subagent
model: opus
color: red
tools: Read, Bash
---

# Alfa

Corpo com `crase`, $variavel e --- no meio.

---

Fim.
EOF
cat >"$AG/beta.md" <<'EOF'
---
name: beta
description: Papel simples.
---
Corpo beta.
EOF

# 1. gera os dois papéis
roda
confere "gera todos os papéis (rc 0)" "$([ $rc = 0 ] && echo 0 || echo 1)"
A="$DEST/alfa/agent.md"
confere "frontmatter tem name e description" "$(grep -qx 'name: alfa' "$A" && grep -qx 'description: >-' "$A" && grep -qx '  em duas linhas.' "$A"; echo $?)"
confere "tem subagent, mainAgent e tools do agy" "$(grep -qx 'subagent: true' "$A" && grep -qx 'mainAgent: false' "$A" && grep -qx 'tools: \[read_file, edit_file, write_file, run_command, manage_task, search_web\]' "$A"; echo $?)"
confere "descarta mode, model, color e a tools do Claude Code" "$(! grep -qE '^(mode|model|color):|tools: Read' "$A"; echo $?)"
confere "tem a marca de gerado" "$(grep -qF '<!-- gerado por agy-gerar-papeis.sh a partir de alfa.md' "$A"; echo $?)"
corpo_orig="$(awk 'c>=2{print} /^---$/ && c<2{c++}' "$AG/alfa.md")"
corpo_novo="$(sed '1,/^<!-- gerado por/d' "$A")"
confere "corpo preservado byte a byte (com --- no meio)" "$([ "$corpo_orig" = "$corpo_novo" ]; echo $?)"
confere "o canônico não foi alterado" "$(grep -qx 'mode: subagent' "$AG/alfa.md"; echo $?)"
confere "beta (description numa linha) gerado" "$(grep -qx 'description: Papel simples.' "$DEST/beta/agent.md"; echo $?)"

# 2. idempotente
cp "$A" "$RAIZ/antes"
roda
confere "segunda rodada: rc 0 e 'igual'" "$([ $rc = 0 ] && grep -q '^igual:' "$RAIZ/saida"; echo $?)"
confere "segunda rodada não muda o arquivo" "$(cmp -s "$A" "$RAIZ/antes"; echo $?)"

# 3. canônico mudou: o gerado acompanha
printf '\nLinha nova.\n' >>"$AG/alfa.md"
roda alfa
confere "canônico mudou: regenera" "$([ $rc = 0 ] && grep -qx 'Linha nova.' "$A"; echo $?)"

# 4. só o papel pedido
rm -rf "$DEST"; mkdir -p "$DEST"
roda beta
confere "papel nomeado gera só ele" "$([ -f "$DEST/beta/agent.md" ] && [ ! -e "$DEST/alfa" ]; echo $?)"

# 5. arquivo próprio da pessoa é recusado
mkdir -p "$DEST/alfa"; printf 'meu arquivo\n' >"$DEST/alfa/agent.md"
roda
confere "arquivo sem a marca: rc 3" "$([ $rc = 3 ]; echo $?)"
confere "arquivo sem a marca: intacto" "$([ "$(cat "$DEST/alfa/agent.md")" = 'meu arquivo' ]; echo $?)"
confere "recusa de um não impede os outros" "$([ -f "$DEST/beta/agent.md" ]; echo $?)"

# 5b. a recusa não vaza para uma segunda rodada limpa
rm -f "$DEST/alfa/agent.md"

# 6. link simbólico: recusado sem a opção, trocado com ela, sem tocar o alvo do link
printf 'alvo do link\n' >"$RAIZ/canonico-link.md"
ln -s "$RAIZ/canonico-link.md" "$DEST/alfa/agent.md"
roda alfa
confere "link sem --substituir-link: rc 3" "$([ $rc = 3 ] && [ -L "$DEST/alfa/agent.md" ]; echo $?)"
roda alfa --substituir-link
confere "--substituir-link troca o link por arquivo" "$([ $rc = 0 ] && [ ! -L "$DEST/alfa/agent.md" ] && grep -qx 'subagent: true' "$DEST/alfa/agent.md"; echo $?)"
confere "o alvo do link ficou intacto" "$([ "$(cat "$RAIZ/canonico-link.md")" = 'alvo do link' ]; echo $?)"

# 7. erros
roda inexistente
confere "papel inexistente: rc 1" "$([ $rc = 1 ]; echo $?)"
printf 'sem frontmatter\n' >"$AG/ruim.md"
roda ruim
confere "sem frontmatter: rc 1" "$([ $rc = 1 ]; echo $?)"
printf -- '---\nname: x\n---\ncorpo\n' >"$AG/semdesc.md"
roda semdesc
confere "sem description: rc 1 e nada gravado" "$([ $rc = 1 ] && [ ! -e "$DEST/semdesc/agent.md" ]; echo $?)"
roda ../fora
confere "nome com barra: rc 2" "$([ $rc = 2 ]; echo $?)"
rc=0; bash "$SCRIPT" --agentes "$RAIZ/nao-existe" --destino "$DEST" >/dev/null 2>&1 || rc=$?
confere "pasta de agentes inexistente: rc 1" "$([ $rc = 1 ]; echo $?)"
rc=0; bash "$SCRIPT" --bobagem >/dev/null 2>&1 || rc=$?
confere "opção desconhecida: rc 2" "$([ $rc = 2 ]; echo $?)"

# 8. sem sobra de temporário
confere "sem .agent.md.* sobrando" "$([ -z "$(find "$DEST" -name '.agent.md.*')" ]; echo $?)"

# 9. os papéis reais do repositório geram
REAL="$AQUI/../../../../agents"
rc=0; bash "$SCRIPT" --agentes "$REAL" --destino "$RAIZ/real" >/dev/null 2>&1 || rc=$?
confere "papéis reais (qa-adversarial, planejador) geram com tools" "$([ $rc = 0 ] && grep -qx 'subagent: true' "$RAIZ/real/planejador/agent.md" && grep -q '^tools: ' "$RAIZ/real/qa-adversarial/agent.md"; echo $?)"

if [ "$falhas" -eq 0 ]; then echo "todos os casos passaram"; exit 0; fi
echo "$falhas caso(s) falharam" >&2; exit 1
