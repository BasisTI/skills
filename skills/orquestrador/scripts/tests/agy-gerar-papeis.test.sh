#!/bin/bash
# Teste do agy-gerar-papeis.sh com agentes e destino falsos num diretório temporário.
# Nunca toca o ~/.gemini real: toda chamada leva --agentes e --destino.
# Uso: bash skills/orquestrador/scripts/tests/agy-gerar-papeis.test.sh
# Sai 0 se todos os casos passarem; 1 com a lista dos que falharam.
#
# Cada caso existe para matar um defeito concreto do script (anotado no comentário):
# se o script voltar a ter o defeito, o caso falha.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$AQUI/../agy-gerar-papeis.sh"
RAIZ="$(mktemp -d "${TMPDIR:-/tmp}/agy-gerar-test.XXXXXX")"
[ -n "$RAIZ" ] && [ -d "$RAIZ" ] || { echo 'mktemp falhou' >&2; exit 2; }
trap 'case "$RAIZ" in */agy-gerar-test.*) rm -rf "$RAIZ" ;; esac' EXIT
AG="$RAIZ/agents"; DEST="$RAIZ/destino"
export TMPDIR="$RAIZ/tmp"; mkdir -p "$AG" "$DEST" "$TMPDIR"

falhas=0
confere() { # confere <descrição> <0 = ok>
  if [ "$2" = 0 ]; then echo "ok   $1"; else echo "FAIL $1"; falhas=$((falhas+1)); fi
}
roda() { rc=0; bash "$SCRIPT" --agentes "$AG" --destino "$DEST" "$@" >"$RAIZ/saida" 2>"$RAIZ/erro" || rc=$?; }
zera() { rm -rf "$DEST"; mkdir -p "$DEST"; }
tem() { grep -qxF -- "$2" "$1"; }                 # linha inteira
# corpo gerado = tudo depois da linha da marca; corpo canônico = depois do 2º `---`
corpo_gerado() { local n; n=$(grep -n '^<!-- gerado por' "$1" | head -n1 | cut -d: -f1); tail -n +$((n+1)) "$1"; }
corpo_canonico() { local n; n=$(grep -n '^---$' "$1" | sed -n 2p | cut -d: -f1); tail -n +$((n+1)) "$1"; }
mesmo_corpo() { # mesmo_corpo <canônico> <gerado>: cmp de arquivos, byte a byte
  corpo_canonico "$1" >"$RAIZ/c1"; corpo_gerado "$2" >"$RAIZ/c2"; cmp -s "$RAIZ/c1" "$RAIZ/c2"
}
TODAS='tools: [read_file, edit_file, write_file, run_command, manage_task, search_web]'

cat >"$AG/alfa.md" <<'X'
---
name: alfa
description: >-
  Papel de teste com descrição
  em duas linhas.
mode: subagent
model: opus
color: red
---

# Alfa

Corpo com `crase`, $variavel e --- no meio.

---

Fim.


X
cat >"$AG/beta.md" <<'X'
---
name: beta
description: Papel simples.
---
Corpo beta.
X

