# Dagger pipeline (Go) para Python na Basis

Padrão Basis pra CI de apps Python: Dagger pipeline mistura targets Maven e Python no mesmo `main.go`. A diferença está nas funções `publish*` e no `VersionFile`.

## Estrutura `main.go` (multi-tecnologia)

Exemplo do kaizenstat (Maven + Python no mesmo repo):

```go
package main

import (
    "context"
    "dagger/<projeto>/internal/dagger"
    "fmt"
    "time"

    "github.com/BasisTI/daggerverse/gitlabci"
    "github.com/BasisTI/daggerverse/pipeline"
)

type <Projeto> struct{}

const group = "<projeto>"
const mavenImage = "maven:3.9.11-eclipse-temurin-25-alpine"

// PublishAll: build e push só dos modules alterados desde baseBranch
func (m *<Projeto>) PublishAll(
    ctx context.Context,
    // +defaultPath="."
    source *dagger.Directory,
    // +default="origin/develop"
    baseBranch string,
    commitSha string,
    version string,                            // CalVer
    // +default="basis-registry.basis.com.br"
    registry string,
    registryUser string,
    registryPassword *dagger.Secret,
    // +optional
    gitlabHost string,
    // +optional
    gitlabToken *dagger.Secret,
    // +optional
    gitlabProjectID string,
    // +optional
    gitRemoteUrl string,
    // +optional +default="develop"
    gitBranch string,
) (string, error) {
    glClient, err := newGitLabClient(ctx, gitlabHost, gitlabToken, gitlabProjectID)
    if err != nil {
        return "", err
    }

    buildTargets := map[string]pipeline.BuildTarget[*dagger.Directory, *dagger.Secret]{
        "judge-admin":         {Build: m.publishMaven,  Path: "apps/judge-admin",      VersionFile: pipeline.VfMaven},
        "training-hiring":     {Build: m.publishDocker, Path: "apps/training-hiring",  VersionFile: pipeline.VfUv},
        "training-absence":    {Build: m.publishDocker, Path: "apps/training-absence", VersionFile: pipeline.VfUv},
        "job-absence-pred":    {Build: m.publishDocker, Path: "apps/job-absence-pred", VersionFile: pipeline.VfUv},
        "webhook-hiring-pred": {Build: m.publishDocker, Path: "apps/webhook-hiring-pred", VersionFile: pipeline.VfUv},
    }

    result, err := pipeline.PublishAll(ctx, daggerOps(glClient), buildTargets, source,
        baseBranch, commitSha, version, registry, registryUser, registryPassword)
    if err != nil {
        return "", err
    }

    if result.Published != "" && gitRemoteUrl != "" && len(result.VersionFiles) > 0 {
        commitMsg := fmt.Sprintf("[skip ci] Bump versão para %s", version)
        if err := dag.OrchestratorUtils().BumpAndCommitVersions(
            ctx, source, result.VersionFiles, version, commitMsg, gitBranch, gitRemoteUrl,
        ); err != nil {
            return "", fmt.Errorf("commit bumped versions: %w", err)
        }
    }

    return result.Published, nil
}
```

## Estratégias de build por tecnologia

### Python: `publishDocker`

Para módulos Python (qualquer tipo: app, script, dagster job), usa `source.DockerBuild()` pra construir a imagem a partir do Dockerfile do módulo:

```go
func (m *<Projeto>) publishDocker(
    ctx context.Context,
    source *dagger.Directory,
    module, commitSha, version, registry, registryUser string,
    registryPassword *dagger.Secret,
    entryPointInfo string,
) (string, error) {
    imageName := fmt.Sprintf("%s/%s/%s:%s", registry, group, module, version)
    dockerfile := fmt.Sprintf("apps/%s/Dockerfile", module)

    container := source.DockerBuild(dagger.DirectoryDockerBuildOpts{
        Dockerfile: dockerfile,
    })
    if registryPassword != nil {
        container = container.WithRegistryAuth(registry, registryUser, registryPassword)
    }
    container = container.
        WithLabel("org.opencontainers.image.revision", commitSha).
        WithLabel("org.opencontainers.image.version", version).
        WithLabel("org.opencontainers.image.created", time.Now().Format(time.RFC3339))
    return container.Publish(ctx, imageName)
}
```

Pontos:
- Build context = `source` (workspace inteiro), Dockerfile referencia paths relativos
- O Dockerfile mesmo cuida de `uv sync --frozen` (ver `dockerfile-uv-multistage.md`)
- Labels OCI sempre populadas
- Registry auth via `WithRegistryAuth` antes do `Publish`

### Maven: `publishMaven` (referência cruzada)

