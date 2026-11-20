#!/bin/bash
# Replica, para um worktree novo, a confiança nos hooks do repo que o Codex já
# guarda para o checkout principal (`[hooks.state."<hooks.json>:<evento>:<i>:<j>"]`
# no config.toml). Sem isso, o Codex pergunta "trust this hook?" a cada worktree e
# o `herdr-workers.sh start` estoura o timeout nessa pergunta.
#
# O despacho roda este script logo depois de criar o worktree e ANTES de lançar o
# Codex nele (references/despacho.md, "Worktree e pacote").
#
# Nunca cria confiança nova: só copia `trusted_hash` que o checkout principal já
# tem, e só quando o `.codex/hooks.json` do worktree é byte a byte igual ao do
# checkout (sha256). O hash vale para a definição do hook, então a cópia só é
# válida com o arquivo idêntico. Se diferir, a pergunta do Codex volta, como deve.
#
# Uso:
#   codex-confiar-hooks.sh <worktree> [--checkout <repo principal>] [--config <config.toml>] [--podar]
#   codex-confiar-hooks.sh --podar [--config <config.toml>]
#
#   <worktree>   raiz do worktree recém-criado.
#   --checkout   repo principal. Padrão: o pai do `git rev-parse --git-common-dir`.
#   --config     padrão: ${CODEX_HOME:-~/.codex}/config.toml.
#   --podar      remove do config as entradas hooks.state cujo hooks.json não
#                existe mais (worktrees limpos). Só mexe em tabelas hooks.state.
#                Pode vir sozinho (sem <worktree>).
#
# Só lê e escreve tabelas `hooks.state`; as demais seções do config (cabeçalhos de
# MCP, por exemplo) passam intactas e nunca são impressas. Antes da primeira
# escrita faz backup (`<config>.bak-<data>`); grava em temporário + mv; relê e
# confere. Rodar duas vezes não duplica nada.
#
# Códigos de saída:
#   0  feito, ou nada a fazer (worktree sem .codex/hooks.json; entradas já lá)
#   3  recusado, nada gravado (hooks.json diferente do checkout, checkout sem
#      hooks.json ou sem entradas): o Codex vai perguntar; aí vale a resposta
#      manual "Continue without trusting"
#   2  uso
#   1  erro (falha ao gravar ou conferir)
#
# Limite: o caminho é comparado como texto; caminho com aspas ou barra invertida
# (escapes do TOML) não é reconhecido.
set -euo pipefail

USO='uso: codex-confiar-hooks.sh <worktree> [--checkout <repo>] [--config <config.toml>] [--podar]
     codex-confiar-hooks.sh --podar [--config <config.toml>]'
uso() { printf 'codex-confiar-hooks: %s\n%s\n' "$1" "$USO" >&2; exit 2; }
erro() { printf 'codex-confiar-hooks: %s\n' "$1" >&2; exit 1; }
info() { printf 'codex-confiar-hooks: %s\n' "$1"; }

worktree=""; checkout=""; config=""; podar=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) printf '%s\n' "$USO"; exit 0 ;;
    --checkout) [ $# -ge 2 ] || uso '--checkout sem valor'; checkout=$2; shift 2 ;;
    --config)   [ $# -ge 2 ] || uso '--config sem valor';   config=$2;   shift 2 ;;
    --podar) podar=1; shift ;;
    -*) uso "opção desconhecida: $1" ;;
    *) [ -z "$worktree" ] || uso "argumento a mais: $1"; worktree=$1; shift ;;
  esac
done
[ -n "$worktree" ] || [ "$podar" = 1 ] || uso 'falta o <worktree>'
[ -n "$config" ] || config="${CODEX_HOME:-$HOME/.codex}/config.toml"

tmp=""; paths=""; blocos=""; faltam=""
trap 'rm -f "$tmp" "$paths" "$blocos" "$faltam"' EXIT
backup_feito=0

backup_uma_vez() {
  [ "$backup_feito" = 0 ] || return 0
  [ -f "$config" ] && cp -p -- "$config" "$config.bak-$(date +%Y%m%d%H%M%S)"
  backup_feito=1
}
novo_tmp() {
  tmp=$(mktemp "$config.tmp.XXXXXX")
  chmod --reference="$config" -- "$tmp" 2>/dev/null || true
}