# ---------------------------------------------------------------- geração básica
roda
confere "gera todos os papéis (rc 0)" "$([ $rc = 0 ]; echo $?)"
A="$DEST/alfa/agent.md"
# defeito (achado nesta rodada): o gerador perdia o `---` de abertura e o agy não via frontmatter
confere "frontmatter abre com --- na 1ª linha e fecha com --- logo antes da marca" "$([ "$(head -n1 "$A")" = --- ] && [ "$(grep -n '^<!-- gerado por' "$A" | cut -d: -f1)" = "$(( $(grep -n '^---$' "$A" | sed -n 2p | cut -d: -f1) + 1 ))" ]; echo $?)"
confere "name e description (dobrada) copiados" "$(tem "$A" 'name: alfa' && tem "$A" 'description: >-' && tem "$A" '  em duas linhas.'; echo $?)"
confere "subagent, mainAgent e tools completo (canônico sem tools)" "$(tem "$A" 'subagent: true' && tem "$A" 'mainAgent: false' && tem "$A" "$TODAS"; echo $?)"
confere "descarta mode, model e color" "$(! grep -qE '^(mode|model|color):' "$A"; echo $?)"
confere "marca de gerado" "$(grep -qF '<!-- gerado por agy-gerar-papeis.sh a partir de alfa.md' "$A"; echo $?)"
# defeito: comparar via $(...) esconde newline final a mais ou a menos; aqui é cmp em arquivo
confere "corpo idêntico byte a byte (cmp em arquivo; --- no meio, linhas em branco no fim)" "$(mesmo_corpo "$AG/alfa.md" "$A"; echo $?)"
confere "o canônico não foi alterado" "$(tem "$AG/alfa.md" 'mode: subagent'; echo $?)"
confere "beta (description numa linha)" "$(tem "$DEST/beta/agent.md" 'description: Papel simples.'; echo $?)"

# ---------------------------------------------------------------- idempotência
# defeito: regravar sempre. Fixa mtime antigo e inode; a 2ª rodada não pode mexer.
touch -d '2001-01-01 00:00:00' "$A"
antes="$(stat -c '%i %Y' "$A")"
roda
depois="$(stat -c '%i %Y' "$A")"
confere "2ª rodada: rc 0 e 'igual'" "$([ $rc = 0 ] && grep -q '^igual:' "$RAIZ/saida"; echo $?)"
confere "2ª rodada: mesmo inode e mesmo mtime (não regravou)" "$([ "$antes" = "$depois" ]; echo $?)"

printf 'Linha nova.\n' >>"$AG/alfa.md"
roda alfa
confere "canônico mudou: regenera" "$([ $rc = 0 ] && tem "$A" 'Linha nova.'; echo $?)"

# ---------------------------------------------------------------- só o papel pedido
zera; roda beta
confere "papel nomeado gera só ele" "$([ -f "$DEST/beta/agent.md" ] && [ ! -e "$DEST/alfa" ]; echo $?)"

# ---------------------------------------------------------------- marca: só na 1ª linha depois do frontmatter
zera; mkdir -p "$DEST/alfa"; printf 'meu arquivo\n' >"$DEST/alfa/agent.md"
roda
confere "arquivo sem frontmatter nem marca: rc 3 e intacto" "$([ $rc = 3 ] && [ "$(cat "$DEST/alfa/agent.md")" = 'meu arquivo' ]; echo $?)"
confere "recusa de um não impede os outros" "$([ -f "$DEST/beta/agent.md" ]; echo $?)"
# defeito: grep da marca no arquivo inteiro sobrescrevia arquivo da pessoa que a citava no meio
printf -- '---\nname: alfa\n---\nmeu texto\n<!-- gerado por agy-gerar-papeis.sh a partir de alfa.md; copiei -->\n' >"$DEST/alfa/agent.md"
cp "$DEST/alfa/agent.md" "$RAIZ/pessoa"
roda alfa
confere "marca no MEIO do corpo: rc 3 e intacto" "$([ $rc = 3 ] && cmp -s "$DEST/alfa/agent.md" "$RAIZ/pessoa"; echo $?)"
printf -- '---\nname: alfa\n---\nlinha 1\n<!-- gerado por agy-gerar-papeis.sh a partir de alfa.md; x -->\n' >"$DEST/alfa/agent.md"
cp "$DEST/alfa/agent.md" "$RAIZ/pessoa"
roda alfa
confere "marca na 2ª linha depois do frontmatter: rc 3 e intacto" "$([ $rc = 3 ] && cmp -s "$DEST/alfa/agent.md" "$RAIZ/pessoa"; echo $?)"
# 5b: depois de apagar o arquivo da pessoa, a rodada limpa gera
rm -f "$DEST/alfa/agent.md"
roda alfa
confere "5b: rodada limpa depois da recusa gera o arquivo (rc 0)" "$([ $rc = 0 ] && tem "$DEST/alfa/agent.md" 'subagent: true'; echo $?)"
# arquivo gerado com a marca é regravado
printf 'x\n' >>"$AG/beta.md"; roda beta; roda alfa beta
confere "arquivo gerado (com a marca) é regravado quando o canônico muda" "$([ $rc = 0 ] && tem "$DEST/beta/agent.md" 'x'; echo $?)"

