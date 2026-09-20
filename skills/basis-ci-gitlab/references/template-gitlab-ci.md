# O template compartilhado de CI

Um template único, em `basis/iac/ci-templates`, arquivo
`templates/dagger-orchestrator.gitlab-ci.yml`. Todos os projetos herdam dele.

## Como o projeto herda

```yaml
include:
  - project: 'basis/iac/ci-templates'
    ref: <versão>
    file: 'templates/dagger-orchestrator.gitlab-ci.yml'
```

É o `.gitlab-ci.yml` inteiro de quase todos os projetos. A única exceção em uso acrescenta
um override:

```yaml
variables:
  DAGGER_MODULE: "."       # projeto com módulo Dagger local
```

**Pin o `ref`.** Herdar de `main` faz uma mudança no template atingir todos os projetos ao
mesmo tempo, sem janela. Os projetos divergem entre si — a deriva é esperada e gerenciável;
o que não é gerenciável é não ter versão.

## Variáveis do template

```yaml
variables:
  GIT_DEPTH: "0"                # histórico completo: o Sonar precisa de blame
  GIT_STRATEGY: clone
  DAGGER_MODULE: "github.com/BasisTI/daggerverse/orchestrator@<versão>"
  PIPELINE_CONFIG: "ci/pipeline.toml"
  CHECK_IMAGES_BUILD_BRANCH: "origin/develop"
```

Os dois que um projeto sobrescreve na prática são `DAGGER_MODULE` e `PIPELINE_CONFIG`.

`GIT_DEPTH: "0"` não é excesso de zelo: com clone raso o `git blame` fica incompleto e o SCM
Publisher do Sonar atribui código novo a quem não escreveu.

## Os stages e os jobs

```yaml
stages:
  - check
  - build
  - pre-prod
  - promote
```

| Job | Stage | `rules` — dispara em |
|---|---|---|
| `validate-pipeline-config` | check | MR que toca `ci/pipeline.toml` |
| `check-quality` | check | `$CI_MERGE_REQUEST_TARGET_BRANCH_NAME == 'develop'` |
| `publish-develop` | build | `$CI_COMMIT_BRANCH == 'develop'` |
| `check-images-ready` | pre-prod | MR develop→main **e** push em `main` |
| `promote-production` | promote | push em `main` |

**`check-quality` só roda com destino `develop`.** Uma MR de feature aberta direto para
`main` não passa por análise nenhuma — é o modo de falha mais silencioso da tabela.

## A tag CalVer

Uma linha no `before_script`, aplicada a todos os jobs:

```yaml
before_script:
  - 'export APP_VERSION="$(date +%Y.%m.%d).$CI_PIPELINE_IID"'
```

Resultado: `2026.08.17.42`.

**É `CI_PIPELINE_IID`, não `CI_PIPELINE_ID`.** O `IID` é o contador **por projeto** —
contíguo, começa em 1 em cada repositório. O `ID` é global da instância, não-contíguo.
Confundir os dois leva a raciocinar errado sobre unicidade de tag entre projetos, e a
escrever regex de Image Updater com a quantidade errada de dígitos.

A montagem é em bash, no GitLab. O Dagger recebe a string pronta em `--version`. Procurar
essa lógica dentro do código Go é perda de tempo.

O ciclo completo de tags:

| Tag | Quando |
|---|---|
| `sha-<commit>` | durante o build, para rastreio |
| `<calver>` | na publicação em `develop` |
| `production-<calver>` | na promoção para `main` |

## Variáveis que a pipeline consome

**Não declare estas no projeto.** No GitLab da Basis elas vivem em escopo global, e todo
projeto as herda:

| Variável | Para |
|---|---|
| `EXTERNAL_REGISTRY_URL` | registry de imagens |
| `EXTERNAL_REGISTRY_USER` | " |
| `EXTERNAL_REGISTRY_PASSWORD` | " (mascarada) |
| `SONAR_HOST` | servidor do SonarQube |
| `SONAR_TOKEN` | token de **análise** (`sqa_`) |
| `SONAR_STG_HOST` | servidor do SonarQube de staging |
| `SONAR_STG_TOKEN` | token de análise de staging |
| `GITLAB_STATUS_TOKEN` | commit status e push do bump de versão |
| `NEXUS_USER` | dependências |
| `NEXUS_PASSWORD` | " |
| `NVD_API_KEY` | chave da API do NVD, usada pelo Dependency-Check (mascarada) |

