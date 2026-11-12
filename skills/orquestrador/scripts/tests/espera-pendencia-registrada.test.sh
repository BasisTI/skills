#!/bin/bash
# Testes de espera-pendencia-registrada.sh: simulam o daemon com um processo de
# fundo que escreve .registrada.json ou .erro.txt. Sem `orq`, sem agente real.
# Uso: bash espera-pendencia-registrada.test.sh   (ou zsh -c 'bash ...')
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$AQUI/../espera-pendencia-registrada.sh"
BASE="$(mktemp -d "${TMPDIR:-/tmp}/espera-pend.XXXXXX")"
# Remove só o diretório criado acima (o valor do mktemp entra literal no trap).
# shellcheck disable=SC2064  # expandir agora é intencional: caminho literal
case "$BASE" in
  */espera-pend.??????) trap "rm -rf -- '$BASE'" EXIT ;;
  *) echo "mktemp inesperado: $BASE" >&2; exit 2 ;;
esac
falhas=0

confere() { # nome esperado obtido
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FALHA $1: esperado [$2], obtido [$3]"; falhas=$((falhas + 1)); fi
}
contem() { # nome trecho arquivo
  if grep -qF -- "$2" "$3"; then echo "ok   $1"; else echo "FALHA $1: [$2] não aparece em $3: $(cat "$3")"; falhas=$((falhas + 1)); fi
}
roda() { # imprime "<codigo>|<ultima linha do stdout>"; saídas em $BASE/out e $BASE/err
  local cod=0
  "$SCRIPT" "$@" >"$BASE/out" 2>"$BASE/err" || cod=$?
  echo "$cod|$(tail -n 1 "$BASE/out")"
}
novo() { D="$BASE/$1/TG-9/pendencias"; mkdir -p "$D"; } # forma do coordenador

# 1. registrada: arquivo .tmp é movido e o JSON é lido
novo registrada
echo x >"$D/.p1.md.tmp"
( sleep 1; echo '{"id":"TG-9#P1","chave":"TG-9","url":"http://x/p1"}' >"$D/p1.registrada.json" ) &
confere "registrada (0 e linha final)" "0|pendência registrada: id=TG-9#P1 chave=TG-9 url=http://x/p1" "$(roda "$D" p1 10)"
confere "registrada: .tmp virou .md" "sim" "$([ -e "$D/p1.md" ] && [ ! -e "$D/.p1.md.tmp" ] && echo sim || echo não)"
wait

# 2. campos ausentes não derrubam (jq com // valor)
novo parcial
echo x >"$D/p2.md"
echo '{"id":7}' >"$D/p2.registrada.json"
confere "registrada parcial" "0|pendência registrada: id=7 chave=? url=?" "$(roda "$D" p2 5)"

# 3. erro novo: conteúdo e saída 1
novo erro
echo x >"$D/.p3.md.tmp"
( sleep 1; echo 'linha 4: falta Contexto' >"$D/p3.erro.txt" ) &
confere "erro (1 e linha final)" "1|pendência recusada: $D/p3.md" "$(roda "$D" p3 10)"
confere "erro: conteúdo impresso" "linha 4: falta Contexto" "$(head -n 1 "$BASE/out")"
wait

# 4. erro de tentativa anterior seguido de sucesso: vale o sucesso
novo reenvio
echo 'erro velho' >"$D/p4.erro.txt"
echo x >"$D/.p4.md.tmp"
( sleep 1; echo '{"id":"P4","chave":"K","url":"u"}' >"$D/p4.registrada.json" ) &
confere "erro velho + sucesso" "0|pendência registrada: id=P4 chave=K url=u" "$(roda "$D" p4 10)"
wait

# 5. reenvio recusado com o MESMO texto: o daemon não regrava o erro; sai 1, não 3
novo mesmoerro
echo 'portal/316 não está em nenhuma onda' >"$D/p5.erro.txt"
echo x >"$D/.p5.md.tmp"
confere "mesmo erro sai 1 no limite" "1|pendência recusada: $D/p5.md" "$(roda "$D" p5 3)"
confere "mesmo erro: texto impresso" "portal/316 não está em nenhuma onda" "$(head -n 1 "$BASE/out")"
# editado no lugar, sem .tmp, mesmo erro
echo y >"$D/p5.md"
confere "mesmo erro, editado no lugar" "1|pendência recusada: $D/p5.md" "$(roda "$D" p5 3)"

# 6. erro velho com texto diferente do novo: sai 1 logo, com o texto novo
novo erronovo
echo 'erro A' >"$D/p6.erro.txt"
echo x >"$D/.p6.md.tmp"
( sleep 1; echo 'erro B' >"$D/p6.erro.txt" ) &
roda "$D" p6 10 >/dev/null
confere "erro mudou: texto novo" "erro B" "$(head -n 1 "$BASE/out")"
wait

