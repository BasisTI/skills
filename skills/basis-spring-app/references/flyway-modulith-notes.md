# Flyway + Spring Modulith: gotchas

Notas práticas pra evitar problemas em apps Basis que usam Modulith com event publication via JDBC.

## Setup básico

`pom.xml`:
```xml
<dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-database-postgresql</artifactId>
</dependency>
```

`application.yml`:
```yaml
spring:
  flyway:
    enabled: true
```

Migrations em `src/main/resources/db/migration/V<N>__<nome>.sql`. Spring Boot auto-configura Flyway pra rodar antes da aplicação subir.

## Naming

Convenção Basis: `V<N>__<descricao_snake>.sql` onde `N` é sequencial inteiro (`V1__`, `V2__`, ...).

Alternativa: timestamp `V20260424123000__nome.sql` — útil em projetos grandes ou onde múltiplas branches geram migrations em paralelo. Para projeto novo, comece com sequencial; migre pra timestamp se houver colisão.

Exemplo do identity-hub:
```
V1__create_colaborador.sql
V2__create_processo.sql
V3__create_event_publication.sql
V4__add_dados_pessoais.sql
V5__add_chave_ocorrencia_jira.sql
V6__remove_bairro_telefone.sql
V7__fix_nascimento_sexo_types.sql
V8__evolve_processo.sql
```

## Modulith JDBC event publisher: criar a tabela manualmente

Modulith publica eventos de domínio numa tabela `event_publication`. Por padrão, Spring tenta inicializar via script SQL embutido. **Desabilite isso e crie a tabela via Flyway:**

`application.yml`:
```yaml
spring:
  modulith:
    events:
      jdbc:
        schema-initialization:
          enabled: false   # NÃO deixar Modulith criar — quem cria é Flyway
```

Migration manual (V3 do identity-hub):
```sql
CREATE TABLE event_publication
(
    id               UUID NOT NULL,
    listener_id      TEXT NOT NULL,
    event_type       TEXT NOT NULL,
    serialized_event TEXT NOT NULL,
    publication_date TIMESTAMP WITH TIME ZONE NOT NULL,
    completion_date  TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (id)
);

CREATE INDEX event_publication_serialized_event_hash_idx
    ON event_publication USING HASH (serialized_event);
CREATE INDEX event_publication_by_completion_date_idx
    ON event_publication (completion_date);
```

Schema atualizado em cada release Modulith — checar a doc da versão em uso pra confirmar colunas/índices.

Por que: `schema-initialization: true` causa conflito em rolling deploy se a tabela já existe; pior, perde controle de versão da estrutura do schema.

## Republish de eventos pendentes no startup

Quando o app reinicia com eventos não-completados na `event_publication`, Modulith pode reprocessar:

```yaml
spring:
  modulith:
    events:
      republish-outstanding-events-on-restart: true
      staleness:
        enabled: true
        check-interval: 5m       # quanto tempo antes de re-publicar
        duration: 15m            # threshold pra considerar stale
```

Cuidado: não habilitar em apps que requerem idempotência manual no consumer e não têm proteção contra duplicação. Pra Basis com SCS+RabbitMQ + retry: geralmente seguro.

## Modulith + multi-módulo

Cada módulo Modulith pode ter seu próprio `db/migration/<modulo>/V*.sql` se você dividir schemas. Padrão Basis: schema único por aplicação (todas as tabelas em `public`), Modulith separa só por package — simplifica.

Quando dividir schema:
- Limites duros entre subdomínios (ex: `compras.*` e `auditoria.*` em apps grandes)
- Necessidade de permissões diferentes por schema
- Deploy independente (não comum em Modulith — a graça é monolito)

Pra projeto novo: schema único. Migra se virar dor real.

## Baseline em sistemas legados

Migrando legacy → Basis: começar com `flyway:baseline` apontando pra V0 e iniciar nova numeração:

```yaml
spring:
  flyway:
    enabled: true
    baseline-on-migrate: true
    baseline-version: 0
```

Já tem o estado atual; novas migrations são V1+.

## Anti-padrões

- **Mexer em migration aplicada (V<N>__*.sql já em prod)** — Flyway calcula checksum; mudança detecta como corrupção. Crie nova migration que altere o estado.
- **Mistura DDL+DML em migration grande** — separe (DDL primeiro, DML em V seguinte). Facilita rollback e debugging.
- **`schema-initialization.enabled: true` + Flyway gerenciando tabela `event_publication`** — race condition na inicialização, falha intermitente.
- **Sem migrations** — "vou criar a tabela na mão em prod" eventualmente vira inconsistência entre ambientes. Todo sistema TEM ferramenta de migração — sem exceção.
- **Esquecer `flyway-database-postgresql`** — Flyway core sozinho não fala Postgres em todas as versões; o starter db-specific evita problemas.
