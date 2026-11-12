#!/bin/bash
# Abre uma pendência pelo arquivo e espera o daemon do `orq` registrá-la
# (references/acompanhamento.md, "Abrir a pendência pelo arquivo").
#
# Uso:
#   espera-pendencia-registrada.sh <dir_pendencias> <slug> [limite_s]   (padrão: 30)
#
#   <dir_pendencias>  pasta `pendencias/` da rodada (ou da US, no coordenador)
#   <slug>            nome do arquivo sem extensão. O script usa:
#                       .<slug>.md.tmp   arquivo recém-gravado: vira <slug>.md por `mv`
#                       <slug>.md        arquivo já no lugar (nada a mover)
#                       <slug>.registrada.json  {"id","chave","url"}, escrito pelo daemon
#                       <slug>.erro.txt         motivo da recusa, escrito pelo daemon
#   [limite_s]        espera máxima em segundos (inteiro, padrão 30)
#
# Saída (a última linha do stdout diz qual sinal saiu):
#   0  registrada: "pendência registrada: id=<id> chave=<chave> url=<url>"
#   1  recusada pelo daemon: imprime o conteúdo do `.erro.txt` e termina com
#      "pendência recusada: <arquivo>" (corrija o arquivo e rode de novo)
#   2  uso / ambiente / arquivo inexistente (nem `.<slug>.md.tmp` nem `<slug>.md`)
#   3  limite esgotado: "pendência não registrada: <arquivo>" (daemon parado ou
#      anterior à #15; o coordenador registra com `orq pend importar <arquivo>`)
#
# Existe porque a espera improvisada falhou em massa sob zsh: 79 erros
# "no matches found" em 58 sessões (2026-10-22 a 2026-11-12) ao esperar
# `*.registrada.json`/`*.erro.txt`, pois o zsh aborta o comando quando o glob
# não casa; um laço gastou as 15 voltas sem rodar o `ls`, e um `cat` com os dois
# globs escondeu o resultado. Aqui cada arquivo é testado com `[ -e ]`, sem glob.
#
# Não chama `orq pend responder` nem `orq pend resolver` (proibidos ao worker).
# Feito para `run_in_background` (Claude Code) ou para o laço do turno (Codex).

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "uso: $0 <dir_pendencias> <slug> [limite_s]" >&2
  exit 2
fi
DIR="$1"
SLUG="$2"
LIMITE="${3:-30}"

case "$LIMITE" in
  '' | *[!0-9]*) echo "limite_s deve ser inteiro: $LIMITE" >&2; exit 2 ;;
esac
case "$SLUG" in
  '' | */* | .* | *.md | *.json | *.txt) echo "slug inválido (sem caminho, sem ponto inicial, sem extensão): $SLUG" >&2; exit 2 ;;
esac
[ -d "$DIR" ] || { echo "diretório inexistente: $DIR" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "falta \`jq\` no PATH" >&2; exit 2; }

TMP="$DIR/.$SLUG.md.tmp"
MD="$DIR/$SLUG.md"
OK="$DIR/$SLUG.registrada.json"
ERRO="$DIR/$SLUG.erro.txt"

if [ -e "$TMP" ]; then
  mv "$TMP" "$MD"
elif [ ! -e "$MD" ]; then
  echo "nem $TMP nem $MD existem" >&2
  exit 2
fi

inicio=$(date +%s)
while :; do
  if [ -e "$OK" ]; then
    echo "pendência registrada: $(jq -r '"id=" + (.id // "?" | tostring) + " chave=" + (.chave // "?" | tostring) + " url=" + (.url // "?" | tostring)' "$OK")"
    exit 0
  fi
  # `.erro.txt` mais antigo que o arquivo é de uma tentativa anterior: ignora.
  if [ -e "$ERRO" ] && ! [ "$MD" -nt "$ERRO" ]; then
    cat "$ERRO"
    echo "pendência recusada: $MD"
    exit 1
  fi
  agora=$(date +%s)
  if [ $((agora - inicio)) -ge "$LIMITE" ]; then
    echo "pendência não registrada: $MD"
    exit 3
  fi
  sleep 1
done
