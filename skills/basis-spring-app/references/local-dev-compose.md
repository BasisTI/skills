# Ambiente de desenvolvimento local (Docker Compose)

Objetivo: `git clone` → `docker compose up -d` → `mvn spring-boot:run -Dspring-boot.run.profiles=dev` e o sistema sobe **sem editar nenhum arquivo de configuração**.

Para isso o `application-dev.yml` e o `compose.yaml` são escritos como um par: os valores no yml são exatamente os defaults declarados no compose.

## `compose.yaml`

Fica na raiz do projeto. Portas sempre publicadas em `127.0.0.1` (não expor infra de dev na rede).

```yaml
name: <app>

services:
  postgres:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: <app>
      POSTGRES_USER: <app>
      POSTGRES_PASSWORD: <app>
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./docker/postgres/init.sql:/docker-entrypoint-initdb.d/01-init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U <app> -d <app>"]
      interval: 5s
      timeout: 3s
      retries: 20
    ports: ["127.0.0.1:5432:5432"]
    networks: [<app>-interna]

  rabbitmq:
    image: rabbitmq:4.1-management
    environment:
      RABBITMQ_DEFAULT_USER: guest
      RABBITMQ_DEFAULT_PASS: guest
    volumes: [rabbitmq-data:/var/lib/rabbitmq]
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 10s
      timeout: 5s
      retries: 12
    ports: ["127.0.0.1:5672:5672", "127.0.0.1:15672:15672"]
    networks: [<app>-interna]

  keycloak:
    image: quay.io/keycloak/keycloak:26.2
    command: start-dev --import-realm
    environment:
      - KC_DB=postgres
      - KC_DB_URL_HOST=postgres
      - KC_DB_URL_DATABASE=keycloak
      - KC_DB_USERNAME=keycloak
      - KC_DB_PASSWORD=keycloak
      - KC_HTTP_PORT=9080
      - KC_BOOTSTRAP_ADMIN_USERNAME=admin
      - KC_BOOTSTRAP_ADMIN_PASSWORD=admin
      - KC_HEALTH_ENABLED=true
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - ./docker/keycloak:/opt/keycloak/data/import
    healthcheck:
      test: ["CMD-SHELL", "bash -c 'exec 3<>/dev/tcp/127.0.0.1/9000; printf \"GET /health/ready HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n\" >&3; grep -q \"200\" <&3'"]
      interval: 15s
      timeout: 5s
      retries: 20
    ports: ["127.0.0.1:9080:9080"]
    networks: [<app>-interna]

volumes:
  postgres-data:
  rabbitmq-data:

networks:
  <app>-interna:
    driver: bridge
```

Serviços adicionais conforme a app precisar, no mesmo padrão (healthcheck + porta em `127.0.0.1` + volume nomeado):

- **MinIO** (`minio/minio`) — quando há upload/objeto
- **GreenMail** (`greenmail/standalone`) — quando há envio de e-mail (SMTP em 3025, web em 8080 do container)
- **Ollama** (`ollama/ollama`) — inferência local; usar `profiles: [ollama]` para não subir por padrão

## Keycloak usa o PostgreSQL da própria aplicação

Padrão Basis: **nada de H2/dev-file no Keycloak local**. O Keycloak aponta para o mesmo container Postgres da aplicação, num banco e role separados (`keycloak`/`keycloak`).

Por que:

- **Exportar o realm com o Keycloak no ar.** Com o dev-file (H2) o arquivo fica travado pelo processo e `kc.sh export` falha ou exige derrubar o container. Com Postgres o export roda direto.
- **Estado sobrevive a `docker compose down`** — o volume é o mesmo do Postgres; usuário criado na mão para testar continua lá.
- **Um container de banco só** — menos memória, um healthcheck, e dá para usar `psql` para inspecionar tanto o schema da app quanto o do Keycloak.
- **Mesma topologia de prod**, onde o Keycloak nunca roda com banco embarcado.

### `docker/postgres/init.sql`

Roda uma única vez, na criação do volume (`docker-entrypoint-initdb.d`). Se o volume já existe, não roda — recriar exige `docker compose down -v`.

```sql
-- Role e banco do Keycloak, separados do schema da aplicação
CREATE ROLE keycloak PASSWORD 'keycloak';
ALTER ROLE keycloak WITH LOGIN;
CREATE DATABASE keycloak OWNER keycloak;

-- Extensões que a aplicação precisar, no banco da aplicação
-- CREATE EXTENSION IF NOT EXISTS vector;
```

