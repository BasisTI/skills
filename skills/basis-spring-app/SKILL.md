---
name: basis-spring-app
description: Use when starting, extending, or refactoring a Basis Spring application — Java LTS + Maven + Spring (latest stable) + Spring Modulith, configuration via yaml + env vars + @ConfigurationProperties under the `application.*` prefix, Postgres + Flyway always, RabbitMQ via Spring Cloud Stream, web stack Thymeleaf + HTMX + Tailwind + DaisyUI, local dev via Docker Compose (Keycloak on the app's Postgres), startup banner and DEBUG logging at entry points, Modulith structure tests. Activate for new modules, configuration cleanup, async messaging wiring, local dev environment setup, or web/frontend build questions.
---

# Basis Spring Application

Padrões da Basis para apps Spring. Pareada com `basis-k8s-deploy` (esta documenta o lado dev; aquela documenta o lado ops/infra) e com `basis-java-code-standards` (como o código Java é escrito dentro dela).

## 1. Stack default (sempre, sem exceção)

- **Java**: LTS mais recente (em 04/2026: 25)
- **Build**: Maven (nunca Gradle — não há benefício para nossos casos)
- **Spring**: estável mais recente (em 07/2026: Spring 4.1)
- **Modulith**: versão pareada com Spring (em 07/2026: 2.1)
- **Banco**: PostgreSQL 17
- **Migrações**: Flyway (sem exceção — todo sistema TEM ferramenta de migração)
- **Persistência**: Spring Data JDBC > JPA para novos projetos
- **Mensageria**: RabbitMQ via Spring Cloud Stream (SCS)
- **Web (quando aplicável)**: Thymeleaf + HTMX + Tailwind + DaisyUI; alternativamente Angular
- **Auth (quando autenticada)**: Keycloak (realm `basis`) via OIDC, registration sempre `keycloak`, autorização por client roles
- **Observability**: Spring Boot Actuator (obrigatório — health probes pra K8s)
- **Dev local**: Docker Compose com Postgres + RabbitMQ + Keycloak (quando autenticada), profile `dev` pronto pra rodar sem editar config

## 2. Esqueleto de projeto

- Multi-módulo: `<app>-domain`, `<app>-core` quando aplicável
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

O padrão de UI (layout com sidebar, tabelas com cabeçalho/rodapé fixos, formulários, página de erro, tema `caramellatte`, build de CSS/JS) está na skill **`basis-web-frontend`**. Resumo do que a app Spring precisa saber:

- Thymeleaf em `src/main/resources/templates/`, layout único em `layout.html` (`th:fragment="layout(content, activeMenu)"`)
- Fragmentos HTMX servidos por Controller dedicado, devolvendo só o trecho (`~{::fragmento}`)
- Tema DaisyUI **`caramellatte`**; `input.css` em `src/frontend/` (fora do classpath), output gerado em `target/classes/static/`
- `frontend-maven-plugin` na fase `generate-resources` roda `npm run build`
- `.gitignore`: `src/main/resources/static/*` exceto `static/images/` (assets versionáveis)
- `templates/error.html` **obrigatório** — sem ele a app cai na Whitelabel Error Page do Spring Boot; `server.error.whitelabel.enabled: false` e `include-stacktrace: never`
- `@ControllerAdvice` com `@ModelAttribute` para `appVersion` (de `BuildProperties`) e `currentUser` (do `OidcUser`), que o layout consome em toda página

## 7. Autenticação (Keycloak OIDC)

Apps web autenticadas usam Keycloak no realm `basis`, fluxo OIDC. Padrões:

- Spring Security registration **sempre** chamada `keycloak` — login fica em `/oauth2/authorization/keycloak`
- `provider.keycloak.issuer-uri: https://sso.apps.basis.com.br/realms/basis`
- Autorização por **client roles** (não realm roles), prefixadas com nome curto da app: `<APP>_USER`, `<APP>_ADMIN`
- Custom `OidcUserService` lê `resource_access.<clientId>.roles` e mapeia para `GrantedAuthority` com prefixo `ROLE_`
- `SecurityConstants` agrupa as roles em uma classe utility (evita typos espalhados)
- `/actuator/health/**` + estáticos sempre `permitAll()` (probes K8s precisam acesso anônimo)

Ver [`references/keycloak-oidc.md`](references/keycloak-oidc.md) — config completa, SecurityConfig template, setup do client no Keycloak.
Para Keycloak local (compose + import do realm `basis`), ver §10 e [`references/local-dev-compose.md`](references/local-dev-compose.md).

## 8. Observability (Actuator)

**Obrigatório**. Sem `spring-boot-starter-actuator` no pom, as probes K8s caem em 404 e o pod entra em crash loop silencioso.

- Endpoints essenciais: `/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness`
- Liveness ≠ readiness: liveness só pode falhar se a JVM/Spring quebrar; readiness inclui dependências externas (DB, Rabbit, LDAP)
- Métricas Prometheus opcional via `micrometer-registry-prometheus` + `management.endpoints.web.exposure.include`

Ver [`references/actuator.md`](references/actuator.md) — config completa, integração com SecurityConfig e probes K8s.

## 9. Logging e depuração

Convenções gerais de log (SLF4J, `{}`, níveis, nada sensível) estão em `basis-java-code-standards` §9. O que é específico de app Spring:

### Banner de startup — obrigatório
- Após `app.run(...)`, logar bloco com nome da aplicação, URL local, URL externa, context path e **profiles ativos**
- Responde na hora "qual app, em que porta, com que profile" sem acesso ao pod
- Ler `server.port` e profiles do `Environment` (não do yml) — reflete a porta efetiva e o profile realmente ativo
- Nada de segredo no banner

### DEBUG nos pontos de entrada — obrigatório
- Todo ponto onde estímulo externo entra loga em `DEBUG` o que chegou: Controller, consumer SCS, `@Scheduled`, listener de evento Modulith, webhook
- Identificador e campos que direcionam o fluxo — não o payload inteiro (payload em `TRACE`), nunca PII/segredo
- Consumer loga também o desfecho (processado/rejeitado + motivo) — mensagem sem contraparte no log é o sintoma de consumer travado

### DEBUG em processamento complexo
- Método com várias etapas, chamada externa ou regra densa: um `DEBUG` no início (entrada) e um no fim (resultado, e duração quando útil), com o mesmo identificador nas duas linhas
- Critério: se falhar em produção, o log de erro sozinho diz *com que entrada* e *até onde foi*? Se não, precisa do par
- Duração em `DEBUG` é diagnóstico; o que precisa de acompanhamento contínuo vai para Micrometer/Actuator

### Níveis
- `application.yml`: `br.com.basis.<app>: INFO`; `application-dev.yml`: `DEBUG`
- Em prod sobe para `DEBUG` sem redeploy via `LOGGING_LEVEL_*` ou `/actuator/loggers` — é para isso que os `DEBUG` existem no código
- `DEBUG`/`TRACE` de pacote de terceiro é investigação pontual, não config commitada (`org.springframework.jdbc.core: TRACE` loga valores de parâmetro de SQL)

Ver [`references/logging-e-banner.md`](references/logging-e-banner.md) — código do banner, exemplos por tipo de entry point, guard `isDebugEnabled`.

## 10. Ambiente de desenvolvimento local

Meta: `git clone` → `docker compose up -d` → `mvn spring-boot:run -Dspring-boot.run.profiles=dev`, **sem editar arquivo de configuração**. `compose.yaml` e `application-dev.yml` são escritos como par — os valores do yml são os defaults declarados no compose.

- `compose.yaml` na raiz: Postgres, RabbitMQ, Keycloak (quando autenticada), + o que a app usar (MinIO, GreenMail, Ollama). Portas sempre em `127.0.0.1`, healthcheck em todo serviço
- **Keycloak usa o Postgres da própria aplicação**, em banco/role separados (`keycloak`/`keycloak`) criados via `docker/postgres/init.sql`. Motivo principal: permite rodar comandos de administração no container com o Keycloak no ar — em especial `kc.sh export` do realm, que com o dev-file (H2) esbarra no lock do arquivo. De quebra: um container de banco só, estado sobrevivendo ao `down`, e mesma topologia de prod
- Realm `basis` importado de `./docker/keycloak` via `--import-realm`; partir de [`references/basis-realm-dev.json`](references/basis-realm-dev.json) (client `<app>-admin`, client roles `<APP>_USER`/`<APP>_ADMIN`, usuários `admin`/`admin` e `user`/`user`)
- **Export de realm nunca vai cru para o repo** — carrega chave RSA privada, segredos HMAC/AES, client secret e hashes de senha
- `application-dev.yml` traz datasource apontando para o compose (`localhost:5432`, usuário/senha = nome da app) e o issuer local (`http://localhost:9080/realms/basis`)
- **RabbitMQ não aparece no `application-dev.yml`**: os defaults do Spring (`localhost:5672`, `guest`/`guest`, vhost `/`) já batem com o container. Vhost dedicado e credencial real só em prod, via env var
- Em dev o SCS é dono da topologia (`declare-exchange`/`bind-queue`/`auto-bind-dlq: true`); em prod os CRDs do operator são

### Anti-padrões
- `application-dev.yml` apontando para infra compartilhada/remota com credencial real — vira segredo versionado, quebra o "clone e roda" e um dev derruba o ambiente do outro
- URL/credencial comentada com a alternativa "de verdade" logo abaixo — o profile deixa de ter config válida
- Senha forte em dev (a porta só escuta em `127.0.0.1`); `<app>`/`<app>`, `guest`/`guest`, `admin`/`admin` são melhores por serem obviamente descartáveis

Ver [`references/local-dev-compose.md`](references/local-dev-compose.md) — compose completo, `init.sql`, `application-dev.yml`, comando de export do realm.

## 11. Testes

- **Unit**: Mockito quando faz sentido (controllers, services puros)
- **Integração**: Testcontainers pra Postgres/RabbitMQ — não mockar infra que sobe local em segundos
- **APIs externas opacas** (AD/LDAP, Mailcow, Secullum, OPNsense): interface + impl real, teste manual contra infra; mocks só pros happy paths em controller tests

### Estrutura (Modulith) — obrigatório quando a app usa Modulith
- `ApplicationModules.of(<App>Application.class).verify()` num teste — pega acesso a pacote `internal` de outro módulo, ciclo entre módulos e dependência não declarada
- Sem esse teste, "módulo" é só convenção de pasta: o build aceita qualquer `import` entre pacotes internos e a modularidade se dissolve sem sinal nenhum
- `Documenter` no mesmo teste gera os diagramas em `target/modulith-docs` — documentação que não desatualiza
- Fronteiras críticas do domínio declaradas explicitamente, principalmente as dependências que **não podem existir** (`containsModuleNamed(...)` com `isFalse()`); alternativa declarativa: `@ApplicationModule(allowedDependencies = ...)` no `package-info.java`
- `@ApplicationModuleTest` + `Scenario` para integração por módulo e para testar evento sem `Thread.sleep`

Ver [`references/modulith-tests.md`](references/modulith-tests.md) — teste base, fronteiras de domínio, `@ApplicationModuleTest`.

## 12. Interface com `basis-k8s-deploy`

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
- Build de frontend, layout, tabelas, formulários e páginas de erro: skill **`basis-web-frontend`**
- [`references/flyway-modulith-notes.md`](references/flyway-modulith-notes.md) — gotchas de schema com Modulith JDBC publisher, naming, baseline em legacy
- [`references/logging-e-banner.md`](references/logging-e-banner.md) — banner de startup, DEBUG em entry points e processamento complexo, níveis por ambiente
- [`references/local-dev-compose.md`](references/local-dev-compose.md) — `compose.yaml`, Keycloak no Postgres da app, `init.sql`, `application-dev.yml` espelhando o compose, export do realm
- [`references/basis-realm-dev.json`](references/basis-realm-dev.json) — realm `basis` mínimo para import em dev: client `<app>-admin`, client roles, usuários de teste
- [`references/modulith-tests.md`](references/modulith-tests.md) — `ApplicationModules.verify()`, `Documenter`, fronteiras de domínio, `@ApplicationModuleTest`

