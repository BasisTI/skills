---
name: basis-spring-app
description: Use when starting, extending, or refactoring a Basis Spring application — Java LTS + Maven + Spring (latest stable) + Spring Modulith, configuration via yaml + env vars + @ConfigurationProperties under the `application.*` prefix, Postgres + Flyway always, RabbitMQ via Spring Cloud Stream, web stack Thymeleaf + HTMX + Tailwind + DaisyUI, local dev via Docker Compose (Keycloak on the app's Postgres), startup banner and DEBUG logging at entry points, Modulith structure tests. Activate for new modules, configuration cleanup, async messaging wiring, local dev environment setup, or web/frontend build questions.
---

# Basis Spring Application

Padrões da Basis para apps Spring. Pareada com `basis-k8s-deploy` (esta documenta o lado dev; aquela documenta o lado ops/infra), com `basis-java-code-standards` (como o código Java é escrito dentro dela) e, quando a app serve mais de um cliente no mesmo banco, com `basis-multi-tenant` (isolamento por `tenant_id` e Row Level Security). Quando a app fala com o **SGO** — criar ocorrência, ler `createmeta`, escrever TableGrid, subir anexo —, o cliente e as armadilhas do Jira 6.3.13 estão em `basis-sgo-jira`.

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
- `application-{profile}.yml`: SÓ os deltas do profile
- **Os profiles de ambiente são dois: `dev` e `prod`. Não existe `staging`.** Staging e produção
  rodam o **mesmo** profile `prod`; o que difere entre os dois é o overlay do kustomize — env
  vars, secrets, réplicas, host do ingress —, nunca um arquivo de configuração da aplicação.
  Medido nos 8 deployments Spring do `iac/argocd-apps`: todos declaram `SPRING_PROFILES_ACTIVE`
  em `base/` com `prod` (às vezes `prod,kubernetes` ou `prod,api-docs,kubernetes`), e nenhum
  overlay o sobrepõe. Em 5 repositórios de aplicação não existe um único `application-staging.*`
- Além desses, só profiles **de recurso**, não de ambiente: `test`, `tls`, `sgo`, `spike`. O
  critério é "liga um pedaço", não "é um ambiente"
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
- **Chave aninhada sob o pai errado.** O Spring liga por caminho completo: um `spring:` indentado dentro de `server:` vira propriedade desconhecida de `server` e é **ignorado sem aviso** — sem erro, sem log, sem falha de startup. Num app real, `datasource`, `flyway`, `modulith` e `mail` viveram meses sob `server:` e nunca foram aplicados; a app subia com os defaults e ninguém percebia. Config nova se confere pelo efeito (`/actuator/env`, o log do Flyway, a URL que apareceu no banner), nunca pela presença da linha no arquivo
- **Bloco de config de tecnologia que o projeto não usa** (`spring.jpa` num projeto Data JDBC): não quebra e engana quem lê depois

### `@ConfigurationProperties`
- `record` immutable + `@EnableConfigurationProperties(MyProps.class)` no `@Configuration`
- Validações via Bean Validation quando o campo é obrigatório

## 4. Banco e migrações

- Flyway location: `db/migration`
- Naming: `V<timestamp>__<descricao_snake>.sql` (timestamp `YYYYMMDDHHmm`)
- **O Flyway compara versão por partes, numericamente — não como texto.** É o que faz o esquema de timestamp conviver com numeração antiga: `V202608131000` vem depois de `V6` porque 202608131000 > 6, e não pela ordem alfabética, que colocaria `V6` por último. Também é por isso que `V1.10` vem depois de `V1.9`, ao contrário do que a ordenação do `ls` sugere
- **Flyway é a única fonte de verdade do schema.** Nenhum componente cria tabela em runtime — nem framework, nem `ddl-auto`, nem script de inicialização. Não é preferência: schema criado fora do Flyway não tem versão, não aparece em revisão de MR e não passa pelas regras que as migrations aplicam
- **Modulith + Flyway** — na criação da aplicação, não depois:
  ```yaml
  spring:
    modulith:
      events:
        jdbc:
          schema-initialization:
            enabled: false   # a tabela event_publication vem do Flyway
  ```
  O publisher de eventos JDBC cria a tabela `event_publication` sozinho por default. Com os dois criando, há race na inicialização; e a estrutura da tabela fica sem controle de versão, o que dói no rolling deploy e em qualquer release que mude as colunas dela. **Vem desligado desde o primeiro commit** — habilitado, a tabela já existe quando alguém percebe, e passa a ser correção de produção em vez de linha de yaml. O DDL entra na baseline; o schema muda a cada release do Modulith, então confira as colunas na doc da versão em uso
  - Schemas separados por módulo: opcional, depende da estratégia adotada
- **Declare qual migration serve de modelo.** Quem vai criar tabela abre a mais recente e copia; se a mais recente for a que esqueceu alguma coisa, o esquecimento se propaga. Nomeie o arquivo-modelo no `AGENTS.md` — "a mais recente" não é instrução, é sorte
- **App multi-tenant tem skill própria.** Isolamento por `tenant_id`, Row Level Security, ordem das migrations de RLS e chave composta `(tenant_id, id)` estão em **`basis-multi-tenant`**. O que é específico daqui: a role do Flyway e a role da aplicação **não são a mesma**, e a tabela `event_publication` do Modulith entra na conta quando carrega `tenant_id`

### Transações — `readOnly` por default na classe

**`@Transactional(readOnly = true)` na classe de serviço, e `@Transactional` explícito só nos métodos que escrevem.** O ganho não é evitar digitação: é inverter o default para o lado seguro. Sem isso, método de leitura sem anotação nenhuma roda fora de transação e ninguém percebe — não dá erro, não aparece em log, e a consequência só existe em cenário que o teste unitário não cobre.

```java
@Service
@Transactional(readOnly = true)
public class FuncionarioService {

    public List<FuncionarioDTO> listar() { ... }          // herda readOnly

    @Transactional
    public FuncionarioDTO criar(NovoFuncionario cmd) { ... }  // override explícito
}
```

O mecanismo que faz disso um guarda-corpo, e não documentação: a anotação mais interna vence, então **esquecer o override num método de escrita produz falha, não corrupção**. Com routing de datasource, a escrita vai parar na réplica e estoura; sem routing, o Spring propaga o flag via `Connection.setReadOnly(true)` e o driver do Postgres marca a transação como read-only, então o `INSERT` falha com `cannot execute INSERT in a read-only transaction`. Nos dois casos o erro aparece no primeiro teste que exercitar o método — que é o momento certo.

- `readOnly = true` é **pré-requisito** para roteamento primário/réplica via `AbstractRoutingDataSource`, que decide pelo `TransactionSynchronizationManager`. Adotar o padrão agora deixa a porta aberta mesmo em app que hoje tem um banco só
- Em **Spring Data JDBC** não há dirty checking para pular, então o ganho é o guarda-corpo mais o roteamento — o argumento de performance do mundo Hibernate não se aplica aqui
- **Não anote a classe inteira com `@Transactional` sem `readOnly`** para "resolver o esquecimento": isso não é default seguro, é escrita liberada em todo método
- Confirme o comportamento no projeto com um teste que tente escrever num método sem override. Se ele passar, o flag não está chegando na conexão e o guarda-corpo não existe
- Referência: [Read-write and read-only transaction routing with Spring](https://vladmihalcea.com/read-write-read-only-transaction-routing-spring/), Vlad Mihalcea

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

### Tratamento de exceção em app que serve HTML

- **Não use `@RestControllerAdvice` numa app que serve HTML.** Ele é `@ControllerAdvice` + `@ResponseBody`: o retorno do handler é serializado como corpo da resposta, não resolvido como view. Numa app HTMX, uma exceção de negócio passa a **injetar JSON dentro do DOM**, no lugar onde o fragmento deveria entrar — a tela mostra `{"timestamp":...,"message":...}` em vez da mensagem de erro. Em app mista, separe: `@RestControllerAdvice` com `@ControllerAdvice(basePackages = ...)` limitado aos pacotes de API, e um `@ControllerAdvice` de view para o resto
- **Prefira exceção própria mapeada no handler global a anotação por endpoint com lista de exceções.** Anotação de marcação com opt-out (`@ExigeContexto` em quase tudo, mais uma lista dos que não exigem) cria uma **segunda lista de endpoints especiais ao lado do `permitAll` do `SecurityConfig`** — duas fontes de verdade sobre a mesma pergunta, que divergem na primeira vez que alguém mexe só numa. Uma exceção lançada onde o contexto falta, mapeada uma vez no handler global, cobre todos os casos sem lista nenhuma
- Se a separação precisar mesmo ser explícita, torne-a estrutural: um prefixo de path (`/api/publico/**`) é visível no `SecurityConfig`, no log e no roteador, em vez de estar espalhado em anotação

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
- Ler a porta de `local.server.port` e os profiles do `Environment` — é a porta efetiva e o profile realmente ativo; `server.port` é só o configurado, e sai `null` quando o yml não o declara
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

- **Credencial de seed documentada no README.** Senha de usuário de teste que só existe como hash na migration é senha que ninguém consegue enunciar — e alguém entrando no projeto vai tentar adivinhá-la. Gere o hash a partir de uma senha declarada (`admin123`, `user123`), com o encoder do próprio projeto, e escreva qual é

### Anti-padrões
- `application-dev.yml` apontando para infra compartilhada/remota com credencial real — vira segredo versionado, quebra o "clone e roda" e um dev derruba o ambiente do outro
- URL/credencial comentada com a alternativa "de verdade" logo abaixo — o profile deixa de ter config válida
- Senha forte em dev (a porta só escuta em `127.0.0.1`); `<app>`/`<app>`, `guest`/`guest`, `admin`/`admin` são melhores por serem obviamente descartáveis
- **`spring-boot-docker-compose` no classpath.** O starter publica um `JdbcConnectionDetails` a partir do `compose.yaml`, e esse bean tem **precedência sobre `spring.datasource.*`** — a app conecta onde o starter mandou, não onde o yml diz. Consequências: erro de configuração do datasource fica mascarado (o yml quebrado "funciona"), e não há como apontar a app para uma role diferente da do compose, o que impede o desenho de RLS da `basis-multi-tenant`. O fluxo desta skill (§10) não depende dele — `docker compose up -d` explícito é mais previsível
- **Deletar migration sem `mvn clean`.** As antigas continuam em `target/classes/db/migration` e o Flyway as aplica de lá. Rebaseline em dev é `./mvnw clean` **junto** com `docker compose down -v`; sem os dois, o banco reconstruído não é o que o repositório descreve

Ver [`references/local-dev-compose.md`](references/local-dev-compose.md) — compose completo, `init.sql`, `application-dev.yml`, comando de export do realm.

## 11. Testes

- **Unit**: Mockito quando faz sentido (controllers, services puros)
- **Integração**: Testcontainers pra Postgres/RabbitMQ — não mockar infra que sobe local em segundos
- **APIs externas opacas** (AD/LDAP, Mailcow, Secullum, OPNsense): interface + impl real, teste manual contra infra; mocks só pros happy paths em controller tests
- **Suíte só de unitário com repositório mockado não cobre mapeamento objeto-relacional.** Trezentos testes verdes não dizem nada sobre `@Id` composto, `@Embedded`, conversor custom ou RLS — e é exatamente aí que uma refatoração de persistência quebra. Antes de mexer em id, herança de entidade ou policy de banco, o pré-requisito é ter pelo menos um IT que salve, busque e liste contra Postgres real
- **Não fixe versão que o parent do Spring Boot já gerencia.** Versão presa envelhece sozinha e o sintoma não aponta para ela: `failsafe` preso em 3.1.2 com o `surefire` em 3.5.6 falha por provider ausente no repositório local; `testcontainers-bom` preso em 1.18.3 (2023) falha contra engine Docker atual com erro de API. Nos dois, a correção é **remover** a versão, não escolher outra
- **`*IT.java` fora de pacote de produção.** Os testes ArchUnit varrem os pacotes de domínio por reflexão; um IT deixado ali é encontrado e **dispara o container durante a suíte unitária**, que passa a depender de Docker. O IT vai para pacote próprio
- Antes de escrever o primeiro IT, confira o pom: `failsafe` costuma já estar configurado, incluindo `**/*IT.java`, e nunca ter rodado por não existir nenhum

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

