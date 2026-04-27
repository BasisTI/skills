# pyproject.toml: skeleton Basis (uv)

Templates pra apps Python na Basis. Decisão chave: workspace ou flat.

## Decisão: workspace ou flat?

- **1 component** (1 app, sem libs internas): **flat** — `pyproject.toml` único na raiz
- **2+ components** (várias apps, libs compartilhadas, scripts): **workspace** — root + members

Promover de flat → workspace quando aparecer o segundo component.

## Flat: app single-component

```toml
[project]
name = "<app>"
version = "0.1.0"                          # CalVer no CI
description = "<descrição>"
authors = [
    { name = "<Nome>", email = "<email>@basis.com.br" }
]
requires-python = "~=3.13.0"
dependencies = [
    "fastapi==0.115.0",
    "uvicorn==0.32.0",
    "sqlmodel==0.0.31",
    "psycopg2-binary==2.9.11",
]

[build-system]
requires = ["uv_build>=0.9.22,<0.10.0"]
build-backend = "uv_build"

[dependency-groups]
dev = [
    "ruff==0.7.0",
    "pytest==9.0.2",
    "pytest-asyncio==1.3.0",
]

[tool.ruff]
line-length = 100
target-version = "py313"

[tool.ruff.lint]
select = ["E", "F", "W", "I", "N", "UP", "B", "C4", "SIM"]

[tool.pytest.ini_options]
asyncio_mode = "auto"
```

## Workspace: root pyproject

Root agrega members e declara deps comuns ao workspace inteiro. Note `package = false` — root não vira pacote distribuível.

```toml
[project]
name = "<projeto>-root"
version = "0.1.0"
description = "<projeto> Workspace Root"
authors = [
    { name = "<Nome>", email = "<email>@basis.com.br" }
]
requires-python = "~=3.13.0"
dependencies = [
    # Deps que aparecem em múltiplos members — opcional, ajuda lockfile coerente
    "alembic==1.18.4",
    "psycopg2-binary==2.9.11",
    "sqlmodel==0.0.31",
    # Members (forçam estarem no lock)
    "<app1>",
    "<app2>",
    "<lib1>",
]

[tool.uv.sources]
<app1> = { workspace = true }
<app2> = { workspace = true }
<lib1> = { workspace = true }

[tool.uv]
managed = true
package = false
workspace = { members = [
    "libs/*",
    "apps/<app1>",
    "apps/<app2>",
    "scripts/<job1>"
] }

[build-system]
requires = ["uv_build>=0.9.22,<0.10.0"]
build-backend = "uv_build"

[dependency-groups]
dev = [
    "ruff==0.7.0",
    "pytest==9.0.2",
    "pytest-asyncio==1.3.0",
]
```

`workspace = { members = [...] }` aceita glob (`libs/*`) ou paths exatos. Glob é prático mas pode pegar diretórios indesejados — paths exatos são mais explícitos.

## Workspace: member pyproject (app)

```toml
[project]
name = "<app1>"
version = "0.1.0"                          # bumped no CI
description = "<descrição da app>"
authors = [
    { name = "<Nome>", email = "<email>@basis.com.br" }
]
requires-python = "~=3.13.0"
dependencies = [
    # Deps próprias da app
    "fastapi==0.115.0",
    "uvicorn==0.32.0",
    # Deps internas do workspace
    "<lib1>",
    "<lib2>",
]

[tool.uv.sources]
<lib1> = { workspace = true }
<lib2> = { workspace = true }

[build-system]
requires = ["uv_build>=0.9.22,<0.10.0"]
build-backend = "uv_build"
```

Sem `[dependency-groups]` em members — dev deps vão no root e ativam pra todo workspace via `uv sync --group dev` no root.

## Workspace: member pyproject (lib)

Mais simples — só deps da própria lib:

```toml
[project]
name = "<lib1>"
version = "0.1.0"
description = "<descrição>"
authors = [
    { name = "<Nome>", email = "<email>@basis.com.br" }
]
requires-python = "~=3.13.0"
dependencies = [
    "sqlmodel==0.0.31",
    "psycopg2-binary==2.9.11",
]

[build-system]
requires = ["uv_build>=0.9.22,<0.10.0"]
build-backend = "uv_build"
```

## Comandos uv (rodar do root, mesmo em workspace)

```bash
uv sync                          # instala members + deps em .venv (sem dev)
uv sync --group dev              # idem + dev deps (ruff, pytest)
uv sync --frozen                 # CI/Docker: usa lock como verdade absoluta
uv add <pkg>                     # adiciona dep ao pyproject + lock
uv add --group dev <pkg>         # adiciona dev dep
uv add <pkg> --package <member>  # adiciona dep a um member específico (workspace)
uv lock                          # regenera o lock
uv run <cmd>                     # roda comando dentro do venv
```

## Convenções Basis

- **Naming**: kebab-case no `name` (`training-hiring`), snake_case no diretório (`training_hiring`) opcional. Padrão atual no kaizenstat: kebab em ambos
- **Versão local**: `0.1.0` (placeholder) — substituída por CalVer no CI via `pipeline.VfUv`
- **`requires-python`**: `~=3.13.0` (estritamente major.minor) — força reprodutibilidade
- **Authors**: `Nome <email@basis.com.br>`
- **`build-backend = "uv_build"`** — backend nativo do uv, evita hatchling/setuptools

## Anti-padrões

- **Workspace com 1 member** — overhead de root pyproject sem ganho. Comece flat
- **Versões com range** (`>=1.0,<2`, `^1.0`) — em prod, lockfile resolve, mas se renovar lock, pode pegar minor breaking. Sempre `==`
- **`name` no member duplicando o root** — quebra resolution. Cada `name` é único no workspace
- **`package = true` no root** com members — root não deve ser publicável; é só agregador
- **Misturar `dev =` em todos members** — dev deps centralizadas no root
- **`uv sync` sem `--frozen` no Dockerfile** — pode rebuildar lock, build não-reprodutível
