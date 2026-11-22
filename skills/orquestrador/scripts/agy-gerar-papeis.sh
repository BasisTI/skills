#!/bin/bash
# Gera os papéis nativos do agy (`~/.gemini/config/agents/<papel>/agent.md`) a partir
# dos papéis canônicos do clone (`agents/<papel>.md`).
#
# Por que gerar e não apontar um link: agente do agy SEM `tools` no frontmatter
# recebe só um conjunto pequeno de leitura (skill embutida `migrate-agent-settings`),
# e o `agent.md` do papel não tem `tools` porque, no Claude Code, a ausência do campo
# quer dizer "todas" e o campo, quando existe, restringe com outros nomes (Read, Bash…).
# No ensaio da orq #108, `agy --agent planejador` subiu só com `read_file` e MCP: não
# gravou o retorno nem rodou `taiga`/`herdr`. O arquivo gerado leva o frontmatter do agy
# e o corpo do papel sem alteração; o canônico continua sem `tools`.
#
# Frontmatter gerado: `name` e `description` do canônico (a `description` copiada
# linha a linha; vazia é recusada), `subagent: true`, `mainAgent: true` e `tools`.
#   `mainAgent: true` é o que faz `agy agents` listar o papel e `--agent <papel>` valer na
#   sessão do worker; com `mainAgent: false` (o que a `migrate-agent-settings` manda para
#   subagente) o papel some da lista (orq #111). `subagent: true` fica: a skill o manda
#   para agente importado e ele só acrescenta o papel como subagente invocável.
#   - Canônico SEM `tools` (todas, no Claude Code): `tools` completo do agy,
#     [read_file, edit_file, write_file, run_command, manage_task, search_web].
#   - Canônico COM `tools` (restritivo): mapeado como a `migrate-agent-settings`:
#     Read/Glob/Grep -> read_file; Edit/MultiEdit -> edit_file; Write -> write_file;
#     Bash -> run_command e manage_task; WebSearch/WebFetch -> search_web. Grant sem
#     equivalente é descartado com aviso no stderr. Se nada sobrar, o papel é recusado
#     (rc 1): nunca se dá o conjunto completo a um papel que restringia.
# Campos do Claude Code (`mode`, `model`, `color`) são descartados.
#
# Corpo: tudo depois do `---` que fecha o frontmatter é copiado byte a byte, sem
# newline final acrescentado nem removido; o corpo gerado vem depois de UMA linha de
# marca. Frontmatter com CRLF ou BOM, canônico vazio ou sem corpo: recusado (rc 1).
#
# Rode de novo depois de cada `git pull` do clone: a cópia gerada não acompanha o
# canônico sozinha. Rodar duas vezes seguidas não muda nada (nem o mtime).
#
# Uso:
#   agy-gerar-papeis.sh [--agentes <dir>] [--destino <dir>] [--substituir-link] [papel...]
#
#   --agentes  pasta `agents/` do clone. Padrão: a do repositório desta skill.
#   --destino  pasta de agentes do agy. Padrão: ${GEMINI_HOME:-~/.gemini}/config/agents.
#              Recusado (rc 3) se ele ou qualquer diretório do caminho for link simbólico
#              (barra final ignorada); só os ancestrais do $HOME ficam de fora da conferência.
#              Componente `..` também é recusado (rc 3). Limite conhecido (orq #113, M7): com
#              --destino RELATIVO, o caminho é lido a partir do $PWD lógico; se o $HOME é o
#              caminho real (`/var/home/u`) e o $PWD entrou por um link (`/home/u`), o link
#              do $PWD não é reconhecido como ancestral do $HOME e o destino é recusado (rc 3,
#              falso positivo que não grava nada). Contorno: passe --destino absoluto.
#   Nome reservado do agy é comparado sem distinguir caixa (`Self`, `SELF`).
#   papel...   nomes (sem .md). Padrão: todos os `*.md` de --agentes.
#   --substituir-link  troca por arquivo gerado um `agent.md` que hoje é link simbólico
#              (a instalação antiga da orq #107). Sem a opção, o link é recusado.
#
# Todos os papéis são validados e gerados num diretório de rascunho ANTES de qualquer
# escrita: nome inválido, papel inexistente ou frontmatter ruim em QUALQUER papel
# aborta tudo sem gravar nada. Depois, papel a papel: `agent.md` existente só é
# sobrescrito se a PRIMEIRA linha depois do frontmatter dele começar com a marca
# "gerado por agy-gerar-papeis.sh". Arquivo próprio da pessoa (sem a marca ali, mesmo
# com a marca no meio do corpo) e diretório do papel que seja link são recusados, nunca
# perdidos. A escrita vai para um temporário no próprio diretório, é conferida contra o
# rascunho e só então vai por `mv -T`; um `trap` limpa os temporários.
#
# Códigos de saída:
#   0  gerado, ou já estava igual
#   3  recusado (arquivo sem a marca, link, diretório link); os demais são processados
#   2  uso (opção desconhecida, nome de papel inválido)
#   1  erro (papel ausente, frontmatter inválido, falha ao gravar ou conferir)
set -euo pipefail