# ---------------------------------------------------------------- links
zera; mkdir -p "$DEST/alfa"
printf 'alvo do link\n' >"$RAIZ/canonico-link.md"
ln -s "$RAIZ/canonico-link.md" "$DEST/alfa/agent.md"
roda alfa
confere "agent.md link sem --substituir-link: rc 3 e link mantido" "$([ $rc = 3 ] && [ -L "$DEST/alfa/agent.md" ]; echo $?)"
roda alfa --substituir-link
confere "--substituir-link troca o link por arquivo" "$([ $rc = 0 ] && [ ! -L "$DEST/alfa/agent.md" ] && tem "$DEST/alfa/agent.md" 'subagent: true'; echo $?)"
confere "o alvo do link ficou intacto" "$([ "$(cat "$RAIZ/canonico-link.md")" = 'alvo do link' ]; echo $?)"
# defeito: mv sem -T move o arquivo PARA DENTRO do diretório alvo do link
zera; mkdir -p "$DEST/alfa" "$RAIZ/dirlink"
ln -s "$RAIZ/dirlink" "$DEST/alfa/agent.md"
roda alfa --substituir-link
confere "agent.md link para DIRETÓRIO: trocado, nada cai dentro do diretório" "$([ $rc = 0 ] && [ -f "$DEST/alfa/agent.md" ] && [ ! -L "$DEST/alfa/agent.md" ] && [ -z "$(ls -A "$RAIZ/dirlink")" ]; echo $?)"
# defeito: diretório do papel como link gravava fora do destino
zera; mkdir -p "$RAIZ/fora"; ln -s "$RAIZ/fora" "$DEST/alfa"
roda alfa beta --substituir-link
confere "diretório do papel é link: rc 3, nada gravado fora, os outros gerados" "$([ $rc = 3 ] && [ -z "$(ls -A "$RAIZ/fora")" ] && [ -f "$DEST/beta/agent.md" ]; echo $?)"
# defeito: --destino link
ln -sfn "$DEST" "$RAIZ/destino-link"
rc=0; bash "$SCRIPT" --agentes "$AG" --destino "$RAIZ/destino-link" >/dev/null 2>&1 || rc=$?
confere "--destino é link: rc 3" "$([ $rc = 3 ]; echo $?)"

# ---------------------------------------------------------------- nomes e efeito parcial
# defeito: nome com `.` aceito (ex. `.x`, `a.b`, `..`)
for n in .x a.b .. -x; do
  zera; roda alfa -- "$n" 2>/dev/null; roda alfa "$n"
  confere "nome '$n': não gera nada" "$([ -z "$(ls -A "$DEST")" ]; echo $?)"
done
zera; roda alfa .x
confere "nome '.x': rc 2" "$([ $rc = 2 ]; echo $?)"
# defeito: efeito parcial. Um nome ruim em qualquer posição aborta tudo antes de gravar.
zera; roda alfa zzz beta
confere "alfa zzz beta: rc 1 e NADA gravado" "$([ $rc = 1 ] && [ -z "$(ls -A "$DEST")" ]; echo $?)"
zera; roda alfa .x
confere "alfa .x: rc 2 e NADA gravado" "$([ $rc = 2 ] && [ -z "$(ls -A "$DEST")" ]; echo $?)"
printf 'sem frontmatter\n' >"$AG/ruim.md"
zera; roda alfa ruim beta
confere "frontmatter ruim no meio da lista: rc 1 e NADA gravado" "$([ $rc = 1 ] && [ -z "$(ls -A "$DEST")" ]; echo $?)"