# 7. limite esgotado
novo limite
echo x >"$D/.p7.md.tmp"
confere "limite (3 e frase)" "3|pendência não registrada: $D/p7.md" "$(roda "$D" p7 2)"

# 8. sem arquivo
novo vazio
confere "sem arquivo (2)" "2|" "$(roda "$D" p8 2)"
contem "sem arquivo: mensagem" "nem " "$BASE/err"

# 9. uso, limite e diretório
confere "sem argumentos (2)" "2|" "$(roda)"
contem "sem argumentos: mensagem" "uso:" "$BASE/err"
confere "limite não numérico (2)" "2|" "$(roda "$D" p8 abc)"
contem "limite não numérico: mensagem" "limite_s" "$BASE/err"
confere "limite acima do teto (2)" "2|" "$(roda "$D" p8 7201)"
contem "limite acima do teto: mensagem" "0 a 7200" "$BASE/err"
confere "limite gigante (2, sem laço infinito)" "2|" "$(roda "$D" p8 99999999999999999999)"
confere "diretório inexistente (2)" "2|" "$(roda "$BASE/nao-existe/TG-9/pendencias" p8 2)"
contem "diretório inexistente: mensagem" "diretório inexistente" "$BASE/err"

# 10. slug fora da regra do daemon: saída 2 imediata
echo x >"$D/.ok.md.tmp"
for s in Decisao-YAML decisao.yaml "decisao yaml" -decisao _x ../x p1.md "$(printf 'a%.0s' $(seq 65))"; do
  confere "slug '${s:0:20}' (2)" "2|" "$(roda "$D" "$s" 5)"
  contem "slug '${s:0:20}': mensagem" "slug inválido" "$BASE/err"
done
confere "slug de 64 vale (3: sem daemon)" "3|pendência não registrada: $D/$(printf 'a%.0s' $(seq 64)).md" "$(printf 'x' >"$D/.$(printf 'a%.0s' $(seq 64)).md.tmp"; roda "$D" "$(printf 'a%.0s' $(seq 64))" 0)"

# 11. forma do caminho: fora dela, saída 2 imediata com a regra
for ruim in "proj/IAC-PROD/pendencias" "proj/TG-9/rodada/pendencias" "proj/TG-0/pendencias" "proj/TG-9/outra" \
            "proj/TG-9/implementacao/r1/extra/pendencias" "proj/TG-9/implementacao/pendencias"; do
  mkdir -p "$BASE/forma/$ruim"
  echo x >"$BASE/forma/$ruim/.f.md.tmp"
  confere "pasta '$ruim' (2)" "2|" "$(roda "$BASE/forma/$ruim" f 5)"
  contem "pasta '$ruim': mensagem" "pasta fora da forma" "$BASE/err"
done
for boa in "proj/TG-9/pendencias" "proj/TG-9/implementacao/r1/pendencias" "proj/TG-9/revisao/r2/pendencias"; do
  mkdir -p "$BASE/boa/$boa"
  echo x >"$BASE/boa/$boa/.f.md.tmp"
  confere "pasta '$boa' vale (3: sem daemon)" "3|pendência não registrada: $BASE/boa/$boa/f.md" "$(roda "$BASE/boa/$boa" f 0)"
done
# caminho relativo também é conferido
novo rel
echo x >"$D/.r.md.tmp"
confere "caminho relativo vale" "pendência não registrada: $D/r.md" "$(cd "$D/.." && "$SCRIPT" pendencias r 0 2>/dev/null || true)"

# 12. .registrada.json ilegível: saída 2 com mensagem, não 0 vazio
for conteudo in '' 'não é json' '[1,2]'; do
  novo ilegivel
  echo x >"$D/i.md"
  printf '%s' "$conteudo" >"$D/i.registrada.json"
  confere "registrada ilegível '$conteudo' (2)" "2|pendência registrada, mas $D/i.registrada.json está ilegível: leia-o à mão" "$(roda "$D" i 3)"
done

# 13. mv que falha (pasta sem escrita): saída 2, não 1
novo semescrita
echo x >"$D/.m.md.tmp"
chmod a-w "$D"
resultado="$(roda "$D" m 3)"
chmod u+w "$D"
if [ "$(id -u)" -eq 0 ]; then echo "pulado: mv falho (root ignora permissão)"; else confere "mv falho vira 2" "2" "${resultado%%|*}"; fi

if [ "$falhas" -ne 0 ]; then echo "$falhas falha(s)"; exit 1; fi
echo "todos os testes passaram"
