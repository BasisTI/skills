#!/bin/bash
# Testa espera-argocd-sync.sh com um `kubectl` falso no PATH (nada toca um cluster)
# e, nos casos de --repo, com repositórios git temporários.
# Uso: tests/espera-argocd-sync.test.sh   (também: zsh -c 'bash tests/espera-argocd-sync.test.sh')
#
# Os arquivos ficam num diretório criado uma vez por mktemp -d; a limpeza roda só no
# fim (trap EXIT) e só se o caminho casar com o padrão do mktemp. Entre os casos os
# arquivos são recriados por cima, nunca apagados. Nenhum processo é morto por nome:
# os sinais vão só ao PID que o próprio teste criou.
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$AQUI/../espera-argocd-sync.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/espera-argocd-sync.XXXXXX")"
# shellcheck disable=SC2064  # expande agora de propósito: o caminho validado fica fixo no trap
case "$TMP" in
  */espera-argocd-sync.??????) trap "rm -rf -- '$TMP'" EXIT ;;
  *) echo "diretório temporário fora do padrão do mktemp: $TMP" >&2; exit 1 ;;
esac
mkdir -p "$TMP/bin" "$TMP/f"

# kubectl falso: devolve $FAKE/app.<n>.json (n = nº da chamada, se existir) ou $FAKE/app.json;
# registra os argumentos em $FAKE/../args. app.erro: falha com a mensagem do arquivo.
cat > "$TMP/bin/kubectl" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE/../args"
if [ -e "$FAKE/app.erro" ]; then cat "$FAKE/app.erro" >&2; exit 1; fi
n=$(( $(cat "$FAKE/../n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE/../n"
if [ -e "$FAKE/app.$n.json" ]; then cat "$FAKE/app.$n.json"; else cat "$FAKE/app.json"; fi
FAKE
chmod +x "$TMP/bin/kubectl"

falhas=0
zerar() { : > "$TMP/n"; }                       # reinicia o contador de chamadas do kubectl falso
limpar_seq() { # esvazia as respostas numeradas: sobrescreve com a resposta padrão (sem rm)
  local n
  for n in 1 2 3 4 5 6 7 8 9 10; do [ ! -e "$TMP/f/app.$n.json" ] || cp "$TMP/f/app.json" "$TMP/f/app.$n.json"; done
}
caso() { # nome saida_esperada trecho_da_ultima_linha [args...]
  local nome="$1" esperado="$2" trecho="$3"; shift 3
  local codigo=0
  zerar
  PATH="$TMP/bin:$PATH" FAKE="$TMP/f" INTERVALO=1 CARENCIA_DEGRADED=2 \
    bash "$SCRIPT" "$@" >"$TMP/saida" 2>&1 || codigo=$?
  local ultima; ultima=$(tail -n 1 "$TMP/saida")
  if [ "$codigo" = "$esperado" ] && [[ "$ultima" == *"$trecho"* ]]; then
    echo "ok   $nome (saída $codigo)"
  else
    echo "FALHA $nome: saída $codigo (esperado $esperado), última linha: $ultima"; cat "$TMP/saida"
    falhas=$((falhas + 1))
  fi
}
caso_uso() { # nome trecho [args...]: sai 64 e o trecho aparece na saída (antes da linha de uso)
  local nome="$1" trecho="$2"; shift 2
  local codigo=0
  zerar
  PATH="$TMP/bin:$PATH" FAKE="$TMP/f" INTERVALO=1 bash "$SCRIPT" "$@" >"$TMP/saida" 2>&1 || codigo=$?
  if [ "$codigo" = 64 ] && grep -qF -- "$trecho" "$TMP/saida"; then
    echo "ok   $nome (saída 64)"
  else
    echo "FALHA $nome: saída $codigo, esperado 64 com \"$trecho\""; cat "$TMP/saida"; falhas=$((falhas + 1))
  fi
}
app() { printf '{"kind":"Application","status":%s}' "$1" > "$TMP/f/app.json"; limpar_seq; }
app_n() { printf '{"kind":"Application","status":%s}' "$2" > "$TMP/f/app.$1.json"; }
st() { # sync revisão saúde [operationState-json]
  printf '{"sync":{"status":"%s","revision":"%s"},"health":{"status":"%s"}%s}' "$1" "$2" "$3" "${4:+,\"operationState\":$4}"
}
BASE=(--context eks-teste --app portal-prod)
R=abc1234def5678

app "$(st Synced $R Healthy)"
caso verde-na-revisao 0 "sinal ok sync Synced saude Healthy" "${BASE[@]}" --revisao abc1234 --limite-s 5
caso verde-sem-revisao 0 "sinal ok" "${BASE[@]}" --limite-s 5
caso revisao-completa 0 "sinal ok" "${BASE[@]}" --revisao abc1234def5678 --limite-s 5
caso revisao-maiuscula 0 "sinal ok" "${BASE[@]}" --revisao ABC1234 --limite-s 5

if grep -q -- '--context eks-teste -n argocd --request-timeout=20s get application.argoproj.io portal-prod -o json' "$TMP/args"; then
  echo "ok   argumentos do kubectl (array, --request-timeout)"
else
  echo "FALHA argumentos do kubectl: $(head -1 "$TMP/args")"; falhas=$((falhas + 1))
fi

# 2: Synced+Healthy em outra revisão (sem --repo vale igualdade), até o limite
caso outra-revisao 2 "sinal revisao-diferente" "${BASE[@]}" --revisao 9999999 --limite-s 2

# ainda Running não conta como pronto; na 2ª leitura termina
app_n 1 "$(st Synced $R Healthy '{"phase":"Running"}')"
app_n 2 "$(st Synced $R Healthy '{"phase":"Succeeded"}')"
caso fase-running-espera 0 "sinal ok" "${BASE[@]}" --revisao abc1234 --limite-s 10

# 1: Degraded na revisão esperada além da carência
app "$(st Synced $R Degraded)"
caso degraded 1 "sinal degradado sync Synced saude Degraded" "${BASE[@]}" --revisao abc1234 --limite-s 30
# carência respeitada: Degraded por menos que a carência e depois Healthy → 0
app_n 1 "$(st Synced $R Degraded)"; app_n 2 "$(st Synced $R Degraded)"; app_n 3 "$(st Synced $R Healthy)"
caso carencia-respeitada 0 "sinal ok" "${BASE[@]}" --revisao abc1234 --limite-s 30
# o relógio do Degraded reinicia quando a saúde melhora e volta a piorar
app_n 1 "$(st Synced $R Degraded)"; app_n 2 "$(st Synced $R Degraded)"; app_n 3 "$(st Synced $R Progressing)"
app_n 4 "$(st Synced $R Degraded)"; app_n 5 "$(st Synced $R Healthy)"
caso carencia-reinicia 0 "sinal ok" "${BASE[@]}" --revisao abc1234 --limite-s 30
app "$(st Synced $R Degraded)"

# S2a: Degraded numa revisão ANTIGA com --revisao nova: continua esperando (limite, não sinal 1)
app "$(st Synced 1111111aaaa Degraded)"
caso degraded-revisao-antiga 3 "sinal limite" "${BASE[@]}" --revisao abc1234 --limite-s 5

# 1: operação falhou na revisão esperada (fonte única, várias fontes, Error sem syncResult)
app "$(st OutOfSync $R Progressing "{\"phase\":\"Failed\",\"syncResult\":{\"revision\":\"$R\"}}")"
caso operacao-falhou 1 "sinal falhou" "${BASE[@]}" --revisao abc1234 --limite-s 30
app "$(st OutOfSync $R Progressing "{\"phase\":\"Failed\",\"syncResult\":{\"revisions\":[\"2222222bb\",\"$R\"]}}")"
caso operacao-falhou-multi 1 "sinal falhou" "${BASE[@]}" --revisao abc1234 --limite-s 30
app "$(st OutOfSync $R Progressing '{"phase":"Error"}')"
caso error-sem-syncresult 1 "sinal falhou" "${BASE[@]}" --revisao abc1234 --limite-s 30
# S2b: operação falhada de revisão ANTIGA continua esperando (e depois fica verde)
app "$(st Synced $R Healthy)"
app_n 1 "$(st OutOfSync 1111111aaaa Progressing '{"phase":"Failed","syncResult":{"revision":"1111111aaaa"}}')"
caso falha-antiga-com-revisao 0 "sinal ok" "${BASE[@]}" --revisao abc1234 --limite-s 30
app "$(st OutOfSync 1111111aaaa Progressing '{"phase":"Failed","syncResult":{"revisions":["1111111aaaa"]}}')"
caso falha-antiga-multi 3 "sinal limite" "${BASE[@]}" --revisao abc1234 --limite-s 3
# sem --revisao: Failed de revisão que não é a atual continua esperando; da atual vale
app "$(st OutOfSync $R Progressing '{"phase":"Failed","syncResult":{"revision":"1111111aaaa"}}')"
caso falha-antiga-sem-revisao 3 "sinal limite" "${BASE[@]}" --limite-s 3
app "$(st OutOfSync $R Progressing "{\"phase\":\"Failed\",\"syncResult\":{\"revision\":\"$R\"}}")"
caso falha-atual-sem-revisao 1 "sinal falhou" "${BASE[@]}" --limite-s 30

# 3: OutOfSync/Progressing até o limite
app "$(st OutOfSync $R Progressing)"
caso limite 3 "sinal limite sync OutOfSync saude Progressing" "${BASE[@]}" --revisao abc1234 --limite-s 2

# campos ausentes: sem erro do jq, cai no limite
printf '{"kind":"Application"}' > "$TMP/f/app.json"; limpar_seq
caso campos-ausentes 3 "sinal limite sync Desconhecido saude Desconhecido" "${BASE[@]}" --limite-s 2
if grep -q 'jq: error' "$TMP/saida"; then echo "FALHA campos-ausentes: erro do jq"; falhas=$((falhas + 1)); fi

# várias fontes: revisão em status.sync.revisions
app '{"sync":{"status":"Synced","revisions":["1111111aaa","abc1234def5678"]},"health":{"status":"Healthy"}}'
caso multiplas-fontes 0 "sinal ok" "${BASE[@]}" --revisao abc1234 --limite-s 5

# falha do jq dentro do contrato: HTML, JSON truncado e Failure → 64 com linha final
for lixo in '<html>502</html>' '{"kind":"Application","status":{"sync":' '{"kind":"Status","status":"Failure"}'; do
  printf '%s' "$lixo" > "$TMP/f/app.json"; limpar_seq
  caso leitura-invalida 64 "sinal ilegivel" "${BASE[@]}" --limite-s 30
done

# app inexistente: 64 na primeira leitura, com a causa e a linha final
echo 'Error from server (NotFound): applications.argoproj.io "portal-prod" not found' > "$TMP/f/app.erro"
caso app-inexistente 64 "sinal ilegivel" "${BASE[@]}" --limite-s 30
if grep -q 'inexistente' "$TMP/saida"; then echo "ok   app-inexistente: mensagem"; else echo "FALHA app-inexistente: mensagem"; cat "$TMP/saida"; falhas=$((falhas + 1)); fi
# kubectl falha de outro jeito 5 vezes: 64
echo 'Unable to connect to the server' > "$TMP/f/app.erro"
caso app-ilegivel 64 "sinal ilegivel" "${BASE[@]}" --limite-s 30
mv "$TMP/f/app.erro" "$TMP/f/app.erro.usado"   # desativa o erro sem apagar

# falha intermitente zera o contador (4 falhas, 1 ok, 4 falhas, ok → 0)
printf '<html>' > "$TMP/f/app.json"; limpar_seq
for n in 1 2 3 4 6 7 8 9; do printf '<html>' > "$TMP/f/app.$n.json"; done
app_n 5 "$(st OutOfSync $R Progressing)"; app_n 10 "$(st Synced $R Healthy)"
caso falha-intermitente 0 "sinal ok" "${BASE[@]}" --limite-s 60
app "$(st OutOfSync $R Progressing)"

# o limite vale com intervalo grande (sleep limitado ao restante)
zerar; t0=$SECONDS; codigo=0
PATH="$TMP/bin:$PATH" FAKE="$TMP/f" INTERVALO=3600 timeout 20 bash "$SCRIPT" "${BASE[@]}" --limite-s 2 >"$TMP/saida" 2>&1 || codigo=$?
if [ "$codigo" = 3 ] && [ $((SECONDS - t0)) -lt 10 ]; then echo "ok   intervalo-maior-que-limite (saída 3 em $((SECONDS - t0))s)"; else echo "FALHA intervalo-maior-que-limite: $codigo"; cat "$TMP/saida"; falhas=$((falhas + 1)); fi

# SIGTERM/SIGINT/SIGHUP: linha final e código 143/130/129, sem esperar o intervalo
for par in TERM:143 INT:130 HUP:129; do
  sig="${par%%:*}"; esperado="${par##*:}"; zerar
  set -m   # sem isso o bash lança o job de fundo com SIGINT ignorado
  PATH="$TMP/bin:$PATH" FAKE="$TMP/f" INTERVALO=300 bash "$SCRIPT" "${BASE[@]}" --limite-s 600 >"$TMP/saida" 2>&1 &
  pid=$!
  set +m
  sleep 1
  kill -"$sig" "$pid"
  codigo=0; wait "$pid" || codigo=$?
  if [ "$codigo" = "$esperado" ] && [[ "$(tail -n 1 "$TMP/saida")" == *"sinal interrompido"* ]]; then echo "ok   sinal-$sig (saída $codigo)"; else echo "FALHA sinal-$sig: $codigo"; cat "$TMP/saida"; falhas=$((falhas + 1)); fi
done

# --repo: o app avançou para um commit posterior ao esperado → 0; sem --repo → 2
G="$TMP/git"; mkdir -p "$G"
git -c init.defaultBranch=main init -q --bare "$G/origem.git"
git -c init.defaultBranch=main init -q "$G/clone"
git -C "$G/clone" remote add origin "$G/origem.git"
gc() { git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$2"; }
gc "$G/clone" c1; gc "$G/clone" c2; gc "$G/clone" c3
git -C "$G/clone" push -q origin HEAD:main
SHA1=$(git -C "$G/clone" rev-parse HEAD~2); SHA3=$(git -C "$G/clone" rev-parse HEAD)
app "$(st Synced "$SHA3" Healthy)"
caso repo-contem 0 "sinal ok" "${BASE[@]}" --revisao "$SHA1" --repo "$G/clone" --limite-s 5
caso sem-repo-igualdade 2 "sinal revisao-diferente" "${BASE[@]}" --revisao "$SHA1" --limite-s 2
# commit que NÃO é ancestral do app: espera o limite
git -C "$G/clone" checkout -q -b lateral HEAD~2; gc "$G/clone" lateral; SHAL=$(git -C "$G/clone" rev-parse HEAD)
git -C "$G/clone" checkout -q main
caso repo-nao-contem 2 "sinal revisao-diferente" "${BASE[@]}" --revisao "$SHAL" --repo "$G/clone" --limite-s 2
# commits novos só no remoto: o script faz git fetch e reconhece
git -c init.defaultBranch=main clone -q "$G/origem.git" "$G/outro"
gc "$G/outro" c4; gc "$G/outro" c5
git -C "$G/outro" push -q origin HEAD:main
SHA4=$(git -C "$G/outro" rev-parse HEAD~1); SHA5=$(git -C "$G/outro" rev-parse HEAD)
app "$(st Synced "$SHA5" Healthy)"
caso repo-com-fetch 0 "sinal ok" "${BASE[@]}" --revisao "$SHA4" --repo "$G/clone" --limite-s 10
# Degraded numa revisão que contém a esperada vale como sinal 1
app "$(st Synced "$SHA5" Degraded)"
caso repo-degraded-posterior 1 "sinal degradado" "${BASE[@]}" --revisao "$SHA4" --repo "$G/clone" --limite-s 30
# --repo inválido e --repo sem --revisao: 64
caso repo-invalido 64 "não é um clone git" "${BASE[@]}" --revisao "$SHA4" --repo "$TMP/f"
caso repo-sem-revisao 64 "--repo só faz sentido" "${BASE[@]}" --repo "$G/clone"

# 64: uso
caso_uso sem-app "uso:" --context x
caso_uso limite-invalido "--limite-s deve ser" "${BASE[@]}" --limite-s abc
caso_uso limite-gigante "--limite-s deve ser" "${BASE[@]}" --limite-s 99999999999999999999
caso revisao-invalida 64 "SHA hexadecimal" "${BASE[@]}" --revisao main --limite-s 2
caso_uso flag-desconhecida "uso:" "${BASE[@]}" --foo
caso_uso flag-sem-valor "exige um valor" "${BASE[@]}" --revisao
caso_uso flag-valor-vazio "exige um valor" "${BASE[@]}" --revisao ""
caso_uso app-com-traco "--app inválido" --context x --app -o=yaml
codigo=0
PATH="$TMP/bin:$PATH" FAKE="$TMP/f" INTERVALO=0 bash "$SCRIPT" "${BASE[@]}" --limite-s 2 >"$TMP/saida" 2>&1 || codigo=$?
if [ "$codigo" = 64 ] && grep -q "INTERVALO" "$TMP/saida"; then echo "ok   intervalo-zero (saída 64)"; else echo "FALHA intervalo-zero: $codigo"; falhas=$((falhas + 1)); fi

# 64: falta jq no PATH
codigo=0
PATH="$TMP/bin" /bin/bash "$SCRIPT" "${BASE[@]}" >"$TMP/saida" 2>&1 || codigo=$?
if [ "$codigo" = 64 ] && grep -q "falta .jq." "$TMP/saida"; then echo "ok   sem-jq (saída 64)"; else echo "FALHA sem-jq: $codigo"; cat "$TMP/saida"; falhas=$((falhas + 1)); fi

if [ "$falhas" = 0 ]; then echo "todos os casos passaram"; else echo "$falhas caso(s) falharam"; exit 1; fi
