---
name: basis-spring-app
description: Use when starting, extending, or refactoring a Basis Spring application — Java LTS + Maven + Spring (latest stable) + Spring Modulith, configuration via yaml + env vars + @ConfigurationProperties under the `application.*` prefix, Postgres + Flyway always, RabbitMQ via Spring Cloud Stream, web stack Thymeleaf + HTMX + Tailwind + DaisyUI. Activate for new modules, configuration cleanup, async messaging wiring, or web/frontend build questions.
---

# Basis Spring Application

Padrões da Basis para apps Spring. Pareada com `basis-k8s-deploy` (esta documenta o lado dev; aquela documenta o lado ops/infra).

## 1. Stack default (sempre, sem exceção)

- **Java**: LTS mais recente (em 04/2026: 25)
- **Build**: Maven (nunca Gradle — não há benefício para nossos casos)
- **Spring**: estável mais recente (em 04/2026: Spring 4.0)
- **Modulith**: versão pareada com Spring (em 04/2026: 2.0)
- **Banco**: PostgreSQL
- **Migrações**: Flyway (sem exceção — todo sistema TEM ferramenta de migração)
- **Persistência**: Spring Data JDBC > JPA para novos projetos
- **Mensageria**: RabbitMQ via Spring Cloud Stream (SCS)
- **Web (quando aplicável)**: Thymeleaf + HTMX + Tailwind + DaisyUI; alternativamente Angular
- **Auth (quando autenticada)**: Keycloak (realm `basis`) via OIDC, registration sempre `keycloak`, autorização por client roles
- **Observability**: Spring Boot Actuator (obrigatório — health probes pra K8s)

## 2. Esqueleto de projeto

- Multi-módulo: `<app>-domain`, `<app>-core`, `<app>-ingress` quando aplicável
- Parent pom + Modulith BOM
- Plugins essenciais:
  - `spring-boot-maven-plugin`
  - `jib-maven-plugin` — para gerar imagem com tag CalVer (passada via property)
  - `frontend-maven-plugin` — quando há build de frontend (Tailwind, etc.)

## 3. Configuração — princípio: usar TUDO que o Spring oferece

### Hierarquia
- `application.yml`: defaults env-agnostic, conteúdo válido pra qualquer ambiente
- `application-{profile}.yml`: SÓ os deltas do profile (`dev`, `prod`, etc.)
- Env vars: sobrepõem qualquer yml via Spring relaxed binding
- `@ConfigurationProperties`: tipa e valida o config no código

### Convenção de prefixo (Basis)
- Sempre `application.*` para ConfigurationProperties da aplicação (não o nome da app)
- Env var equivalente: `APPLICATION_*`
- Ex: `application.opnsense.base-url` ← `APPLICATION_OPNSENSE_BASE_URL`
- Vantagem: carga cognitiva menor, mesmo padrão em qualquer projeto

### Anti-padrões
- `key: ${ENV_VAR}` no yml quando o nome do env var pode seguir relaxed binding — deixa o yml limpo, Spring resolve sozinho
- Redeclarar defaults Spring (ex: `spring.rabbitmq.port: 5672`) — omitir
- Criar env var custom (`RABBITMQ_HOST`) quando o oficial cobre (`SPRING_RABBITMQ_HOST`)
- Misturar dev/prod no mesmo arquivo

### `@ConfigurationProperties`
- `record` immutable + `@EnableConfigurationProperties(MyProps.class)` no `@Configuration`
- Validações via Bean Validation quando o campo é obrigatório

## 4. Banco e migrações

- Flyway location: `db/migration`
- Naming: `V<timestamp>__<descricao_snake>.sql` (timestamp `YYYYMMDDHHmm`)
- **Modulith + Flyway**:
  - JDBC event publisher cria tabela `events` automaticamente — desabilitar `schema-initialization` se gerenciar via Flyway
  - Schemas separados por módulo: opcional, depende da estratégia adotada

## 5. Mensageria assíncrona com SCS

### Bindings funcionais
- `<name>-in-0` / `<name>-out-0` (Spring Cloud Function naming)
- `function.definition: name1;name2;...` agrega os consumers

### Topologia: ESCOLHER UM dono — não misturar
- **K8s dono** (recomendado em prod): topologia via CRDs RabbitMQ
  - SCS config: `default.consumer.bind-queue: false`, `auto-bind-dlq: false`
  - Main queue tem `x-dead-letter-exchange: DLX` + `x-dead-letter-routing-key: <destination>` definidos no CRD
