# Configuração: yaml + env vars + @ConfigurationProperties

Padrão Basis pra configurar aplicações Spring. Princípio: usar TUDO que o Spring oferece — não reinventar.

## Convenção de prefixo: `application.*`

ConfigurationProperties da aplicação usam SEMPRE o prefixo `application.*`, independente do nome do projeto.

- Property no yml: `application.opnsense.base-url`
- Env var equivalente (Spring relaxed binding): `APPLICATION_OPNSENSE_BASE_URL`

Vantagem: carga cognitiva zero ao trocar de projeto, env vars têm formato previsível, e snippets de deploy são reutilizáveis.

> Para infra do próprio Spring (datasource, rabbitmq, mail) o prefixo é `spring.*` — convenção do framework, não mexer.

## Hierarquia de fontes

1. `application.yml` — defaults env-agnostic, válidos em qualquer ambiente
2. `application-{profile}.yml` — só os DELTAS do profile (`dev`, `prod` — ver anti-padrão 5)
3. Env vars — sobrepõem qualquer yml via Spring relaxed binding
4. `@ConfigurationProperties` — tipa e valida no código

## Spring relaxed binding

Spring mapeia env vars pra properties trocando `_` por `.` ou `-`, e fazendo lowercase:

| Property | Env var |
|----------|---------|
| `spring.datasource.url` | `SPRING_DATASOURCE_URL` |
| `spring.rabbitmq.host` | `SPRING_RABBITMQ_HOST` |
| `application.opnsense.base-url` | `APPLICATION_OPNSENSE_BASE_URL` |
| `application.secullum.id-banco-selecionado` | `APPLICATION_SECULLUM_ID_BANCO_SELECIONADO` |

Doc: <https://docs.spring.io/spring-boot/reference/features/external-config.html#features.external-config.typesafe-configuration-properties.relaxed-binding>

## Anti-padrões

### 1. `key: ${ENV_VAR}` redundante

❌ Errado:
```yaml
spring:
  datasource:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD}
application:
  opnsense:
    base-url: ${OPNSENSE_BASE_URL}
```

✅ Certo (omitir tudo que vem de env e segue convenção):
```yaml
# Nada aqui — env vars SPRING_DATASOURCE_*, APPLICATION_OPNSENSE_*
# Spring resolve sozinho via relaxed binding
```

Use `${ENV_VAR}` no yml SOMENTE quando o nome do env var não pode seguir convenção (ex: integração com sistema legado que exige nome específico).

### 2. Redeclarar defaults Spring

❌ Errado:
```yaml
spring:
  rabbitmq:
    port: 5672              # default Spring já é 5672
    listener:
      simple:
        prefetch: 250       # default Spring já é 250
```

✅ Certo: omitir, deixar default do framework.

### 3. Renomear env vars sem necessidade

❌ Errado: criar `RABBITMQ_HOST` (nome custom) quando Spring já oferece `SPRING_RABBITMQ_HOST`.

✅ Certo: usar o nome canônico do Spring → não precisa de `${RABBITMQ_HOST}` no yml.

### 4. Misturar dev/prod no mesmo arquivo

❌ Errado: `application.yml` com `if profile == prod` via @Conditional, ou ifs em código.

✅ Certo: dois arquivos, `application-dev.yml` e `application-prod.yml`, com APENAS os deltas. Default do `application.yml` vale pra tudo.

### 5. Inventar um profile `staging`

❌ Errado: ver `overlays/staging` e `overlays/production` no kustomize e concluir que a aplicação
precisa de `application-staging.yml` ao lado do `application-prod.yml`.

**Staging e produção rodam o mesmo profile `prod`.** O overlay do kustomize é que os separa, e ele
separa o que é de ambiente: env var, secret, número de réplicas, host do ingress, tamanho de
volume. Nada disso é arquivo de configuração da aplicação — todos já entram por env var, via
relaxed binding, sem `${VAR}` no yaml (anti-padrão 1).

Estado medido no `iac/argocd-apps`: os 8 deployments Spring declaram `SPRING_PROFILES_ACTIVE` em
`base/`, com `prod`, `prod,kubernetes` ou `prod,api-docs,kubernetes` — e **nenhum overlay
sobrepõe esse valor**. Em 5 repositórios de aplicação não existe nenhum `application-staging.*`.

Um profile a mais custa mais do que parece: ele cria um caminho de configuração que **só existe
em staging**, então o artefato que passou no teste não é o artefato que vai para produção. O erro
aparece no deploy de produção, que é o pior lugar para descobri-lo.

✅ Certo: dois profiles de ambiente (`dev` para a máquina do desenvolvedor, `prod` para tudo que
roda no cluster) e, ao lado deles, profiles **de recurso** — `test`, `tls`, `sgo`, `spike`. O
critério que separa os dois grupos: profile de recurso *liga um pedaço*; profile de ambiente
*descreve onde a aplicação está*. Só o segundo grupo é fechado.

