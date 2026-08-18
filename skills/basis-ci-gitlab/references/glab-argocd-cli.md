# Receitas de CLI: `glab`, `argocd`, `sonar`, `kubectl`

Comandos verificados em uso real. Onde há uma forma óbvia que não funciona, ela está
anotada — é o que economiza o ciclo perdido.

## `glab`

### Descobrir o contexto

```bash
glab config get host                        # host configurado
glab repo view -F json --jq '.id'           # id numérico do projeto
```

O id numérico é o que a API pede em `projects/:id`, e é uma das seis chaves do mapa de
identidade do projeto.

### Validar o YAML antes de disparar

```bash
glab ci lint
```

### Rodar a pipeline de uma MR

```bash
glab api -X POST "projects/:id/merge_requests/<iid>/pipelines"
```

**`glab ci run` não serve aqui.** Ele cria pipeline de **branch**, e ela nasce vazia — os
jobs de check têm `rules: if: $CI_PIPELINE_SOURCE == 'merge_request_event'` e nenhum deles
casa. O resultado é uma pipeline sem job, que parece "a CI está quebrada" e é só o gatilho
errado. É a armadilha mais provável, porque `glab ci run` é o comando que se tenta primeiro.

### Investigar uma pipeline

```bash
glab api "projects/:id/pipelines/<pipeline_id>/jobs"     # jobs e status
glab api "projects/:id/jobs/<job_id>/trace"              # log completo do job
```

O `trace` é texto puro. Para achar a causa num log longo, filtre pelo fim — o erro real
costuma estar antes do ruído de shutdown (ver `dagger-local.md`).

### Variáveis de CI

```bash
glab variable list        # do projeto
glab variable list -g     # do grupo
```

Lista **nomes**, não valores. Serve para confirmar que as seis variáveis exigidas pelo
template existem.

### Abrir MR com descrição longa

```bash
glab mr create \
  --source-branch TG-58 \
  --target-branch develop \
  --title "Corrigir configuração de volume no docker-compose - TG-58" \
  --description "$(cat <<'EOF'
## O que muda

...markdown...
EOF
)"
```

O heredoc com `'EOF'` entre aspas evita que `$`, crase e `!` da descrição sejam
interpretados pelo shell.

Lembre das flags do fluxo: **Delete Branch e Squash** na MR para `develop`; **sem Squash** na
MR de `develop` para `main`.

### Consulta por caminho, quando `:id` não serve

```bash
glab api "projects/basis%2F<repo>/merge_requests/<iid>"
```

O `/` do caminho vira `%2F`.

### Conferir acesso a um projeto

```bash
glab api "projects/<id>/members/all" | grep <usuário>
```

É o diagnóstico de `Project not found or access denied` no `include:` — a mensagem é
ambígua de propósito e não distingue "não existe" de "sem permissão".

## `argocd`

```bash
argocd login argocd.basis.com.br --sso
```

Abre uma janela do browser para autenticar no Keycloak. **Um agente não completa esse
login** — se a sessão expirou, peça à pessoa que rode o comando; não tente contornar.

```bash
argocd app sync <app>-<env>
```

O resto do ciclo de vida da Application é `basis-k8s-deploy`.

## `sonar`

CLI v1.4.0. **O comando é `sonar auth login`** — subcomando, não um executável
`sonar-auth-login`.

```bash
sonar auth login                 # autentica
sonar auth status                # confere sem tentar adivinhar
sonar analyze --file <arquivo>   # analisa um arquivo contra as regras
sonar api GET "api/<endpoint>"   # chamada autenticada à Web API
```

`sonar auth status` é o que um agente deve rodar antes de assumir que há sessão — é barato e
evita interpretar um 401 como problema de configuração.

Endpoints úteis para os diagnósticos de `sonar-analise-e-quality-gate.md`:

```bash
sonar api GET "api/project_pull_requests/list?project=<chave>"   # a MR virou PR analysis?
sonar api GET "api/project_analyses/search?project=<chave>"      # havia análise anterior?
```

## `kubectl`

Só um uso pertence a esta skill — o resto é `basis-k8s-deploy`.

Quando a imagem foi promovida e a versão não subiu em produção, o log do Image Updater diz
se ele viu a tag:

```bash
kubectl -n argocd logs deploy/argocd-image-updater-controller \
  -l app.kubernetes.io/name=argocd-image-updater --tail=100
```

No contexto de produção. Se ele não menciona a aplicação, o problema está antes: ou a tag
não bate com o `allow-tags` da Application, ou o `promote` não rodou.

A convenção viva de tag é `production-\d{4}\.\d{2}\.\d{2}[-.]\d+`. Um projeto legado usa
`producao-[0-9.]+`, em português — não sirva de modelo.

## Nota de shell

Os exemplos são POSIX. Laço em fish (`for i in (seq 1 60) ... end`) falha com `parse error
near 'end'` quando o comando é executado por um agente, porque o ambiente de execução é `sh`
mesmo quando o shell interativo é fish. Use `for i in $(seq 1 60); do ... done`.