Conforme a skill `basis-k8s-deploy` (ver `references/dagger-pipeline-example.md` no repo `basis-skills`), Maven usa `dag.Maven().FullBuild()` que orquestra Jib internamente. Não há equivalente em Python — Dockerfile é a abstração mais simples.

## `VersionFile`: bump-and-commit por tipo

`pipeline.BumpAndCommitVersions` precisa saber QUAIS arquivos atualizar com a nova versão:

| Tipo | `VersionFile` | Arquivo afetado | Forma do bump |
|------|---------------|-----------------|---------------|
| Maven | `pipeline.VfMaven` | `pom.xml` | `<version>` ou `versions:set` |
| Python (uv) | `pipeline.VfUv` | `pyproject.toml` | linha `version = "..."` em `[project]` |
| (futuro) Angular | TBD | `package.json` | `version` field |

`pipeline.VfUv` lida com edição mínima do `pyproject.toml` — só substitui o valor de `version =` no `[project]`. Não toca `tool.uv.*` nem deps. Se houver problema, usar `versions:set` analog em uv:

```bash
uv version <novo>           # uv 0.5+ atualiza version no pyproject
```

Mas pra workspace, o orchestrator já cuida — não precisa shell out.

## Quality check em Python (não usado hoje)

Hoje o kaizenstat só roda `CheckQuality` em targets Maven (Sonar tem ótimo suporte Java). Pra incluir Python:

```go
qualityTargets := map[string]pipeline.QualityTarget[*dagger.Directory, *dagger.Secret]{
    "judge-admin": {Check: m.checkMaven, Path: "apps/judge-admin"},
    // Quando tivermos:
    // "training-hiring": {Check: m.checkUv, Path: "apps/training-hiring"},
}

func (m *<Projeto>) checkUv(
    ctx context.Context,
    source *dagger.Directory,
    module, sonarHost string,
    sonarToken *dagger.Secret,
) error {
    uvc := dag.Uv()  // Daggerverse uv module
    // ruff + pytest + (opcional) Sonar Python plugin
    // implementação depende da API do uv module — checar daggerverse docs
    return nil
}
```

Por enquanto, lint + testes locais e em pre-merge MR. Sonar pra Python entra quando o módulo tiver maturidade pra justificar.

## `projectImagesJson`: mapeamento imagem → path

Pra `Promote` e `CheckImages`, manter o mapa explícito:

```go
func (m *<Projeto>) projectImagesJson() string {
    return `{"<projeto>/judge-admin":"apps/judge-admin",
"<projeto>/training-hiring":"apps/training-hiring",
"<projeto>/training-absence":"apps/training-absence",
"<projeto>/job-absence-pred":"apps/job-absence-pred",
"<projeto>/webhook-hiring-pred":"apps/webhook-hiring-pred",
"<projeto>/hiring-salary-update":"scripts/hiring_salary_update"}`
}
```

A chave (`<projeto>/<modulo>`) é o nome da imagem sem registry e sem tag. O valor é o path no repo (relativo). `Promote` usa esse mapa pra saber quais imagens copiar staging → production.

## `.gitlab-ci.yml` (esqueleto Python ou misto)

Mesmo do mundo Java — Dagger abstrai a tecnologia:

```yaml
stages:
  - quality
  - publish
  - promote

variables:
  DAGGER_VERSION: "0.20.5"

publish:
  stage: publish
  image: registry.dagger.io/engine:${DAGGER_VERSION}
  script:
    - export VERSION=$(date +%Y.%m.%d).$CI_PIPELINE_ID
    - dagger call publish-all
        --source=. --base-branch=origin/$CI_DEFAULT_BRANCH
        --commit-sha=$CI_COMMIT_SHA --version=$VERSION
        --registry-user=$REGISTRY_USER
        --registry-password=env:REGISTRY_PASSWORD
        --git-remote-url=$CI_REPOSITORY_URL
        --git-branch=$CI_COMMIT_REF_NAME
  rules:
    - if: $CI_COMMIT_BRANCH == "develop"
```

## Anti-padrões

- **Build do Dockerfile sem usar `source` como context** — perde acesso ao lockfile/workspace, `uv sync --frozen` falha
- **`pipeline.VfUv` apontado pra arquivo errado** — bump silencioso no arquivo errado, lockfile out-of-sync
- **Mistura `publishMaven` + Dockerfile manual** — duplica esforço (Jib via Maven já faz a imagem)
- **Esquecer labels OCI** — sem rastreabilidade no `docker inspect` em produção
- **Usar `WithExec("uv", ...)` em vez de `DockerBuild`** — perde os layers do Dockerfile, build não otimizado