**Variante legítima: nenhum profile.** Há app em que o `application.yml` já é a configuração de
produção e os profiles são todos desvios dela. Aí o deployment não declara
`SPRING_PROFILES_ACTIVE` nenhum — e isso precisa estar escrito no manifesto, senão o próximo
leitor "conserta" a ausência:

```yaml
# Sem SPRING_PROFILES_ACTIVE: o `application.yml` do repositório JÁ É a configuração de
# produção. Os profiles que existem são desvios dela -- `dev` (compose local), `sgo`
# (credencial), `spike` (escrita manual), `test`. Ativar qualquer um aqui trocaria
# produção por um deles.
```

### 6. `@ConditionalOnProperty` como chave de segurança em app que compila nativa

❌ Errado: proteger uma rotina perigosa — a que escreve num sistema externo compartilhado, a que
manda e-mail, a que roda expurgo — com `@ConditionalOnProperty` e achar que a variável de
ambiente decide em runtime.

A condição do Spring é avaliada **uma vez só**. Numa imagem nativa, essa vez é o **build**: o
`process-aot` roda sem perfil e sem variável de ambiente, o `matchIfMissing` vale, o bean entra
congelado na imagem — e a chave deixa de ter qualquer efeito depois. Medido em 2026-08-21 numa
imagem nativa de um app da Basis: com a chave em `false`, o agendador protegido rodou assim
mesmo; na JVM, não rodava.

✅ Certo: o bean sempre sobe, e **quem decide é o método**.

```java
@Component
class AgendamentoEnvio {

    private final boolean ligado;

    AgendamentoEnvio(Envios envios, AppProperties props) {
        this.envios = envios;
        this.ligado = props.agendamento();
        if (!ligado) log.info("Consumidor da fila: DESLIGADO por configuração");
    }

    @Scheduled(fixedDelayString = "${application.intervalo-da-fila:30s}")
    void processarFila() {
        if (!ligado) return;
        envios.processarFila();
    }
}
```

`@ConditionalOnProperty` continua certo para **montagem** — qual implementação entra, qual
integração existe. O que ele não pode ser é a trava que separa staging de produção: uma proteção
que some conforme o formato do artefato é pior que proteção nenhuma, porque ninguém desconfia
dela.

## @ConfigurationProperties — pattern

Classes record imutáveis + `@EnableConfigurationProperties`:

```java
package com.basis.<app>.opnsense;

@ConfigurationProperties(prefix = "application.opnsense")
public record OpnsenseProperties(
        String baseUrl,
        String apiKey,
        String apiSecret,
        Long vpnId,
        String exportHostname,
        Integer exportPort,
        String caRef,
        Long groupId,
        Boolean verifySsl
) {}
```

```java
@Configuration
@EnableConfigurationProperties(OpnsenseProperties.class)
class OpnsenseConfig { /* ... */ }
```

Validação opcional via Bean Validation:

```java
@ConfigurationProperties(prefix = "application.opnsense")
@Validated
public record OpnsenseProperties(
        @NotBlank String baseUrl,
        @NotBlank String apiKey,
        @NotBlank String apiSecret,
        @NotNull Long vpnId,
        // ...
) {}
```

Spring valida na inicialização — falha rápido se config inválida.

## Estrutura yml recomendada

`application.yml` — defaults + bindings + lista de fluxos:
```yaml
spring:
  application:
    name: <app>-core
  flyway:
    enabled: true
  cloud:
    stream:
      bindings: { ... }
  # ZERO ${ENV_VAR}
```

`application-dev.yml` — defaults pra desenvolvimento local (docker-compose):
```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/<db>
    username: <app>
    password: <app>
  rabbitmq:
    host: localhost
    username: <app>
    password: <app>
  mail:
    host: localhost
    port: 1025         # mailpit
application:
  opnsense:
    base-url: https://vpn.basisti.com.br
    api-key: changeme
    # … defaults óbvios
```

`application-prod.yml` — só o que é prod-only e estável:
```yaml
spring:
  mail:
    host: smtp.basis.com.br
    port: 25
    properties:
      mail.smtp.auth: false
      mail.smtp.starttls.enable: false
application:
  ad:
    urls:
      - ldaps://saltinho.basis.com.br:636
      - ldaps://rome.basis.com.br:636
    base-dn: DC=basis,DC=com,DC=br
    # … defaults prod
  # nada com ${ENV_VAR} — segredos vêm via env
```

## Interface com deploy K8s

- **`envFrom: configMapRef`** pra valores não-sensíveis (`APPLICATION_*` de URLs, IDs, etc.)
- **`envFrom: secretRef`** pro conjunto de segredos (`APPLICATION_*` de credenciais)
- **`env: - name: ... valueFrom.secretKeyRef`** quando precisa pegar de secret gerenciado por operador (ex: Postgres Zalando — `SPRING_DATASOURCE_USERNAME` vem de `<user>.<cluster>.credentials.postgresql.acid.zalan.do`)

Ver `basis-k8s-deploy/references/operator-secret-cheatsheet.md`.
