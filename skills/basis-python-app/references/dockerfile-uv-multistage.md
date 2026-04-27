# Dockerfile multi-stage com uv

Padrão Basis pra empacotar Python em imagem container. Multi-stage: builder com uv resolve deps + cria venv; runtime mínimo só copia o resultado.

## Padrão (workspace member)

```dockerfile
FROM ghcr.io/astral-sh/uv:0.11.5-python3.13-trixie-slim AS builder

ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy PYTHONUNBUFFERED=1
ENV UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# Copia o workspace inteiro (root + members)
COPY . .

# Instala o workspace inteiro com lock congelado
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-cache

FROM python:3.13-slim-trixie

WORKDIR /app

# Copia o app + .venv do builder
COPY --from=builder /app /app

# .venv/bin no PATH (binários do uv ficam aí)
ENV PATH="/app/.venv/bin:$PATH"

# Default: rodar com uv run; override por imagem se necessário
# CMD ["uv", "run", "python", "-m", "<app>"]
```

## Pontos críticos

### 1. Imagem do builder = imagem oficial do uv

`ghcr.io/astral-sh/uv:<ver>-python<ver>-trixie-slim` já vem com `uv` + Python prontos. Evita instalar uv via pipx/wget.

Pin: sempre versão específica do uv (`0.11.5`) — evita mudança silenciosa em rebuild.

### 2. Env vars do uv

```dockerfile
ENV UV_COMPILE_BYTECODE=1     # pré-compila .pyc, startup mais rápido
ENV UV_LINK_MODE=copy         # copy em vez de hardlink (necessário pra layer)
ENV PYTHONUNBUFFERED=1        # logs sem buffer (visível em kubectl logs)
ENV UV_PYTHON_DOWNLOADS=0     # não baixar Python (já está na imagem)
```

### 3. Cache mount pra build incremental

```dockerfile
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-cache
```

`--mount=type=cache` reusa cache do uv entre builds (acelera rebuild quando deps não mudam). Em CI usar buildkit (Dagger usa por default).

### 4. `uv sync` com flags certas em build

| Flag | Por que |
|------|---------|
| `--frozen` | Usa o lockfile como verdade — falha se desincroniza com pyproject |
| `--no-dev` | Não instala deps do `[dependency-groups] dev` (pytest/ruff fora da imagem) |
| `--no-cache` | Não persiste cache final na imagem (já tem o `--mount` pra build) |

### 5. Runtime image leve

`python:3.13-slim-trixie` (~50MB) vs `python:3.13` (~150MB). Suficiente porque `.venv/` já tem todas as deps compiladas.

Não copiar uv pro runtime — o `.venv/` já tem os binários certos no `bin/`. `uv run` no CMD é opcional; pode chamar direto:

```dockerfile
CMD ["python", "-m", "<app>"]
# ou
CMD ["uvicorn", "<app>.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Padrão (single-component flat)

Sem workspace, simplifica:

```dockerfile
FROM ghcr.io/astral-sh/uv:0.11.5-python3.13-trixie-slim AS builder

ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy PYTHONUNBUFFERED=1
ENV UV_PYTHON_DOWNLOADS=0

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-cache --no-install-project

# Agora copia o código (otimização: layer de deps separado do código)
COPY . .

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-cache

FROM python:3.13-slim-trixie

WORKDIR /app
COPY --from=builder /app /app

ENV PATH="/app/.venv/bin:$PATH"

CMD ["python", "-m", "<app>"]
```

`--no-install-project` no primeiro `uv sync` instala só as deps externas (cacheável); o segundo, depois do `COPY .`, instala o projeto. Cache de deps invalida só quando `pyproject.toml`/`uv.lock` muda, não a cada commit.

Em workspace o gain é menor (qualquer mudança em member invalida) — vale flat.

## Non-root user

```dockerfile
FROM python:3.13-slim-trixie

RUN groupadd -g 1000 app && useradd -u 1000 -g app -s /bin/bash app
WORKDIR /app
COPY --from=builder --chown=app:app /app /app

USER app
ENV PATH="/app/.venv/bin:$PATH"
CMD ["python", "-m", "<app>"]
```

K8s + segurança Basis: rodar como não-root é boa prática. Jib faz isso automático no Java; em Python precisamos declarar.

## Build local

```bash
docker build -t <app>:dev .
docker run --rm -p 8000:8000 <app>:dev
```

No Dagger CI, `source.DockerBuild()` faz o equivalente — ver `dagger-pipeline-python.md`.

## Anti-padrões

- **Imagem base diferente entre builder e runtime sem matching de Python** — venv compilado em 3.13.x não roda em 3.12.y
- **`pip install` no Dockerfile** — bypassa uv, sem lockfile, build não-reprodutível
- **`COPY . .` antes do `uv sync`** — invalida cache de deps a cada commit, build lento
- **Esquecer `--frozen`** — uv pode regenerar lock no build, mudança silenciosa de versão
- **`UV_LINK_MODE=hardlink`** (default) — não funciona cross-FS (cache mount + COPY); `copy` é a opção segura
- **Ignorar `--mount=type=cache`** — build lento sem necessidade
- **Não passar `--no-dev`** — runtime fica com pytest/ruff (~50-100MB extra inúteis)
- **Esquecer `PATH` ajustado** — `python` chama o do sistema, não o do venv → ImportError em runtime
