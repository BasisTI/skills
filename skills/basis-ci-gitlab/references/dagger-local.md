# Rodar a pipeline na sua máquina

A razão de a pipeline ser Dagger e não YAML: ela é um programa, e programas rodam fora do
CI. O ciclo "empurra commit, espera runner, lê log" deixa de ser a única forma de descobrir
que faltou uma vírgula.

## A invocação

```bash
dagger call -m github.com/BasisTI/daggerverse/orchestrator@<versão> \
  --source . --config-path ci/pipeline.toml \
  <função>
```

`-m` aponta o módulo. Num repositório com módulo Dagger local (o que declara
`DAGGER_MODULE: "."` no `.gitlab-ci.yml`), use `-m .`.

## As seis funções

| Função | O que faz | Roda local? |
|---|---|---|
| `validate` | Valida o `pipeline.toml` contra o schema | sim |
| `sonar-project-keys` | Lista as chaves de Sonar efetivas dos targets | sim |
| `check-quality` | Testes + análise Sonar dos targets alterados | **não** (ver limite) |
| `publish-all` | Builda e publica os targets alterados | sim, com registry alcançável |
| `check-images` | Confere se as imagens esperadas existem | sim, idem |
| `promote` | Copia imagem para a tag de produção | sim, idem |

**`validate` é a que paga a conta.** Custa segundos, não precisa de rede interna, e pega a
classe inteira de erro de configuração — chave desconhecida, `reactor` sem `module`,
`sonar-project-key` sem `sonar`, nome de imagem duplicado. Rodar antes de cada push elimina
o ciclo mais caro do fluxo.

```bash
dagger call -m github.com/BasisTI/daggerverse/orchestrator@<versão> \
  --source . --config-path ci/pipeline.toml validate
```

## O limite: DNS, não certificado

Chamar serviço interno do `dagger call` local falha assim:

```
Failed to query server version: Call to URL [https://<host-interno>/api/v2/analysis/version]
failed: (certificate_unknown) The certificate chain is not trusted
```

Parece cadeia de certificados. **É DNS.**

O engine do Dagger roda num contêiner que **não usa o resolvedor da VPN do host**. O mesmo
hostname resolve para IPs diferentes:

| Onde | Resolve para | O que responde |
|---|---|---|
| host (com VPN) | o servidor real | HTTP 401, certificado válido |
| dentro do engine | outra máquina na borda | HTTP 404, certificado self-signed |

O erro de certificado é consequência de estar falando com a máquina errada.

**Não troque certificado nem monte CA.** Verifique para onde o nome resolve nos dois lados
antes de qualquer coisa.

**Consequência prática:** a análise do Sonar só roda no runner, que está na rede interna.
Para tarefas administrativas do Sonar (criar projeto, binding, consultar API), chame a API
direto do host — ele resolve certo. Para a análise, empurre o commit.

## O ruído no fim do job

```
ERR cleanup failed msg="close dagger session" err="shutdown: do shutdown:
    Post http://dagger/shutdown: context deadline exceeded" duration=10.001271355s
Error: cleanup failed
ERROR: Job failed: exit status 1
```

Timeout de 10s no shutdown da sessão do CLI, cravado no limite. **Pode aparecer depois de o
trabalho ter terminado com sucesso** — já aconteceu num `promote-production` marcado
`failed` cuja imagem estava publicada e correta.

Antes de concluir que a lógica falhou, leia o log até o fim e procure a conclusão do
trabalho (`... DONE`, o `crane copy`, o push da imagem). Reexecutar é seguro — `promote` é
idempotente desde a 3.1.1 — mas reexecutar por diagnóstico errado gasta um ciclo à toa.

No mesmo log, `crane digest ... 404 MANIFEST_UNKNOWN` aparece em vermelho e **é o caminho
feliz**: é a checagem "essa tag já existe?" que o promote faz antes de copiar. 404 significa
"ainda não promovida, siga".

## Mexer num módulo local

Só o repositório com targets `type = "custom"` tem módulo próprio. Ele lê o mesmo
`ci/pipeline.toml` e expõe as mesmas funções do orchestrator, então o template roda sem
ajuste.

**Depois de mudar a assinatura de qualquer função exportada, rode `dagger develop`.** O
código gerado (`dagger.gen.go`) fica velho e o build falha com mensagem que aponta para o
lugar errado:

```
not enough arguments in call to (*X).Y
```

Parece erro de chamada no seu código; é o stub gerado desatualizado. Vale como reflexo:
mudou parâmetro de função exportada, `dagger develop` antes de compilar.

Ao rodar `dagger develop`, confira se o `engineVersion` do `dagger.json` não subiu junto —
já aconteceu de subir sozinho e entrar no commit sem intenção.

## Nota de shell

Os exemplos aqui são POSIX. Se o seu shell interativo é fish, laços com `for i in (seq ...)
... end` não funcionam quando o comando é executado por um agente — o ambiente de execução é
`sh`, não fish, e o erro é `parse error near 'end'`. Use `for i in $(seq 1 N); do ... done`.