# ---------------------------------------------------------------- canônico inválido
: >"$AG/vazio.md"
zera; roda vazio
confere "canônico vazio: rc 1 e nada gravado" "$([ $rc = 1 ] && [ -z "$(ls -A "$DEST")" ]; echo $?)"
printf -- '---\nname: x\ndescription: d\n---\n' >"$AG/semcorpo.md"
zera; roda semcorpo
confere "só frontmatter, sem corpo: rc 1 e nada gravado" "$([ $rc = 1 ] && [ -z "$(ls -A "$DEST")" ]; echo $?)"
printf -- '---\nname: x\n---\ncorpo\n' >"$AG/semdesc.md"
zera; roda semdesc
confere "sem description: rc 1 e nada gravado" "$([ $rc = 1 ] && [ -z "$(ls -A "$DEST")" ]; echo $?)"
printf -- '---\nname: x\ndescription:\n---\ncorpo\n' >"$AG/descvazia.md"
zera; roda descvazia
confere "description vazia: rc 1 e nada gravado" "$([ $rc = 1 ] && [ -z "$(ls -A "$DEST")" ]; echo $?)"
printf -- '---\nname: x\ndescription: >-\n\nmode: subagent\n---\ncorpo\n' >"$AG/descdobradavazia.md"
zera; roda descdobradavazia
confere "description dobrada sem texto: rc 1" "$([ $rc = 1 ]; echo $?)"
printf -- '---\nname: x\n---\ncorpo\n' >"$AG/semnome.md"
roda semnome
confere "sem name: rc 1" "$([ $rc = 1 ]; echo $?)"
printf -- '---\r\nname: x\r\ndescription: d\r\n---\r\ncorpo\r\n' >"$AG/crlf.md"
roda crlf
confere "frontmatter CRLF: rc 1" "$([ $rc = 1 ]; echo $?)"
printf -- '---\nname: x\ndescription: d\ncorpo sem fechar\n' >"$AG/naofecha.md"
roda naofecha
confere "frontmatter não fechado: rc 1" "$([ $rc = 1 ]; echo $?)"

# ---------------------------------------------------------------- corpo sem newline final
printf -- '---\nname: sn\ndescription: d\n---\nsem newline final' >"$AG/sn.md"
zera; roda sn
confere "corpo sem newline final: preservado byte a byte (nada acrescentado)" "$([ $rc = 0 ] && mesmo_corpo "$AG/sn.md" "$DEST/sn/agent.md"; echo $?)"

# ---------------------------------------------------------------- tools restritivo do canônico
printf -- '---\nname: rs\ndescription: d\ntools: Read, Grep, Bash, WebFetch, Foo\n---\ncorpo\n' >"$AG/rs.md"
zera; roda rs
confere "tools 'Read, Grep, Bash, WebFetch, Foo' mapeado como a migrate-agent-settings" "$(tem "$DEST/rs/agent.md" 'tools: [read_file, run_command, manage_task, search_web]'; echo $?)"
confere "grant sem equivalente (Foo) avisado no stderr" "$(grep -q 'Foo' "$RAIZ/erro"; echo $?)"
confere "tools restritivo NÃO vira o conjunto completo" "$(! tem "$DEST/rs/agent.md" "$TODAS"; echo $?)"
printf -- '---\nname: rl\ndescription: d\ntools:\n  - Read\n  - Edit\n---\ncorpo\n' >"$AG/rl.md"
zera; roda rl
confere "tools em lista de blocos: read_file, edit_file" "$(tem "$DEST/rl/agent.md" 'tools: [read_file, edit_file]'; echo $?)"
printf -- '---\nname: rc\ndescription: d\ntools: [Write, "Edit"]\n---\ncorpo\n' >"$AG/rc.md"
zera; roda rc
confere "tools entre colchetes e aspas: edit_file, write_file" "$(tem "$DEST/rc/agent.md" 'tools: [edit_file, write_file]'; echo $?)"
printf -- '---\nname: rn\ndescription: d\ntools: Foo, Bar\n---\ncorpo\n' >"$AG/rn.md"
zera; roda rn
confere "tools só com grants sem equivalente: rc 1 e nada gravado" "$([ $rc = 1 ] && [ -z "$(ls -A "$DEST")" ]; echo $?)"

