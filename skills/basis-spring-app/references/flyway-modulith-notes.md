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

Migrations em `src/main/resources/db/migration/V<versão>__<nome>.sql`. Spring Boot auto-configura Flyway pra rodar antes da aplicação subir.

## Naming

Convenção Basis: `V<timestamp>_<ref>__<nome>.sql`, em que `<ref>` é o número da user story, o mesmo de `TG-xxx` na branch. **O sufixo da US se acrescenta ao formato de timestamp que o projeto já usa, mantendo o mesmo comprimento**: histórico de 12 dígitos (`yyyyMMddHHmm`) segue com 12, histórico de 14 (`yyyyMMddHHmmss`) segue com 14.

```
V202611031020_259__add_chave_ocorrencia.sql       12 dígitos  ->  202611031020.259
V20261108150000_123__add_chave_ocorrencia.sql     14 dígitos  ->  20261108150000.123
```

O Flyway lê o `_` da parte da versão como `.` e compara cada parte como número. Duas US que escolham o mesmo minuto geram versões diferentes (`.259` e `.272`) em vez de colidir. Foi o que aconteceu no portal-liven (painel): TG-259 e TG-272 geraram `202611031020` e uma precisou ser renomeada.

```
V202611031020_259__add_chave_ocorrencia.sql       ->  202611031020.259
V202611031020_259_2__backfill_chave.sql           ->  202611031020.259.2
V202611031020_272__create_anexo.sql               ->  202611031020.272
```

- **Mais de uma migração na mesma US:** minutos diferentes, ou o contador depois da ref (`_259_2`, `_259_3`). `.259.2` vem depois de `.259` e antes de `.272`.
- **Não encurte o timestamp.** A versão é um número: `202611081500` (12 dígitos) é cerca de 100 vezes menor que `20260726120002` (14). Migração com timestamp mais curto que o do histórico fica menor que as já aplicadas e dá `Detected resolved migration not applied`. No banco limpo ela entra **antes** das antigas, então o teste com Testcontainers passa (um `ALTER` sobre tabela antiga falharia) e a falha só aparece no banco com histórico. Antes de criar a migração, olhe o comprimento da última em `db/migration`.
- **O sufixo resolve a colisão, não a ordem.** Dentro do mesmo minuto a ordem é a da ref, não a do merge. Se a `.272` já foi aplicada e a `.260` é mesclada depois, o Flyway recusa com `Detected resolved migration not applied`, como em qualquer versão menor que a última aplicada. Para arquivo ainda não aplicado, renomeie com um minuto posterior à última da branch de destino antes do merge; nunca ligue `outOfOrder` em produção para contornar.
- **Migração aplicada não se renomeia.** O checksum e o histórico não mudam, mas o Flyway deixa de achar o arquivo da versão aplicada e acusa `Detected applied migration not resolved locally` junto com a nova versão pendente.
- **Migrações já aplicadas ficam como estão.** `V202611031020__x.sql` (sem sufixo) vale `202611031020` e vem **antes** de qualquer `202611031020.<ref>`: as duas formas convivem na mesma pasta, e as antigas não são reaplicadas nem acusadas. `V6` e `V202608131000` também continuam antes das novas, pela comparação numérica por partes.
- **Projeto com numeração sequencial** (`V068`, `V017`) segue numerado e reserva números por US (skill `orquestrador`, `references/ondas.md`, "Recurso numerado"). A primeira migração em timestamp impede novas numeradas, porque qualquer `V069` ficaria menor que o histórico, e **não há volta**. Adotar é decisão por projeto, de quem pediu.

Conferido com SQL real e Postgres 17 no Flyway 11.14.1 e 12.4.0 (as versões dos projetos, Boot 4.0.5 e 4.1.x) e no 13.12.1: leitura de `_259`, `_259_2` e `_259_10`, ordem `.259`, `.259.2`, `.259.10`, `.272`, convivência com legado aplicado, recusa da `.260` tardia, e o 14 dígitos (`V20261108150000_123`) aplicado e validado sobre histórico de 14 dígitos.

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