# --- copiar a confiança do checkout para o worktree --------------------------
copiar() {
  local wt ck hw hc nwt tot ja novas h
  [ -d "$worktree" ] || { info "worktree inexistente: $worktree"; return 0; }
  wt=$(cd "$worktree" && pwd -P)
  if [ ! -f "$wt/.codex/hooks.json" ]; then
    info "sem .codex/hooks.json em $wt: nada a fazer"; return 0
  fi
  if [ -n "$checkout" ]; then
    ck=$(cd "$checkout" 2>/dev/null && pwd -P) || erro "checkout inexistente: $checkout"
  else
    local gc
    gc=$(git -C "$wt" rev-parse --git-common-dir 2>/dev/null) || erro "não é repositório git: $wt (use --checkout)"
    case "$gc" in /*) ;; *) gc="$wt/$gc" ;; esac
    ck=$(cd "$gc/.." && pwd -P)
  fi
  if [ "$ck" = "$wt" ]; then info "o worktree é o próprio checkout: nada a fazer"; return 0; fi
  if [ ! -f "$ck/.codex/hooks.json" ]; then
    info "RECUSADO: o checkout $ck não tem .codex/hooks.json; nada gravado (o Codex vai perguntar)"; RC=3; return 0
  fi
  hw=$(sha256sum <"$wt/.codex/hooks.json"); hw=${hw%% *}
  hc=$(sha256sum <"$ck/.codex/hooks.json"); hc=${hc%% *}
  if [ "$hw" != "$hc" ]; then
    info "RECUSADO: o .codex/hooks.json do worktree difere do do checkout (sha256 ${hw:0:12} contra ${hc:0:12}); nada gravado (o Codex vai perguntar)"; RC=3; return 0
  fi
  if [ ! -f "$config" ]; then
    info "RECUSADO: $config não existe, logo o checkout não tem entradas hooks.state; nada gravado (o Codex vai perguntar)"; RC=3; return 0
  fi

  blocos=$(mktemp "${TMPDIR:-/tmp}/codex-confiar-blocos.XXXXXX")
  # Uma passada: guarda os blocos hooks.state do checkout e as chaves existentes.
  read -r tot ja < <(awk -v old="$ck/.codex/hooks.json" -v new="$wt/.codex/hooks.json" -v out="$blocos" '
    function fecha(   i, n) {
      if (key == "") return
      have[key] = 1
      if (path == old) { nc++; ck_key[nc] = key; ck_suf[nc] = suf; ck_n[nc] = nb
        for (i = 1; i <= nb; i++) ck_body[nc, i] = body[i] }
      key = ""; nb = 0
    }
    /^\[/ {
      fecha()
      l = $0
      if (sub(/^\[hooks\.state\."/, "", l) && sub(/"\][ \t]*(#.*)?$/, "", l) && match(l, /:[^:]+:[0-9]+:[0-9]+$/)) {
        key = l; suf = substr(l, RSTART); path = substr(l, 1, RSTART - 1); nb = 0
      }
      next
    }
    key != "" { body[++nb] = $0 }
    END {
      fecha()
      tot = nc + 0; ja = 0
      for (c = 1; c <= nc; c++) {
        nk = new ck_suf[c]
        if (nk in have) { ja++; continue }
        n = ck_n[c]; while (n > 0 && ck_body[c, n] ~ /^[ \t]*$/) n--
        printf "\n[hooks.state.\"%s\"]\n", nk >> out
        for (i = 1; i <= n; i++) print ck_body[c, i] >> out
      }
      print tot, ja
    }' "$config")
  [ -n "$tot" ] || erro "falha ao ler $config"
  if [ "$tot" = 0 ]; then
    info "RECUSADO: o checkout $ck não tem entradas hooks.state em $config; nada gravado (o Codex vai perguntar)"; RC=3; return 0
  fi
  if [ ! -s "$blocos" ]; then
    info "já confiado: as $ja entrada(s) hooks.state de $wt já estão em $config; nada gravado"; return 0
  fi
  novas=$(grep -c '^\[hooks\.state\.' "$blocos")
  backup_uma_vez
  novo_tmp
  cp -- "$config" "$tmp"
  [ -z "$(tail -c1 "$config")" ] || printf '\n' >>"$tmp"
  cat -- "$blocos" >>"$tmp"
  mv -- "$tmp" "$config"; tmp=""
  # Relê e confere que cada tabela nova está lá, com o mesmo trusted_hash.
  while IFS= read -r h; do
    grep -qxF -- "$h" "$config" || erro "conferência falhou: $h ausente em $config (backup: $config.bak-*)"
  done < <(grep '^\[hooks\.state\.' "$blocos")
  info "confiado: $novas entrada(s) hooks.state copiadas do checkout $ck para $wt (já havia $ja)"
}

# --- podar entradas cujo hooks.json não existe mais --------------------------
podar_entradas() {
  local p n=0
  [ -f "$config" ] || { info "podar: $config não existe; nada a fazer"; return 0; }
  paths=$(mktemp "${TMPDIR:-/tmp}/codex-confiar-paths.XXXXXX")
  faltam=$(mktemp "${TMPDIR:-/tmp}/codex-confiar-faltam.XXXXXX")
  awk '/^\[hooks\.state\."/ { l=$0; sub(/^\[hooks\.state\."/,"",l); sub(/"\][ \t]*(#.*)?$/,"",l)
         if (match(l, /:[^:]+:[0-9]+:[0-9]+$/)) print substr(l,1,RSTART-1) }' "$config" | sort -u >"$paths"
  while IFS= read -r p; do
    [ -e "$p" ] || { printf '%s\n' "$p" >>"$faltam"; n=$((n+1)); }
  done <"$paths"
  if [ "$n" = 0 ]; then info "podar: nenhuma entrada de hooks.json inexistente"; return 0; fi
  backup_uma_vez
  novo_tmp
  awk -v lista="$faltam" '
    BEGIN { while ((getline l < lista) > 0) sumido[l] = 1 }
    /^\[/ {
      skip = 0; l = $0
      if (sub(/^\[hooks\.state\."/, "", l) && sub(/"\][ \t]*(#.*)?$/, "", l) && match(l, /:[^:]+:[0-9]+:[0-9]+$/))
        if (substr(l, 1, RSTART - 1) in sumido) skip = 1
    }
    !skip { print }' "$config" >"$tmp"
  mv -- "$tmp" "$config"; tmp=""
  while IFS= read -r p; do
    ! grep -qF -- "[hooks.state.\"$p:" "$config" || erro "conferência falhou: entrada de $p ainda em $config"
  done <"$faltam"
  info "podado: entradas hooks.state de $n hooks.json inexistente(s) removidas de $config"
}

RC=0
if [ -n "$worktree" ]; then copiar; fi
if [ "$podar" = 1 ]; then podar_entradas; fi
exit "$RC"