# ---------------------------------------------------------------- conferência antes do mv e trap
# defeito: conferência depois do mv (ou ausente). `cmp` falso falha só para o temporário.
mkdir -p "$RAIZ/bin"
cat >"$RAIZ/bin/cmp" <<'X'
#!/bin/bash
for a in "$@"; do case "$a" in */.agent.md.*) exit 1 ;; esac; done
exec /usr/bin/cmp "$@"
X
chmod +x "$RAIZ/bin/cmp"
zera
rc=0; PATH="$RAIZ/bin:$PATH" bash "$SCRIPT" --agentes "$AG" --destino "$DEST" beta >"$RAIZ/saida" 2>"$RAIZ/erro" || rc=$?
confere "temporário que não confere: rc 1 e NENHUM agent.md criado" "$([ $rc = 1 ] && [ ! -e "$DEST/beta/agent.md" ]; echo $?)"
confere "temporário que não confere: nenhum temporário sobrando (trap)" "$([ -z "$(find "$DEST" "$TMPDIR" -name '.agent.md.*' -o -name 'agy-gerar.*' 2>/dev/null)" ]; echo $?)"
# a falha também não pode trocar um agent.md gerado que já existia
zera; roda beta; cp "$DEST/beta/agent.md" "$RAIZ/antes-beta"; printf 'y\n' >>"$AG/beta.md"
rc=0; PATH="$RAIZ/bin:$PATH" bash "$SCRIPT" --agentes "$AG" --destino "$DEST" beta >/dev/null 2>&1 || rc=$?
confere "conferência falha: o agent.md anterior fica intacto" "$([ $rc = 1 ] && cmp -s "$DEST/beta/agent.md" "$RAIZ/antes-beta"; echo $?)"

# ---------------------------------------------------------------- uso e erros
roda inexistente
confere "papel inexistente: rc 1" "$([ $rc = 1 ]; echo $?)"
rc=0; bash "$SCRIPT" --agentes "$RAIZ/nao-existe" --destino "$DEST" >/dev/null 2>&1 || rc=$?
confere "pasta de agentes inexistente: rc 1" "$([ $rc = 1 ]; echo $?)"
rc=0; bash "$SCRIPT" --bobagem >/dev/null 2>&1 || rc=$?
confere "opção desconhecida: rc 2" "$([ $rc = 2 ]; echo $?)"

# ---------------------------------------------------------------- sem sobra de temporário
zera; roda alfa beta
confere "sem .agent.md.* nem rascunho sobrando" "$([ -z "$(find "$DEST" "$TMPDIR" -name '.agent.md.*' -o -name 'agy-gerar.*' 2>/dev/null)" ]; echo $?)"

# ---------------------------------------------------------------- papéis reais do repositório
REAL="$AQUI/../../../../agents"
rc=0; bash "$SCRIPT" --agentes "$REAL" --destino "$RAIZ/real" >/dev/null 2>&1 || rc=$?
confere "papéis reais (qa-adversarial, planejador) geram com tools completo e corpo idêntico" "$([ $rc = 0 ] && tem "$RAIZ/real/planejador/agent.md" "$TODAS" && tem "$RAIZ/real/qa-adversarial/agent.md" "$TODAS" && mesmo_corpo "$REAL/planejador.md" "$RAIZ/real/planejador/agent.md" && mesmo_corpo "$REAL/qa-adversarial.md" "$RAIZ/real/qa-adversarial/agent.md"; echo $?)"

if [ "$falhas" -eq 0 ]; then echo "todos os casos passaram"; exit 0; fi
echo "$falhas caso(s) falharam" >&2; exit 1
