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

Convenção Basis: `V<timestamp>_<ref>__<nome>.sql`, em que `<timestamp>` é `yyyyMMddHHmm` (minuto) e `<ref>` é o número da user story, o mesmo de `TG-xxx` na branch. Exemplo: a TG-259, às 10h20 de 03/11/2026, cria `V202611031020_259__add_chave_ocorrencia.sql`.

O Flyway lê o `_` da parte da versão como `.`, e compara cada parte como número. Então `V202611031020_259` é a versão `202611031020.259`, e duas US que escolham o mesmo minuto geram versões diferentes (`.259` e `.272`), em vez de colidir. Foi o que aconteceu no portal-liven (painel): TG-259 e TG-272 geraram `202611031020` e uma precisou ser renomeada.

```
V202611031020_259__add_chave_ocorrencia.sql       ->  202611031020.259
V202611031020_259_2__backfill_chave.sql           ->  202611031020.259.2
V202611031020_272__create_anexo.sql               ->  202611031020.272
```

- **Mais de uma migração na mesma US:** minutos diferentes, ou o contador depois da ref (`_259_2`, `_259_3`). `.259.2` vem depois de `.259` e antes de `.272`.
- **O sufixo resolve a colisão, não a ordem.** Dentro do mesmo minuto a ordem é a da ref, não a do merge. Se a `.272` já foi aplicada e a `.260` é mesclada depois, o Flyway recusa com `Detected resolved migration not applied`, como em qualquer versão menor que a última aplicada. Gere o timestamp na hora de criar o arquivo e, se a base já tiver versão maior, **renomeie com um minuto posterior à última da branch de destino** antes do merge; nunca ligue `outOfOrder` em produção para contornar.
- **Migrações já aplicadas ficam como estão.** Não renomeie arquivo aplicado (o checksum e a versão no `flyway_schema_history` mudariam). `V202611031020__x.sql` (sem sufixo) vale `202611031020` e vem **antes** de qualquer `202611031020.<ref>`: as duas formas convivem na mesma pasta, e as antigas não são reaplicadas nem acusadas.
- **Numeração antiga convive.** `V6` e `V202608131000` continuam antes das novas, pela comparação numérica por partes.

Conferido no Flyway 13.12.1 (OSS) com Postgres 17: leitura das versões acima, convivência com legado aplicado (`V6`, `V202608131000`, `V202611031020`), ordem `.259`, `.259.2`, `.272`, e a recusa da `.260` tardia. O arranjo está descrito aqui e não precisa ser refeito a cada projeto; refaça se trocar de major do Flyway.

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

**O DDL acima é de Modulith 1.x — não copie sem conferir.** O schema muda a cada release: no Modulith 2.x a tabela tem também `event_id`, `status`, `completion_attempts` e `last_resubmission_date`, e o publisher depende delas. Tabela incompleta não falha no startup — falha na primeira publicação de evento, em runtime. Confira as colunas na doc da versão em uso antes de escrever a migration.

Por que desabilitar: `schema-initialization: true` causa conflito em rolling deploy se a tabela já existe; pior, perde controle de versão da estrutura do schema; e com os dois criando há race na inicialização.

**Desligue na criação da aplicação, não quando der problema.** É uma linha de yaml no primeiro commit. Depois que a tabela já existe criada pelo framework, vira correção de produção — e em app multi-tenant vira também uma tabela com `tenant_id` que nunca passou por revisão de policy (ver `basis-multi-tenant` §4).

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
