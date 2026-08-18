# Schema do `ci/pipeline.toml`

Schema real do orchestrator da daggerverse 3.x. Implementado em
`daggerverse/pipeline/config/` — `config.go` (tipos e defaults), `validate.go` (regras),
`images.go` (derivação do mapa de imagens).

**O parse é estrito.** O decoder roda com `DisallowUnknownFields`: chave desconhecida é
erro, não aviso. Isso é deliberado — uma chave com nome errado ignorada em silêncio é uma
configuração que alguém acredita estar valendo e não está.

Valide sem empurrar commit:

```bash
dagger call -m github.com/BasisTI/daggerverse/orchestrator@<versão> \
  --source . --config-path ci/pipeline.toml validate
```

## Estrutura

```toml
schema-version = 1        # único valor aceito

[project]
group = "<grupo>"          # obrigatório; vira <registry>/<grupo>/<image>

[defaults.maven]           # opcional, por tecnologia
[defaults.npm]
[defaults.uv]

[targets.<nome>]           # ao menos um
type = "..."               # obrigatório
```

O **nome do target** é o default de três coisas ao mesmo tempo: `path`, `image` e
`sonar-project-key`. Escolher bem o nome economiza três linhas; escolher mal obriga a
sobrescrever as três.

## `[project]`

| Chave | Obrigatória | Efeito |
|---|---|---|
| `group` | sim | Caminho no registry: `<registry>/<group>/<image>` |

## `[defaults.<tecnologia>]`

Valem para todos os targets daquele tipo, e cada target pode sobrescrever.

| Bloco | Chaves |
|---|---|
| `[defaults.maven]` | `image`, `use-docker`, `sonar-plugin-version` |
| `[defaults.npm]` | `build-image`, `run-image` |
| `[defaults.uv]` | `build-image`, `run-image` |

`sonar-plugin-version` vazio significa "o módulo maven decide" — não "a última release".

## `[targets.<nome>]`

### Comuns a todos os tipos

| Chave | Default | Para quê |
|---|---|---|
| `type` | — **obrigatória** | `maven`, `npm`, `uv`, `dockerfile`, `custom` |
| `path` | nome do target | Onde o código do target vive |
| `source-path` | `path` efetivo, ou `.` se `reactor = true` | O que é montado como raiz do build |
| `image` | nome do target | Último segmento do caminho no registry |
| `version-file` | por tipo (ver abaixo) | Arquivo cuja versão o bump reescreve |
| `root-version-file` | `false` | O `version-file` é relativo à **raiz do repo**, não ao `source-path` |
| `extra-trigger-paths` | `[]` | Caminhos adicionais que reconstroem este target |
| `sonar` | `false` | Participa do `check-quality` |
| `sonar-project-key` | nome do target | Chave permanente da análise; exige `sonar = true` |
| `quality-type` | o próprio `type` | Com que build system analisar; exige `sonar = true` |

Defaults de `version-file`, seguindo o **`quality-type` efetivo** e não o `type`:

| Tipo | `version-file` |
|---|---|
| `maven` | `pom.xml` |
| `npm` | `package.json` |
| `uv`, `dockerfile` | `pyproject.toml` |

### Só para `type = "maven"`

| Chave | Default | Para quê |
|---|---|---|
| `maven-image` | `defaults.maven.image` | Sobrescreve a imagem só neste target |
| `use-docker` | `defaults.maven.use-docker` | Liga um daemon dind (Testcontainers) |
| `sonar-plugin-version` | `defaults.maven.sonar-plugin-version` | |
| `reactor` | `false` | Multi-módulo: monta a raiz e builda um módulo |
| `module` | — **obrigatória se `reactor`** | Qual módulo do reactor |
| `extra-options` | `[]` | Opções extras passadas ao Maven |

`use-docker` é um ponteiro no código, o que distingue "ausente" (herda o default) de
"explicitamente `false`" (sobrescreve o default para desligado).

### Só para `type = "uv"`

| Chave | Default | Para quê |
|---|---|---|
| `uv-build-image` / `uv-run-image` | `defaults.uv.*` | |
| `run-subdir` | — | Subdiretório de execução na imagem final |
| `customizations` | `[]` | `"dbt"`, `"dlt"` |

### Só para `type = "dockerfile"`

| Chave | Default | Para quê |
|---|---|---|
| `dockerfile` | `"Dockerfile"` | Relativo ao `source-path` efetivo |

**O nome é case-sensitive.** Um arquivo chamado `dockerfile` não é encontrado; já custou um
`git mv`.

### `type = "custom"`

O target entra normalmente no mapa de imagens (`check-images` e `promote` contam com ele),
mas o orchestrator genérico **recusa buildá-lo** — quem builda é o módulo Dagger local do
projeto. Como não há default por tipo, `version-file` precisa ser explícito, senão o bump
não acontece e o `promote` compara versões que nunca mudaram.

## Validações

Todas em `validate.go`, todas falham no `validate`:

- `schema-version` diferente de `1`.
- `project.group` vazio.
- Nenhum target.
- `type` ausente ou fora do conjunto.
- `quality-type` fora de `maven`/`npm`/`uv`, ou sem `sonar = true`.
- `sonar = true` num `type = "dockerfile"` **sem** `quality-type`. Faz sentido: o Dockerfile
  diz como a imagem é construída, não com que build system o código é analisado.
- `sonar-project-key` sem `sonar = true`.
- Duas chaves de Sonar efetivas iguais entre targets.
- `reactor = true` sem `module`.
- Dois nomes de imagem efetivos iguais entre targets.

## A regra anti-drift

O mapa de imagens consumido por `check-images` e `promote` **não é declarado**. É derivado
dos mesmos targets, por `Config.ProjectImages()`.

Antes disso, no `kaizenstat`, a lista de imagens era uma string JSON mantida à mão em
`ci/main.go`, em paralelo ao mapa de builds. As duas divergiram: dois serviços estavam na
lista de promoção **sem ter target de build**. Ninguém percebeu porque nada falha quando uma
lista tem um item a mais.

A segunda face da mesma regra é `extra-trigger-paths`. Um target com caminhos extras é
reconstruído quando qualquer um deles muda — então a versão publicada tem que ser resolvida
pelo commit mais recente **entre todos os caminhos**. Resolver só pelo primário promoveu, no
`colaboradados`, uma imagem de dois dias antes, com a pipeline inteira verde. `ProjectImages()`
hoje devolve a lista completa por imagem exatamente por causa disso.

**Ao mexer no TOML, a pergunta é sempre: o que dispara o build e o que resolve a versão
enxergam o mesmo conjunto de caminhos?**

## Exemplos reais anotados

### Módulo único na raiz

O caso mais simples. `path = "."` diz duas coisas: qualquer arquivo alterado dispara o
build, e a árvore montada é a raiz — que é o que o Sonar precisa para ter `.git` e fazer
blame.

```toml
schema-version = 1

[project]
group = "ponto"

[defaults.maven]
# NÃO usar a variante -alpine: ela é musl, e o node que o frontend-maven-plugin
# baixa é linkado contra glibc.
image = "maven:3.9.11-eclipse-temurin-25"

[targets.ponto]
type = "maven"
path = "."
sonar = true
```

### Reactor multi-módulo

Dois targets do mesmo reactor. `source-path = "."` monta a raiz; `module` seleciona.

```toml
[targets.identity-hub-core]
type = "maven"
reactor = true
source-path = "."
module = "identity-hub-core"
image = "core"                                    # nome curto no registry
extra-trigger-paths = ["identity-hub-domain", "pom.xml"]
version-file = "pom.xml"
root-version-file = true                          # a <revision> fica no pom da RAIZ
sonar = true
use-docker = true                                 # Testcontainers nos testes de integração
```

O nome do target é longo (`identity-hub-core`) porque **é a chave do Sonar**, e chaves
existentes não se renomeiam sem perder o histórico da análise. O nome curto vai no `image`.

### Alvo com JDK diferente do resto

```toml
[defaults.maven]
image = "maven:3.9.11-eclipse-temurin-25-alpine"

[targets.integracaosgo]
type = "maven"
# Módulo legado em Spring Boot 3.3.1: o maven-enforcer-plugin do JHipster
# trava em JDK 17–22 e reprova a imagem 25 do default.
maven-image = "maven:3.9.11-eclipse-temurin-21-alpine"
```

É a válvula de escape para não bifurcar a pipeline por causa de um módulo atrasado.

### Python em workspace uv

App Python em workspace `uv` usa `type = "dockerfile"` com `source-path = "."` — o
`uv sync --frozen` precisa do lockfile da raiz do workspace, não do diretório do app.

```toml
[targets.webhook-hiring-pred]
type = "dockerfile"
path = "apps/webhook-hiring-pred"
source-path = "."
version-file = "apps/webhook-hiring-pred/pyproject.toml"
```

### Targets custom com módulo local

```toml
[targets.rh-dp]
type = "custom"
# Sem default por tipo: sem esta linha o bump não acontece e o promote
# compara uma versão que nunca muda.
version-file = "pyproject.toml"

[targets.lightdash-content]
type = "custom"
path = "lightdash"
source-path = "."
# A imagem embute estes projetos dbt; sair de sincronia com eles já quebrou
# o sync do Lightdash.
extra-trigger-paths = ["rh-dp/dbtrh", "financeiro/dbt_financeiro"]
```

O repositório com targets `custom` acrescenta `DAGGER_MODULE: "."` no `.gitlab-ci.yml`. O
módulo local lê o mesmo `ci/pipeline.toml` e expõe as mesmas funções, então o template roda
sem nenhum outro ajuste.

## Sobrescrever a chave do Sonar

O default é o nome do target, e num servidor compartilhado nomes genéricos colidem:

```toml
[targets.beneficios]
type = "maven"
path = "apps/beneficios"
sonar = true
# O default seria `beneficios`, genérico demais num servidor com dezenas de projetos.
sonar-project-key = "colaboradados-beneficios"
```

A chave é o identificador **permanente** da análise. Trocar depois cria um projeto novo, sem
branch principal nem período de new code — e a análise de PR morre com
`No branch exists in Sonarqube with the name main`.