- **SCS dono** (dev): SCS cria filas/DLQ automaticamente
  - SCS config: `default.consumer.bind-queue: true`, `auto-bind-dlq: true`
  - Default DLQ name = `<queue>.dlq`, default routing key = destination

## 6. Web stack (quando aplicável)

### Templates e HTMX
- Thymeleaf em `src/main/resources/templates/`
- Fragmentos `monitoring/fragments/<frag>.html` servidos por Controller pra `hx-target` requests
- Reutilizar layouts via `th:fragment`/`th:replace`

### Tailwind v4 + DaisyUI
- **Source `input.css` em `src/frontend/`** (FORA do classpath, senão acaba no jar)
- Output gerado em `target/classes/static/css/style.css` (vai pro jar via classpath, não versionado)
- JS vendored (htmx, list.js) também copiado pra `target/classes/static/js/`
- `package.json` build script:
  ```
  mkdir -p ./target/classes/static/css ./target/classes/static/js
  && tailwindcss -i ./src/frontend/input.css -o ./target/classes/static/css/style.css
  && cp node_modules/htmx.org/dist/htmx.min.js target/classes/static/js/
  && cp node_modules/list.js/dist/list.min.js target/classes/static/js/
  ```
- `frontend-maven-plugin` na fase `generate-resources` roda `npm run build`
- `.gitignore`: `src/main/resources/static/*` exceto `static/images/` (assets versionáveis)

## 7. Autenticação (Keycloak OIDC)

Apps web autenticadas usam Keycloak no realm `basis`, fluxo OIDC. Padrões:

- Spring Security registration **sempre** chamada `keycloak` — login fica em `/oauth2/authorization/keycloak`
- `provider.keycloak.issuer-uri: https://sso.apps.basis.com.br/realms/basis`
- Autorização por **client roles** (não realm roles), prefixadas com nome curto da app: `<APP>_USER`, `<APP>_ADMIN`
- Custom `OidcUserService` lê `resource_access.<clientId>.roles` e mapeia para `GrantedAuthority` com prefixo `ROLE_`
- `SecurityConstants` agrupa as roles em uma classe utility (evita typos espalhados)
- `/actuator/health/**` + estáticos sempre `permitAll()` (probes K8s precisam acesso anônimo)

Ver [`references/keycloak-oidc.md`](references/keycloak-oidc.md) — config completa, SecurityConfig template, setup do client no Keycloak.

## 8. Observability (Actuator)

**Obrigatório**. Sem `spring-boot-starter-actuator` no pom, as probes K8s caem em 404 e o pod entra em crash loop silencioso.

- Endpoints essenciais: `/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness`
- Liveness ≠ readiness: liveness só pode falhar se a JVM/Spring quebrar; readiness inclui dependências externas (DB, Rabbit, LDAP)
- Métricas Prometheus opcional via `micrometer-registry-prometheus` + `management.endpoints.web.exposure.include`

Ver [`references/actuator.md`](references/actuator.md) — config completa, integração com SecurityConfig e probes K8s.

## 9. Testes

- **Unit**: Mockito quando faz sentido (controllers, services puros)
- **Integração**: Testcontainers pra Postgres/RabbitMQ — não mockar infra que sobe local em segundos
- **APIs externas opacas** (AD/LDAP, Mailcow, Secullum, OPNsense): interface + impl real, teste manual contra infra; mocks só pros happy paths em controller tests

## 10. Interface com `basis-k8s-deploy`

### Env vars que o app espera
- `SPRING_PROFILES_ACTIVE=prod` (ativa `application-prod.yml`)
- `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`
- `SPRING_RABBITMQ_HOST`, `SPRING_RABBITMQ_USERNAME`, `SPRING_RABBITMQ_PASSWORD`, `SPRING_RABBITMQ_VIRTUAL_HOST`
- `APPLICATION_<CONFIGITEM>_*` para tudo que está em `application.*` no yml

### O que documentar pro deploy
- Quando criar uma nova ConfigurationProperties section, listar os env vars equivalentes em `references/env-vars.md`
- Profile `prod` deve assumir que infra-secrets vêm de env (não tem default)

## References disponíveis