### Import do realm

`./docker/keycloak/` é montado em `/opt/keycloak/data/import` e `--import-realm` carrega tudo que estiver lá no primeiro start (quando o realm ainda não existe no banco).

Partir de [`basis-realm-dev.json`](basis-realm-dev.json) — realm `basis`, um client confidencial `<app>-admin`, client roles `<APP>_USER`/`<APP>_ADMIN` e dois usuários de teste (`admin`/`admin`, `user`/`user`):

```bash
mkdir -p docker/keycloak
sed -e 's/<app>/meuapp/g' -e 's/<APP>/MEUAPP/g' \
    basis-realm-dev.json > docker/keycloak/basis-realm.json
```

Ajustar `redirectUris`/`rootUrl` se a app não roda em `http://localhost:8080`.

### Exportar o realm de volta (depois de mexer no console)

Mudança feita pelo console admin (`http://localhost:9080`, `admin`/`admin`) só vira código depois do export:

```bash
docker compose exec keycloak /opt/keycloak/bin/kc.sh export \
    --dir /opt/keycloak/data/import \
    --realm basis \
    --users realm_file
```

O arquivo cai direto em `docker/keycloak/` pelo bind mount.

> **Antes de commitar um export**: um export completo carrega chave RSA privada, segredos HMAC/AES (`components.org.keycloak.keys.KeyProvider`), o client secret real e os hashes argon2 das senhas. Nada disso pode ir para repositório — em especial repositório público. Ou se commita apenas o delta editado à mão sobre o template, ou se remove `components`, `clientScopes`, `authenticationFlows` e os clients embutidos (`account`, `admin-cli`, `broker`, `realm-management`, `security-admin-console`) — o Keycloak recria todos eles no import — e se troca `secret` e `credentials` por valores de desenvolvimento.

## `application-dev.yml` — espelha o compose

Regra: o profile `dev` só contém os deltas do `application.yml`, e cada valor bate com o default declarado no compose.

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/<app>
    username: <app>
    password: <app>
  security:
    oauth2:
      client:
        registration:
          keycloak:
            client-secret: dev-secret
        provider:
          keycloak:
            issuer-uri: http://localhost:9080/realms/basis
  cloud:
    stream:
      rabbit:
        default:
          consumer:
            declare-exchange: true
            bind-queue: true
            auto-bind-dlq: true

logging:
  level:
    br.com.basis.<app>: DEBUG
```

### RabbitMQ não aparece aqui — de propósito

Os defaults do Spring Boot (`localhost:5672`, `guest`/`guest`, vhost `/`) são exatamente o que o container sobe com `RABBITMQ_DEFAULT_USER: guest` / `RABBITMQ_DEFAULT_PASS: guest`. Declarar `spring.rabbitmq.*` no dev é redeclarar default — o vhost dedicado e as credenciais reais só existem em prod, vindos de env var (ver `basis-k8s-deploy`).

Em dev o **SCS é dono da topologia** (`declare-exchange`/`bind-queue`/`auto-bind-dlq` em `true`), ao contrário de prod, onde os CRDs do operator são donos. Ver [`scs-rabbitmq.md`](scs-rabbitmq.md).

### Anti-padrões no `application-dev.yml`

- **Apontar para infra compartilhada/remota** (banco de homologação, Keycloak do SSO) com credencial real no arquivo. Além de virar segredo versionado, quebra o "clone e roda" e faz um dev derrubar o ambiente do outro. `dev` = compose local, sempre.
- **URL/credencial comentada** com a alternativa "de verdade" logo abaixo — o arquivo deixa de ter uma configuração válida e vira um menu de edição manual.
- **Credencial forte em dev** — não protege nada (a porta só escuta em `127.0.0.1`) e só atrapalha. `<app>`/`<app>`, `guest`/`guest`, `admin`/`admin` são preferíveis por serem obviamente descartáveis.
- **Segredo de prod em qualquer profile** — prod não tem default; tudo vem de env var.

## Sobe o ambiente

```bash
docker compose up -d              # aguarda healthchecks
./mvnw spring-boot:run -Dspring-boot.run.profiles=dev
```

O `spring-boot-docker-compose` (que sobe o compose junto com a app) é opcional e não é o padrão: ele amarra o ciclo de vida do Keycloak/Postgres ao restart da app, o que atrapalha em desenvolvimento com hot reload. Se for usado, deixar `spring.docker.compose.enabled: false` no `application-dev.yml` por padrão.
