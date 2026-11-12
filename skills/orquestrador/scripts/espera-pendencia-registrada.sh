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
#   [limite_s]        espera máxima em segundos (inteiro de 0 a 7200, padrão 30)
#
# O script confere o que o daemon confere e, fora disso, sai 2 na hora em vez de
# esperar o limite por um arquivo que o daemon ignora sem escrever `.erro.txt`:
#   - slug: ^[a-z0-9][a-z0-9_-]{0,63}$ (orq/internal/pendencias/importar.go);
#   - pasta: termina em <projeto>/TG-<ref>/pendencias (coordenador) ou
#     <projeto>/TG-<ref>/<papel>/<rodada>/pendencias (worker). O script não sabe a
#     raiz (ORQ_TRABALHO_DIR): confere só a forma, o daemon confere o resto.
#
# Saída (a última linha do stdout diz qual sinal saiu):
#   0  registrada: "pendência registrada: id=<id> chave=<chave> url=<url>"
#   1  recusada pelo daemon: imprime o conteúdo do `.erro.txt` e termina com
#      "pendência recusada: <arquivo>" (corrija o arquivo e rode de novo). O erro
#      conta como atual se for novo (não havia `.erro.txt` ao começar, ou o texto
#      mudou) ou, no fim do limite, se ainda existir: o daemon não regrava
#      `.erro.txt` de texto idêntico, então reenvio recusado pelo mesmo motivo
#      só aparece assim. (Daemon parado com erro antigo também sai 1: leia o texto.)
#   2  uso / ambiente / slug ou pasta fora da regra / arquivo inexistente (nem
#      `.<slug>.md.tmp` nem `<slug>.md`) / `.registrada.json` ilegível / mv falhou
#   3  limite esgotado: "pendência não registrada: <arquivo>" (daemon parado ou
#      anterior à #15; o coordenador registra com `orq pend importar <arquivo>`)
#
# Limite conhecido: slug reutilizado (já existe `<slug>.registrada.json`) sai 0 na
# hora com o id antigo, e o conteúdo novo não vira pendência; o daemon faz igual.
# Use um slug novo para outra pendência.
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
  '' | *[!0-9]*) echo "limite_s deve ser inteiro de 0 a 7200: $LIMITE" >&2; exit 2 ;;
esac
if [ "${#LIMITE}" -gt 4 ] || [ "$((10#$LIMITE))" -gt 7200 ]; then
  echo "limite_s deve ser de 0 a 7200: $LIMITE" >&2
  exit 2
fi
LIMITE=$((10#$LIMITE))

if ! [[ "$SLUG" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ ]]; then
  echo "slug inválido: use ^[a-z0-9][a-z0-9_-]{0,63}\$ (minúsculas, dígitos, - e _, até 64; sem extensão): $SLUG" >&2
  exit 2
fi
[ -d "$DIR" ] || { echo "diretório inexistente: $DIR" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "falta \`jq\` no PATH" >&2; exit 2; }

DIR="$(cd "$DIR" && pwd)"
# Forma do caminho (localDe do daemon): .../<projeto>/TG-<ref>[/<papel>/<rodada>]/pendencias
IFS=/ read -r -a partes <<<"$DIR"
n="${#partes[@]}"
forma=nao
if [ "${partes[n - 1]}" = "pendencias" ]; then
  if [ "$n" -ge 4 ] && [[ "${partes[n - 2]}" =~ ^TG-[1-9][0-9]*$ ]]; then forma=sim; fi
  if [ "$n" -ge 6 ] && [[ "${partes[n - 4]}" =~ ^TG-[1-9][0-9]*$ ]]; then forma=sim; fi
fi
if [ "$forma" != sim ]; then
  echo "pasta fora da forma <projeto>/TG-<ref>[/<papel>/<rodada>]/pendencias (o daemon ignora o arquivo sem avisar): $DIR" >&2
  exit 2
fi

TMP="$DIR/.$SLUG.md.tmp"
MD="$DIR/$SLUG.md"
OK="$DIR/$SLUG.registrada.json"
ERRO="$DIR/$SLUG.erro.txt"

if [ -e "$TMP" ]; then
  mv -- "$TMP" "$MD" || { echo "não consegui mover $TMP para $MD" >&2; exit 2; }
elif [ ! -e "$MD" ]; then
  echo "nem $TMP nem $MD existem" >&2
  exit 2
fi

# Estado do erro ao começar: serve para reconhecer um erro novo (o daemon só
# regrava o `.erro.txt` quando o texto muda).
erro_ini=""
tinha_erro=nao
if [ -e "$ERRO" ]; then
  tinha_erro=sim
  erro_ini="$(cat -- "$ERRO" 2>/dev/null || true)"
fi

recusada() {
  cat -- "$ERRO" 2>/dev/null || echo "(erro ilegível)"
  echo "pendência recusada: $MD"
  exit 1
}

inicio=$(date +%s)
while :; do
  if [ -e "$OK" ]; then
    if ! resumo="$(jq -r '"id=" + (.id // "?" | tostring) + " chave=" + (.chave // "?" | tostring) + " url=" + (.url // "?" | tostring)' "$OK" 2>/dev/null)" || [ -z "$resumo" ]; then
      echo "pendência registrada, mas $OK está ilegível: leia-o à mão"
      exit 2
    fi
    echo "pendência registrada: $resumo"
    exit 0
  fi
  if [ -e "$ERRO" ]; then
    erro_agora="$(cat -- "$ERRO" 2>/dev/null || true)"
    if [ "$tinha_erro" = nao ] || [ "$erro_agora" != "$erro_ini" ]; then
      recusada
    fi
  fi
  agora=$(date +%s)
  if [ $((agora - inicio)) -ge "$LIMITE" ]; then
    # Erro igual ao do começo e nenhum registro: o daemon não regrava texto idêntico.
    if [ -e "$ERRO" ]; then recusada; fi
    echo "pendência não registrada: $MD"
    exit 3
  fi
  sleep 1
done