- [`references/configuration-properties.md`](references/configuration-properties.md) — Convenção `application.*` + `APPLICATION_*`, hierarquia yml/env/profiles, `@ConfigurationProperties` records, anti-padrões
- [`references/scs-rabbitmq.md`](references/scs-rabbitmq.md) — SCS functional bindings, K8s-dono vs SCS-dono, retry e DLQ, inspeção/retry manual
- [`references/keycloak-oidc.md`](references/keycloak-oidc.md) — OIDC com registration `keycloak`, client roles, SecurityConfig template
- [`references/actuator.md`](references/actuator.md) — Health probes (liveness/readiness), integração com K8s, métricas Prometheus
- [`references/pom-skeleton.md`](references/pom-skeleton.md) — pom multi-módulo + plugins essenciais (jib, frontend-maven-plugin), parent BOM, módulos típicos
- [`references/frontend-build.md`](references/frontend-build.md) — package.json com output em `target/classes/static/`, `input.css` em `src/frontend/` (fora do classpath), `.gitignore` com exceção `images/`
- [`references/flyway-modulith-notes.md`](references/flyway-modulith-notes.md) — gotchas de schema com Modulith JDBC publisher, naming, baseline em legacy

## Skills upstream (sivalabs)

Repositório: <https://github.com/sivaprasadreddy/sivalabs-agent-skills>. Links abaixo pinados em SHA `ab6386d` pra evitar drift silencioso — atualizar SHA quando upstream lançar mudança relevante.

Áreas onde sivalabs cobre bem nosso padrão — usar direto, não duplicar:

- [`code-organization.md`](https://github.com/sivaprasadreddy/sivalabs-agent-skills/blob/ab6386d6a13a4b15e6145db8db43cb65e06f7bb9/skills/spring-boot/references/code-organization.md) — package layout domain-driven (combina com Modulith)
- [`spring-modulith.md`](https://github.com/sivaprasadreddy/sivalabs-agent-skills/blob/ab6386d6a13a4b15e6145db8db43cb65e06f7bb9/skills/spring-boot/references/spring-modulith.md) — Modulith básico
- [`spring-boot-maven-config.md`](https://github.com/sivaprasadreddy/sivalabs-agent-skills/blob/ab6386d6a13a4b15e6145db8db43cb65e06f7bb9/skills/spring-boot/references/spring-boot-maven-config.md) — plugins Spring Boot 4.x (complementa nosso `pom-skeleton.md`)
- [`archunit.md`](https://github.com/sivaprasadreddy/sivalabs-agent-skills/blob/ab6386d6a13a4b15e6145db8db43cb65e06f7bb9/skills/spring-boot/references/archunit.md) — testes de arquitetura
- [`thymeleaf.md`](https://github.com/sivaprasadreddy/sivalabs-agent-skills/blob/ab6386d6a13a4b15e6145db8db43cb65e06f7bb9/skills/spring-boot/references/thymeleaf.md) — templates
- [`spring-boot-webapp-testing-with-mockmvctester.md`](https://github.com/sivaprasadreddy/sivalabs-agent-skills/blob/ab6386d6a13a4b15e6145db8db43cb65e06f7bb9/skills/spring-boot/references/spring-boot-webapp-testing-with-mockmvctester.md) — testes de controller com MockMvcTester
- [`spring-boot-docker-compose.md`](https://github.com/sivaprasadreddy/sivalabs-agent-skills/blob/ab6386d6a13a4b15e6145db8db43cb65e06f7bb9/skills/spring-boot/references/spring-boot-docker-compose.md) — Docker Compose support

Áreas onde divergimos do sivalabs (NÃO usar a versão deles, vale o nosso):

- Persistência: eles usam **JPA**, nós usamos **Spring Data JDBC** (preferência Basis)
- REST: eles cobrem REST API completa; nós usamos Thymeleaf + HTMX (REST mínima quando necessária)
- Configuração: eles não cobrem o padrão `application.*` — nosso `references/configuration-properties.md` é canônico
- Mensageria: eles não cobrem SCS — nosso `references/scs-rabbitmq.md` é canônico
- Auth: eles não cobrem Keycloak/OIDC — nosso `references/keycloak-oidc.md` é canônico

Skill independente recomendada (instalar direto via [`install.sh`](https://github.com/sivaprasadreddy/sivalabs-agent-skills/blob/ab6386d6a13a4b15e6145db8db43cb65e06f7bb9/install.sh) do upstream):
- [`jspecify`](https://github.com/sivaprasadreddy/sivalabs-agent-skills/blob/ab6386d6a13a4b15e6145db8db43cb65e06f7bb9/skills/jspecify/SKILL.md) — adiciona null-safety com `@NullMarked` + ErrorProne+NullAway. Drop-in, usar como está.
