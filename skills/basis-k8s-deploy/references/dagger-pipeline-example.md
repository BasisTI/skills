# Dagger pipeline (Go) na Basis

Padrão Basis pra CI: pipelines em Go via [Dagger](https://dagger.io), executadas em GitLab CI. Daggerverse modules da Basis (`maven`, `uv`, `npm`, `orchestrator-utils`) cobrem 90% dos casos.

## Estrutura do projeto

```
<app>/
├── ci/
│   ├── dagger.json
│   ├── go.mod
│   ├── go.sum
│   └── main.go              # módulo Dagger do projeto
├── .gitlab-ci.yml           # invoca os Dagger functions
├── pom.xml                  # ou outra build config
└── ...código...
```

## Funções típicas em `main.go`

Estrutura padrão de um app Maven multi-módulo:

```go
package main

import (
    "context"
    "dagger/<app>/internal/dagger"
    "fmt"
    "time"

    "github.com/BasisTI/daggerverse/gitlabci"
    "github.com/BasisTI/daggerverse/pipeline"
)

type <App> struct{}

const group = "<app>"
const mavenImage = "maven:3.9.11-eclipse-temurin-25-alpine"

// PublishAll: build + push de todas as imagens em um único reactor Maven
func (m *<App>) PublishAll(
    ctx context.Context,
    // +defaultPath="."
    source *dagger.Directory,
    commitSha string,
    version string,                    // CalVer YYYY.MM.DD.<pipelineId>
    // +default="basis-registry.basis.com.br"
    registry string,
    registryUser string,
    registryPassword *dagger.Secret,
    // +optional
    gitRemoteUrl string,
    // +optional +default="develop"
    gitBranch string,
) (string, error) {
    src := dag.Directory().WithDirectory("/", source, dagger.DirectoryWithDirectoryOpts{
        Exclude: []string{"**/target/"},
    })

    password, err := registryPassword.Plaintext(ctx)
    if err != nil {
        return "", fmt.Errorf("get registry password: %w", err)
    }

    labels := fmt.Sprintf(
        "org.opencontainers.image.revision=%s,org.opencontainers.image.version=%s,org.opencontainers.image.created=%s",
        commitSha, version, time.Now().UTC().Format(time.RFC3339))

    mv := dag.Maven(dagger.MavenOpts{BuildImage: mavenImage})
    container := mv.Container().
        WithDirectory("/app", src).
        WithWorkdir("/app")

    mvnBase := []string{"mvn", "--batch-mode", "--errors"}

    // Bump da versão direto no pom (versions:set funciona em multi-módulo)
    bumped := container.
        WithExec(append(mvnBase, "versions:set",
            "-DnewVersion="+version, "-DgenerateBackupPoms=false"))

    // Build + push
    built := bumped.
        WithExec(append(mvnBase, "clean", "install", "-DskipTests")).
        WithExec(append(mvnBase,
            "jib:build",
            "-Djib.to.auth.username="+registryUser,
            "-Djib.to.auth.password="+password,
            "-Djib.to.tags="+version+",sha-"+commitSha,
            "-Djib.container.labels="+labels,
        ))

    if _, err := built.Sync(ctx); err != nil {
        return "", err
    }

    published := fmt.Sprintf("%s/%s/core:%s,%s/%s/ingress:%s",
        registry, group, version, registry, group, version)

    // Bump-and-commit dos pom.xml com nova versão
    if gitRemoteUrl != "" {
        versionFiles := []string{
            "pom.xml",
            "<app>-domain/pom.xml",
            "<app>-core/pom.xml",
            "<app>-ingress/pom.xml",
        }
        bumpedSource := bumped.Directory("/app")
        commitMsg := fmt.Sprintf("Bump versão para %s", version)
        if err := dag.OrchestratorUtils().CommitAndPush(
            ctx, bumpedSource, versionFiles, commitMsg, gitBranch, gitRemoteUrl,
        ); err != nil {
            return "", fmt.Errorf("commit bumped versions: %w", err)
        }
    }

    return published, nil
}
```

## Gotchas resolvidos

### 1. `BumpAndCommitVersions` não funciona em Maven multi-módulo

`OrchestratorUtils.BumpAndCommitVersions` usa um `bumpPomVersion` que escreve `<version>` direto no pom — falha em sub-módulos que herdam versão do `<parent>` (não há `<version>` próprio pra alterar).

**Solução**: usar `mvn versions:set -DnewVersion=...` (Maven entende multi-módulo nativamente), depois extrair o diretório bumped e chamar `CommitAndPush` separado.

### 2. `[skip ci]` no commit message

`CommitAndPush` já adiciona o prefixo `[skip ci]` automaticamente — NÃO incluir manualmente no `commitMsg`, senão fica duplicado.

### 3. Quality check em sub-módulo precisa do reactor inteiro

```go
mv := dag.Maven(dagger.MavenOpts{
    BuildImage:   mavenImage,
    ExtraOptions: []string{"-pl", mavenSubmodule(module), "-am"},
})
```

`-pl <modulo> -am` roda só o módulo + dependências (also-make). Sem `-am`, falha porque `<app>-core` não acha `<app>-domain`.

E em `GetSubDirectory`: passar o repositório INTEIRO (não só o subdir do módulo), senão o reactor não acha o pom-pai.

```go
GetSubDirectory: func(source *dagger.Directory, path string) *dagger.Directory {
    return source   // multi-módulo: precisa do contexto inteiro
},
```

### 4. Image labels OCI

Sempre populate as labels canônicas pra rastreabilidade:

```go
labels := fmt.Sprintf(
    "org.opencontainers.image.revision=%s,org.opencontainers.image.version=%s,org.opencontainers.image.created=%s",
    commitSha, version, time.Now().UTC().Format(time.RFC3339))
```

`docker inspect <image>` mostra de qual commit/versão veio a imagem — útil em incidents.

## Funções complementares

### `CheckQuality`: testes + Sonar nos módulos alterados

```go
func (m *<App>) CheckQuality(
    ctx context.Context,
    source *dagger.Directory,
    baseBranch string,
    commitSha string,
    sonarHost string,
    sonarToken *dagger.Secret,
    stopOnFirstFail bool,
    gitlabHost string,
    gitlabToken *dagger.Secret,
    gitlabProjectID string,
) error {
    glClient, _ := newGitLabClient(ctx, gitlabHost, gitlabToken, gitlabProjectID)
    qualityTargets := map[string]pipeline.QualityTarget[*dagger.Directory, *dagger.Secret]{
        "core":    {Check: m.checkMaven, Path: "<app>-core"},
        "ingress": {Check: m.checkMaven, Path: "<app>-ingress"},
    }
    return pipeline.CheckQuality(ctx, daggerOps(glClient),
        qualityTargets, source, baseBranch, commitSha, sonarHost, sonarToken, stopOnFirstFail)
}
```

### `Promote`: imagens staging → production

```go
func (m *<App>) Promote(
    ctx context.Context,
    source *dagger.Directory,
    srcRegistry string,
    registryUser string,
    registryPass *dagger.Secret,
    dstRegistry string,
    buildBranch string,
) error {
    return dag.OrchestratorUtils().Promote(ctx, source, m.projectImagesJson(),
        srcRegistry, registryUser, registryPass,
        dagger.OrchestratorUtilsPromoteOpts{
            DstRegistry: dstRegistry,
            BuildBranch: buildBranch,
        })
}
```

### `CheckImages`: garante que imagens existem antes de promote

```go
func (m *<App>) CheckImages(
    ctx context.Context,
    source *dagger.Directory,
    registry string,
    registryUser string,
    registryPassword *dagger.Secret,
) error {
    return dag.OrchestratorUtils().CheckImages(ctx, source, m.projectImagesJson(),
        registry,
        dagger.OrchestratorUtilsCheckImagesOpts{
            RegistryUser: registryUser,
            RegistryPass: registryPassword,
        })
}
```

`projectImagesJson()` retorna o mapa `imagem→subdir`:

```go
func (m *<App>) projectImagesJson() string {
    return `{"<app>/core":"<app>-core","<app>/ingress":"<app>-ingress"}`
}
```

## Daggerverse modules da Basis

| Módulo | Função |
|--------|--------|
| `dag.Maven()` | Build de Java/Maven com cache de `~/.m2/repository` |
| `dag.Uv()` | Build Python com `uv` |
| `dag.Npm()` | Build de frontends Angular |
| `dag.OrchestratorUtils()` | `CommitAndPush`, `Promote`, `CheckImages`, `TagWithSha`, `GetChangedProjects` |
| `dag.GitLabCI()` | Helper pra interagir com GitLab API (commit statuses, pipeline ID) |

## `.gitlab-ci.yml` (esqueleto)

```yaml
stages:
  - quality
  - publish
  - promote

variables:
  DAGGER_VERSION: "0.20.5"

quality:
  stage: quality
  image: registry.dagger.io/engine:${DAGGER_VERSION}
  script:
    - dagger call check-quality
        --source=. --base-branch=origin/$CI_DEFAULT_BRANCH
        --commit-sha=$CI_COMMIT_SHA
        --sonar-host=$SONAR_HOST --sonar-token=env:SONAR_TOKEN
        --gitlab-host=$CI_SERVER_URL --gitlab-token=env:CI_GITLAB_TOKEN
        --gitlab-project-id=$CI_PROJECT_ID
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

publish:
  stage: publish
  image: registry.dagger.io/engine:${DAGGER_VERSION}
  script:
    - export VERSION=$(date +%Y.%m.%d).$CI_PIPELINE_ID
    - dagger call publish-all
        --source=. --commit-sha=$CI_COMMIT_SHA --version=$VERSION
        --registry-user=$REGISTRY_USER --registry-password=env:REGISTRY_PASSWORD
        --git-remote-url=$CI_REPOSITORY_URL --git-branch=$CI_COMMIT_REF_NAME
  rules:
    - if: $CI_COMMIT_BRANCH == "develop"
```

`VERSION=$(date +%Y.%m.%d).$CI_PIPELINE_ID` produz CalVer compatível com Image Updater regex.

## Anti-padrões

- **`mvn versions:set` sem `-DgenerateBackupPoms=false`** — gera `pom.xml.versionsBackup` em cada módulo, polui working tree e quebra `CommitAndPush`
- **Excluir `**/target/` no Exclude inicial mas esquecer no rebuild** — o cache fica com lixo, build determinístico vira não-determinístico
- **Senha de registry como string em código** — usar `*dagger.Secret` sempre
- **Bump-and-commit antes do push da imagem** — se push falha, repo já tem versão bumped sem imagem correspondente. Ordem certa: build → push → bump → commit
- **Múltiplos `mvn` calls criando containers separados sem reusar cache** — cada `WithExec` em um container novo perde `~/.m2`. Encadear ou usar volume cache
