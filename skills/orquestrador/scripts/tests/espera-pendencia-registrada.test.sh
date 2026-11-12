#!/bin/bash
# Testes de espera-pendencia-registrada.sh: simulam o daemon com um processo de
# fundo que escreve .registrada.json ou .erro.txt. Sem `orq`, sem agente real.
# Uso: bash espera-pendencia-registrada.test.sh   (ou zsh -c 'bash ...')
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$AQUI/../espera-pendencia-registrada.sh"
BASE="$(mktemp -d "${TMPDIR:-/tmp}/espera-pend.XXXXXX")"
falhas=0

confere() { # nome esperado obtido
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FALHA $1: esperado [$2], obtido [$3]"; falhas=$((falhas + 1)); fi
}
roda() { # imprime "<codigo>|<ultima linha>"; saída completa em $BASE/out
  local cod=0
  "$SCRIPT" "$@" >"$BASE/out" 2>"$BASE/err" || cod=$?
  echo "$cod|$(tail -n 1 "$BASE/out")"
}
novo() { D="$BASE/$1"; mkdir -p "$D"; }

# 1. registrada: arquivo .tmp é movido e o JSON é lido
novo registrada
echo x >"$D/.p1.md.tmp"
( sleep 1; echo '{"id":"TG-9#P1","chave":"TG-9","url":"http://x/p1"}' >"$D/p1.registrada.json" ) &
confere "registrada (0 e linha final)" "0|pendência registrada: id=TG-9#P1 chave=TG-9 url=http://x/p1" "$(roda "$D" p1 10)"
confere "registrada: .tmp virou .md" "sim" "$([ -e "$D/p1.md" ] && [ ! -e "$D/.p1.md.tmp" ] && echo sim || echo não)"
wait

# 2. registrada com campos ausentes não derruba (jq com // valor)
novo parcial
echo x >"$D/p2.md"
echo '{"id":7}' >"$D/p2.registrada.json"
confere "registrada parcial" "0|pendência registrada: id=7 chave=? url=?" "$(roda "$D" p2 5)"

# 3. erro: conteúdo do erro e saída 1
novo erro
echo x >"$D/.p3.md.tmp"
( sleep 1; echo 'linha 4: falta Contexto' >"$D/p3.erro.txt" ) &
r="$(roda "$D" p3 10)"
confere "erro (1 e linha final)" "1|pendência recusada: $D/p3.md" "$r"
confere "erro: conteúdo impresso" "linha 4: falta Contexto" "$(head -n 1 "$BASE/out")"
wait

# 4. erro antigo de tentativa anterior é ignorado; o novo resultado vale
novo reenvio
echo 'erro velho' >"$D/p4.erro.txt"
sleep 1
echo x >"$D/.p4.md.tmp"
( sleep 1; echo '{"id":"P4","chave":"K","url":"u"}' >"$D/p4.registrada.json" ) &
confere "erro velho ignorado" "0|pendência registrada: id=P4 chave=K url=u" "$(roda "$D" p4 10)"
wait

# 5. limite esgotado
novo limite
echo x >"$D/.p5.md.tmp"
confere "limite (3 e frase)" "3|pendência não registrada: $D/p5.md" "$(roda "$D" p5 2)"

# 6. sem arquivo
novo vazio
confere "sem arquivo (2)" "2|" "$(roda "$D" p6 2)"

# 7. uso
confere "uso sem argumentos (2)" "2|" "$(roda)"
confere "limite não numérico (2)" "2|" "$(roda "$D" p6 abc)"
confere "slug com caminho (2)" "2|" "$(roda "$D" ../x 2)"
confere "diretório inexistente (2)" "2|" "$(roda "$BASE/nao-existe" p6 2)"

if [ "$falhas" -ne 0 ]; then echo "$falhas falha(s)"; exit 1; fi
echo "todos os testes passaram"