O runner precisa da tag `dagger` — é onde o binário está pré-instalado.

Conferir presença sem revelar valor:

```bash
glab variable list        # SÓ as do projeto
glab variable list -g     # SÓ as do grupo
```

**Nenhum dos dois enxerga variável de escopo global**, então uma saída vazia não significa
que a variável falta. Se a pipeline autentica no registry e fala com o Sonar, elas existem.
Para confirmar de verdade é preciso permissão no escopo onde estão declaradas, ou observar o
comportamento do job. O `scripts/estado-pipeline.sh` já trata a listagem vazia dessa forma e
não a reporta como ausência.

## A permissão do `include: project:`

**O GitLab resolve o `include` com a permissão do usuário que disparou a pipeline** — não do
runner, não de um token de serviço. Como `ci-templates` é privado dentro de grupos privados,
todo desenvolvedor que abre MR precisa de leitura nele.

Sem acesso, a pipeline não começa:

```
Project `basis/iac/ci-templates` not found or access denied!
Make sure any includes in the pipeline configuration are correctly defined.
```

A mensagem é deliberadamente ambígua — não revela se o projeto existe —, então parece erro
de digitação no caminho ou template removido. Antes de mexer no YAML, confira o acesso:

```bash
glab api "projects/<id-do-ci-templates>/members/all" | grep <usuário>
```

O sintoma é por pessoa: a MR de quem tem acesso roda, a de quem não tem falha no mesmo
commit.

## O que cada job de fato chama

Todos na mesma forma — o template é uma casca fina sobre `dagger call`:

```yaml
script:
  - >-
    dagger --progress plain call -m "$DAGGER_MODULE"
    --source . --config-path "$PIPELINE_CONFIG"
    check-quality
    --base-branch "origin/$CI_MERGE_REQUEST_TARGET_BRANCH_NAME"
    --commit-sha "$CI_COMMIT_SHA"
    --sonar-token env:SONAR_TOKEN
    --sonar-host "$SONAR_HOST"
    --gitlab-host "$CI_SERVER_URL"
    --gitlab-token env:GITLAB_STATUS_TOKEN
    --gitlab-project-id "$CI_PROJECT_ID"
    --gitlab-ref "$CI_COMMIT_REF_NAME"
    --merge-request-id "$CI_MERGE_REQUEST_IID"
    --merge-request-source-branch "$CI_MERGE_REQUEST_SOURCE_BRANCH_NAME"
    --merge-request-target-branch "$CI_MERGE_REQUEST_TARGET_BRANCH_NAME"
```

Os três últimos são o que transforma a análise em análise de **pull request** — sem eles o
Sonar analisa e não comenta na MR. Detalhe em `sonar-analise-e-quality-gate.md`.

Segredo sempre como `env:NOME`, nunca interpolado como string: a forma `env:` faz o Dagger
ler a variável de ambiente sem que o valor apareça no log de comando.

## O bump de versão e o `ci.skip`

Depois de publicar, o `publish-all` commita `Bump versão para <versão>` e empurra:

```
git push -o ci.skip ...
```

O objetivo é não disparar uma pipeline de branch duplicada pelo próprio commit de bump.

**O efeito colateral que assusta:** como `develop` é a branch de origem de uma MR
develop→main já aberta, o `ci.skip` suprime **também** a pipeline de merge request daquele
commit. O head da MR fica sem job nenhum, aparece como `skipped`, e **não bloqueia o merge**.

É por isso que `check-images-ready` roda em dois gatilhos. Na MR ele é frequentemente
suprimido; no push para `main` ele roda sempre, e é essa segunda execução que de fato garante
que as imagens existem antes do `promote`. A aparente redundância é a correção de um modo de
falha real.
