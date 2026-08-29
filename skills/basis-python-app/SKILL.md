---
name: basis-python-app
description: >-
  Use when starting, extending, or refactoring a Basis Python application — Python 3.13+ +
  uv (mandatory) for dependency and project management, ruff for lint/format, pytest for
  tests, Dockerfile multi-stage for container builds (no equivalent of Jib). Workspace
  pattern only when there are multiple components (apps/libs/scripts); single-component
  projects use a flat pyproject. Activate for new modules, dependency upgrades, or
  container build questions. For the pipeline itself — `ci/pipeline.toml`, the shared CI
  template, Dagger, Sonar, merge requests — use `basis-ci-gitlab`; this skill only says
  which target type a Python component declares there.
---

# Basis Python Application

Padrões da Basis pra apps Python. Pareada com `basis-k8s-deploy` (lado ops) e `basis-spring-app` (Spring/Java analog). Integração com o **SGO** (`ks-jira`, biblioteca `jira`, webhooks, outbox): `basis-sgo-jira`.

## 1. Stack default (sempre, sem exceção)

- **Python**: 3.13+ (versão estável recente, pinada via `requires-python = "~=3.13.0"`)
- **Build/dependências**: `uv` (obrigatório) — nunca pip puro, poetry, hatch, pipenv
- **Lint/format**: `ruff` (substitui black + isort + flake8)
- **Testes**: `pytest` + `pytest-asyncio`; Testcontainers ainda não é padrão (avaliar quando virar dor)
- **Imagem**: Dockerfile multi-stage com `uv sync --frozen` (não há Jib pra Python)
- **CI**: Dagger pipeline em Go com Daggerverse modules + `dag.Uv()` (análogo ao `dag.Maven()`)

## 2. Layout

### Single-component (1 app, sem libs internas)

```
<app>/
├── pyproject.toml
├── uv.lock
├── Dockerfile
├── src/<app>/
│   ├── __init__.py
│   └── ...
└── tests/
```

### Workspace (múltiplos components — apps + libs + scripts)

```
<projeto>/
├── pyproject.toml          # root: workspace declaration + deps comuns
├── uv.lock                 # único lockfile pra todo o workspace
├── apps/
│   ├── <app1>/{pyproject.toml, Dockerfile, src/, tests/}
│   └── <app2>/{pyproject.toml, Dockerfile, src/, tests/}
├── libs/
│   ├── <lib1>/{pyproject.toml, src/}
│   └── <lib2>/{pyproject.toml, src/}
└── scripts/
    └── <job>/{pyproject.toml, Dockerfile, src/}
```

Workspace SÓ quando há mais de 1 component. Um app simples começa flat — promove pra workspace quando aparecer um segundo component.

Ver [`references/pyproject-skeleton.md`](references/pyproject-skeleton.md).

## 3. Configuração de dependências

- **Versões pinadas** (`==`): nada de range em prod. Lockfile garante reprodutibilidade
- **Deps internas no workspace**: `[tool.uv.sources] <pkg> = { workspace = true }`
- **Dev deps via `[dependency-groups]`** (PEP 735), ativadas com `uv sync --group dev`
- **Sem `requirements.txt`** — `pyproject.toml` + `uv.lock` é canônico

## 4. Build da imagem (Dockerfile multi-stage)

Padrão: `ghcr.io/astral-sh/uv:<ver>-python3.13-trixie-slim` como builder, `python:3.13-slim-trixie` como runtime. Copia `.venv/` do builder, `PATH` ajustado.

Ver [`references/dockerfile-uv-multistage.md`](references/dockerfile-uv-multistage.md).

## 5. CI: qual target declarar

A pipeline é declarativa. Um componente Python entra no `ci/pipeline.toml` do repositório
como um target, e o orchestrator genérico cuida do resto — não existe mais um `main.go` de
pipeline por projeto.

| Situação | `type` |
|---|---|
| Projeto Python autocontido, com seu próprio `pyproject.toml` | `uv` |
| Componente dentro de um **workspace uv** | `dockerfile` com `source-path = "."` |

O segundo caso não é preferência: `uv sync --frozen` precisa do lockfile da **raiz do
workspace**, então a árvore montada tem que ser a raiz do repositório, e não o diretório do
app.

```toml
[targets.webhook-hiring-pred]
type = "dockerfile"
path = "apps/webhook-hiring-pred"
source-path = "."
version-file = "apps/webhook-hiring-pred/pyproject.toml"
```

`version-file` default de `uv` e `dockerfile` é `pyproject.toml`; num workspace ele precisa
ser explícito, senão o bump reescreve o arquivo errado.

Para analisar no Sonar, um target `type = "dockerfile"` exige `quality-type = "uv"` — o
Dockerfile diz como a imagem é construída, não com que build system o código é analisado.

Schema completo, funções do orchestrator e diagnóstico de pipeline: **`basis-ci-gitlab`**.

## 6. Lint, format, testes

```toml
# pyproject.toml (root ou single)
[dependency-groups]
dev = [
    "ruff==<ver>",
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

Comandos (rodar do root, mesmo em workspace):

```bash
uv sync --group dev          # instala deps + dev deps
uv run ruff check            # lint
uv run ruff format           # format
uv run pytest                # testes
```

## 7. Interface com `basis-k8s-deploy`

- **Imagem**: tag CalVer (`YYYY.MM.DD.<pipelineId>`) — Image Updater usa o mesmo regex do mundo Java
- **Probes K8s**: dependem do tipo de app
  - **Web/HTTP** (Flask, FastAPI): expor `/health` ou usar lib equivalente do actuator (FastAPI tem `@app.get("/health")` simples)
  - **Job/script**: sem probes — `kind: Job` ou `CronJob`, não Deployment
  - **Worker** (Dagster, consumer): livenessProbe via TCP socket ou exec do uv (`uv run python -c "import sys; sys.exit(0)"`)
- **Env vars**: convenção `APPLICATION_*` quando lendo via Pydantic Settings ou similar (mesma lógica do Spring relaxed binding — keys mapeáveis)
- **Secrets**: mesmo padrão do Spring — `valueFrom.secretKeyRef` (ver `basis-k8s-deploy/references/operator-secret-cheatsheet.md`)

## References disponíveis

- [`references/pyproject-skeleton.md`](references/pyproject-skeleton.md) — root workspace + member pyproject patterns
- [`references/dockerfile-uv-multistage.md`](references/dockerfile-uv-multistage.md) — Dockerfile com `uv sync --frozen`, multi-stage, non-root

## Skills upstream

Diferente do mundo Spring (sivalabs), não temos skill upstream consolidada para Python+uv que se alinhe ao nosso stack. Quando aparecer, atualizar este SKILL.md com referências.

## Anti-padrões

- **`pip install`** ou `python -m venv` direto — fora do uv, perde lockfile, não é reprodutível
- **Workspace pra app single-component** — overhead sem benefício
- **`requirements.txt`** — duplica info que já está no pyproject + lock
- **Dockerfile com `pip install` dentro** — mistura ferramentas, perde cache de uv
- **Range de versão (`>=1.0`) em prod** — quebra reprodutibilidade. Sempre `==`
- **Probe HTTP `/actuator/health`** num app Python — esse path é Spring; em Python o que existir vem do framework (FastAPI custom, Flask custom)
