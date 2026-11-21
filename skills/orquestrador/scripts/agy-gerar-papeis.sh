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
# linha a linha), `subagent: true`, `mainAgent: false` e
# `tools: [read_file, edit_file, write_file, run_command, manage_task, search_web]`.
# Campos do Claude Code (`mode`, `model`, `color`, `tools`) são descartados.
#
# Rode de novo depois de cada `git pull` do clone: a cópia gerada não acompanha o
# canônico sozinha. Rodar duas vezes seguidas não muda nada.
#
# Uso:
#   agy-gerar-papeis.sh [--agentes <dir>] [--destino <dir>] [--substituir-link] [papel...]
#
#   --agentes  pasta `agents/` do clone. Padrão: a do repositório desta skill.
#   --destino  pasta de agentes do agy. Padrão: ${GEMINI_HOME:-~/.gemini}/config/agents.
#   papel...   nomes (sem .md). Padrão: todos os `*.md` de --agentes.
#   --substituir-link  troca por arquivo gerado um `agent.md` que hoje é link simbólico
#              (a instalação antiga da orq #107). Sem a opção, o link é recusado.
#
# Um `agent.md` existente só é sobrescrito se tiver a marca "gerado por
# agy-gerar-papeis.sh" na primeira linha depois do frontmatter. Arquivo próprio da
# pessoa (sem a marca) é recusado, nunca perdido. Grava em temporário + mv.
#
# Códigos de saída:
#   0  gerado, ou já estava igual
#   3  recusado (arquivo sem a marca, ou link sem --substituir-link); os demais
#      papéis são processados
#   2  uso
#   1  erro (papel ausente, frontmatter inválido, falha ao gravar)
set -euo pipefail

MARCA='<!-- gerado por agy-gerar-papeis.sh a partir de'
TOOLS='[read_file, edit_file, write_file, run_command, manage_task, search_web]'
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTES="$AQUI/../../../agents"
DESTINO="${GEMINI_HOME:-$HOME/.gemini}/config/agents"
SUBSTITUIR=0
PAPEIS=()

uso() { sed -n '/^# Uso:/,/^# Códigos/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2; exit 2; }

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

# gerar_conteudo <canônico>: imprime o agent.md do agy. Falha se o frontmatter não
# tiver `name` e `description`.
gerar_conteudo() {
  local src="$1" papel="$2"
  awk -v tools="$TOOLS" -v marca="$MARCA $papel.md; não edite, rode o script de novo -->" '
    NR == 1 {
      if ($0 != "---") { print "sem frontmatter" > "/dev/stderr"; exit 1 }
      fm = 1; next
    }
    fm {
      if ($0 == "---") {
        fm = 0
        if (!tem_name || !tem_desc) { print "frontmatter sem name ou description" > "/dev/stderr"; exit 1 }
        print "subagent: true"; print "mainAgent: false"; print "tools: " tools; print "---"; print marca
        next
      }
      if ($0 ~ /^[A-Za-z_][A-Za-z0-9_-]*:/) {
        chave = $0; sub(/:.*/, "", chave)
        manter = (chave == "name" || chave == "description")
        if (chave == "name") tem_name = 1
        if (chave == "description") tem_desc = 1
      }
      if (manter) print
      next
    }
    { print }
    END { if (fm) { print "frontmatter não fechado" > "/dev/stderr"; exit 1 } }
  ' "$src"
}

rc_final=0
for papel in "${PAPEIS[@]}"; do
  case "$papel" in */*|""|.*) echo "nome de papel inválido: $papel" >&2; exit 2 ;; esac
  src="$AGENTES/$papel.md"
  [ -f "$src" ] || { echo "papel inexistente: $src" >&2; exit 1; }
  dir="$DESTINO/$papel"
  alvo="$dir/agent.md"

  if [ -L "$alvo" ] && [ "$SUBSTITUIR" -eq 0 ]; then
    echo "recusado: $alvo é link simbólico (use --substituir-link)" >&2
    rc_final=3; continue
  fi
  if [ -f "$alvo" ] && [ ! -L "$alvo" ] && ! grep -qF -- "$MARCA" "$alvo"; then
    echo "recusado: $alvo não tem a marca de arquivo gerado" >&2
    rc_final=3; continue
  fi

  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.agent.md.XXXXXX")"
  if ! gerar_conteudo "$src" "$papel" > "$tmp"; then
    rm -f -- "$tmp"; echo "falha ao gerar $papel" >&2; exit 1
  fi
  if [ ! -L "$alvo" ] && [ -f "$alvo" ] && cmp -s "$tmp" "$alvo"; then
    rm -f -- "$tmp"; echo "igual: $alvo"; continue
  fi
  chmod 644 "$tmp"
  mv -T -- "$tmp" "$alvo"   # -T troca o próprio link, sem entrar no destino dele
  grep -qx 'tools: \[read_file, edit_file, write_file, run_command, manage_task, search_web\]' "$alvo" \
    || { echo "conferência falhou: $alvo" >&2; exit 1; }
  echo "gerado: $alvo"
done
exit "$rc_final"