MARCA='<!-- gerado por agy-gerar-papeis.sh a partir de'
TOOLS_TODAS='read_file, edit_file, write_file, run_command, manage_task, search_web'
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTES="$AQUI/../../../agents"
DESTINO="${GEMINI_HOME:-$HOME/.gemini}/config/agents"
SUBSTITUIR=0
PAPEIS=()
STAGE=""
TMPS=()

limpar() {
  local t
  for t in "${TMPS[@]+"${TMPS[@]}"}"; do rm -f -- "$t"; done
  [ -n "$STAGE" ] && rm -rf -- "$STAGE"
  return 0
}
trap limpar EXIT
trap 'exit 130' INT TERM

uso() { sed -n '/^# Uso:/,/^# Todos os papéis/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --agentes) [ $# -ge 2 ] || uso; AGENTES="$2"; shift 2 ;;
    --destino) [ $# -ge 2 ] || uso; DESTINO="$2"; shift 2 ;;
    --substituir-link) SUBSTITUIR=1; shift ;;
    -h|--help) uso ;;
    -*) echo "opção desconhecida: $1" >&2; uso ;;
    *) PAPEIS+=("$1"); shift ;;
  esac
done

[ -d "$AGENTES" ] || { echo "pasta de agentes inexistente: $AGENTES" >&2; exit 1; }
AGENTES="$(cd "$AGENTES" && pwd)"
if [ ${#PAPEIS[@]} -eq 0 ]; then
  for f in "$AGENTES"/*.md; do
    [ -e "$f" ] || continue
    PAPEIS+=("$(basename "$f" .md)")
  done
fi
[ ${#PAPEIS[@]} -gt 0 ] || { echo "nenhum papel em $AGENTES" >&2; exit 1; }

# Nome de papel: letras, dígitos, `_` e `-`, começando por letra ou dígito. Rejeita
# vazio, ponto, barra e tudo que escape do diretório.
nome_valido() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; }
for papel in "${PAPEIS[@]}"; do
  nome_valido "$papel" || { echo "nome de papel inválido: $papel" >&2; exit 2; }
done

# --destino: nenhum componente do caminho pode ser link simbólico, inclusive com barra
# final (`dl/` escapava do `-L` sobre o caminho inteiro; a subida por componentes pega).
# Só os ancestrais do $HOME ficam de fora (ex. `/home` -> `/var/home`).
[ -n "$DESTINO" ] || { echo "--destino vazio" >&2; exit 2; }
# `..` é recusado: com componente inexistente antes dele (`naoexiste/../dl`) o `-L` não
# vê o link e o `mkdir -p` depois atravessa (orq #113, M2).
case "/$DESTINO/" in
  */../*) echo "recusado: --destino $DESTINO tem componente '..'" >&2; exit 3 ;;
esac
case "$DESTINO" in /*) conf="$DESTINO" ;; *) conf="$PWD/$DESTINO" ;; esac
while [ "$conf" != "/" ] && [ -n "$conf" ]; do
  if [ -L "$conf" ]; then
    case "$HOME/" in
      "$conf"/*) ;;   # ancestral do HOME (ou o próprio): tolerado
      *) echo "recusado: --destino $DESTINO passa por link simbólico: $conf" >&2; exit 3 ;;
    esac
  fi
  conf="${conf%/*}"
done

# cabecalho <canônico> <papel>: imprime o frontmatter do agy + a marca; devolve no
# stderr, na última linha, o número da linha do `---` que fecha. Falha se o
# frontmatter for inválido.
cabecalho() {
  awk -v todas="$TOOLS_TODAS" -v marca="$MARCA $2.md; não edite, rode o script de novo -->" '
    function mapear(tok,   t) {
      gsub(/^[ \t\047"]+|[ \t\047"]+$/, "", tok); if (tok ~ /\(/) padrao = 1; sub(/\(.*$/, "", tok)
      if (tok == "") return
      if (tok == "Read" || tok == "Glob" || tok == "Grep") t = "read_file"
      else if (tok == "Edit" || tok == "MultiEdit") t = "edit_file"
      else if (tok == "Write") t = "write_file"
      else if (tok == "Bash") { usar["run_command"] = 1; t = "manage_task" }
      else if (tok == "WebSearch" || tok == "WebFetch") t = "search_web"
      else { printf "aviso: grant de tools sem equivalente no agy, descartado: %s\n", tok > "/dev/stderr"; return }
      usar[t] = 1
    }
    function achatar(s,   n, i, partes) {
      sub(/(^|[ \t])#.*$/, "", s)   # comentário YAML não é grant
      gsub(/[\[\]]/, "", s); n = split(s, partes, ",")
      for (i = 1; i <= n; i++) mapear(partes[i])
    }
    function falha(msg) { print msg > "/dev/stderr"; fm = 0; exit 1 }
    function limpo(v) {   # valor escalar sem espaços, aspas nem comentário
      sub(/^[ \t]+/, "", v); if (v ~ /^#/) return ""
      if (v ~ /^"/) { sub(/^"/, "", v); sub(/".*$/, "", v) }
      else if (v ~ /^\047/) { sub(/^\047/, "", v); sub(/\047.*$/, "", v) }
      else { sub(/[ \t]+#.*$/, "", v) }
      gsub(/^[ \t]+|[ \t]+$/, "", v); return v
    }
    NR == 1 {
      if ($0 != "---") falha("sem frontmatter (ou com CRLF/BOM)")
      print "---"; fm = 1; next
    }
    fm {
      if ($0 == "---") {
        if (!tem_name) falha("frontmatter sem name")
        if (nome == "") falha("frontmatter com name vazio")
        if (tolower(nome) ~ /^(self|browser|research|deepagent|review-agent)$/) falha("name reservado do agy: " nome " (prefixe o nome)")
        if (!tem_desc || desc_txt == "" || desc_txt ~ /^(""|\047\047)$/ || tolower(desc_txt) ~ /^(null|~)$/ || desc_txt ~ /^(\[.*\]|\{.*\})$/) falha("frontmatter sem description (ou vazia, ou sem texto: \"\", null, ~, [], {})")
        if (desc_lista) falha("description em lista: não é texto")
        if (tem_dis) falha("disallowedTools não tem equivalente no agy: papel recusado")
        if (tem_tools) {
          if (padrao) falha("tools com padrão entre parênteses (ex. Bash(git:*)): o agy não restringe comando, papel recusado")
          out = ""
          split("read_file edit_file write_file run_command manage_task search_web", ord, " ")
          for (i = 1; i <= 6; i++) if (usar[ord[i]]) out = out (out == "" ? "" : ", ") ord[i]
          if (out == "") falha("tools restritivo sem nenhum equivalente no agy: papel recusado")
          tools = "[" out "]"
        } else tools = "[" todas "]"
        print "subagent: true"; print "mainAgent: true"; print "tools: " tools; print "---"; print marca
        printf "%d\n", NR > "/dev/stderr"
        fm = 0; exit 0
      }
      if ($0 ~ /^[A-Za-z_][A-Za-z0-9_-]*:/) {
        chave = $0; sub(/:.*/, "", chave); resto = $0; sub(/^[^:]*:[ \t]*/, "", resto)
        manter = (chave == "name" || chave == "description"); modo = chave; primeira = 1
        if (chave == "name") { tem_name = 1; nome = limpo(resto) }
        if (chave == "description") { tem_desc = 1; v = resto; sub(/^[>|][-+0-9]*[ \t]*(#.*)?$/, "", v); v = limpo(v); desc_txt = v; desc_cab = (v != "") }
        if (chave == "tools") { tem_tools = 1; achatar(resto) }
        if (chave == "disallowedTools") tem_dis = 1
      } else if (modo == "description") {
        v = $0
        if (v !~ /^[ \t]*#/ && v !~ /^[ \t]*$/) {   # linha em branco ou só comentário não conta
          if (!desc_cab && primeira && v ~ /^[ \t]*-[ \t]/) desc_lista = 1
          primeira = 0
          gsub(/[ \t]/, "", v); desc_txt = desc_txt v
        }
      } else if (modo == "tools" && $0 ~ /^[ \t]*-[ \t]/) {
        v = $0; sub(/^[ \t]*-[ \t]*/, "", v); sub(/(^|[ \t])#.*$/, "", v); mapear(v)
      }
      if (manter) print
      next
    }
    END { if (fm) { print "frontmatter não fechado" > "/dev/stderr"; exit 1 } }
  ' "$1"
}

# ---- fase 1: validar e gerar tudo no rascunho, sem escrever no destino ------------
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/agy-gerar.XXXXXX")"
[ -n "$STAGE" ] && [ -d "$STAGE" ] || { echo "mktemp falhou" >&2; exit 1; }
for papel in "${PAPEIS[@]}"; do
  src="$AGENTES/$papel.md"
  [ -f "$src" ] || { echo "papel inexistente: $src" >&2; exit 1; }
  [ -s "$src" ] || { echo "canônico vazio: $src" >&2; exit 1; }
  if ! cabecalho "$src" "$papel" >"$STAGE/$papel.cab" 2>"$STAGE/$papel.err"; then
    cat "$STAGE/$papel.err" >&2; echo "falha ao gerar $papel" >&2; exit 1
  fi
  # o stderr do awk leva avisos e, na última linha, o número do `---` de fechamento
  grep -v '^[0-9][0-9]*$' "$STAGE/$papel.err" >&2 || true
  fech_n="$(grep '^[0-9][0-9]*$' "$STAGE/$papel.err" | tail -n 1)"
  [ -n "$fech_n" ] || { echo "falha ao gerar $papel (sem fechamento)" >&2; exit 1; }
  # corpo: bytes exatos depois do `---` de fechamento
  tail -n +"$((fech_n + 1))" "$src" >"$STAGE/$papel.corpo"
  [ -s "$STAGE/$papel.corpo" ] || { echo "canônico sem corpo: $src" >&2; exit 1; }
  cat "$STAGE/$papel.cab" "$STAGE/$papel.corpo" >"$STAGE/$papel.agent.md"
  [ -s "$STAGE/$papel.agent.md" ] || { echo "geração vazia: $papel" >&2; exit 1; }
done

# tem_marca <arquivo>: a primeira linha depois do frontmatter começa com a marca.
tem_marca() {
  awk -v marca="$MARCA" '
    NR == 1 { if ($0 != "---") exit 1; fm = 1; next }
    fm && $0 == "---" { fm = 0; fechou = 1; next }
    fechou { exit (index($0, marca) == 1 ? 0 : 1) }
    END { if (!fechou) exit 1 }
  ' "$1"
}

# ---- fase 2: gravar papel a papel -------------------------------------------------
rc_final=0
for papel in "${PAPEIS[@]}"; do
  dir="$DESTINO/$papel"
  alvo="$dir/agent.md"
  gerado="$STAGE/$papel.agent.md"

  if [ -L "$dir" ]; then
    echo "recusado: $dir é link simbólico" >&2; rc_final=3; continue
  fi
  if [ -L "$alvo" ] && [ "$SUBSTITUIR" -eq 0 ]; then
    echo "recusado: $alvo é link simbólico (use --substituir-link)" >&2; rc_final=3; continue
  fi
  if [ -f "$alvo" ] && [ ! -L "$alvo" ] && ! tem_marca "$alvo"; then
    echo "recusado: $alvo não tem a marca de arquivo gerado na primeira linha depois do frontmatter" >&2
    rc_final=3; continue
  fi
  if [ -e "$alvo" ] && [ ! -L "$alvo" ] && [ ! -f "$alvo" ]; then
    echo "recusado: $alvo não é arquivo regular" >&2; rc_final=3; continue
  fi
  if [ ! -L "$alvo" ] && [ -f "$alvo" ] && cmp -s "$gerado" "$alvo"; then
    echo "igual: $alvo"; continue
  fi

  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.agent.md.XXXXXX")"
  TMPS+=("$tmp")
  cat "$gerado" >"$tmp"
  # conferência ANTES do mv: não vazio e idêntico ao rascunho validado
  if [ ! -s "$tmp" ] || ! cmp -s "$gerado" "$tmp"; then
    echo "conferência do temporário falhou: $papel (nada foi trocado)" >&2; exit 1
  fi
  chmod 644 "$tmp"
  mv -T -- "$tmp" "$alvo"   # -T troca o próprio link, sem entrar no destino dele
  echo "gerado: $alvo"
done
exit "$rc_final"
