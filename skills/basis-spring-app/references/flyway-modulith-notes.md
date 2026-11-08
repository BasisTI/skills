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

Convenção Basis: timestamp `V20260424123000__nome.sql` — útil em projetos grandes ou onde múltiplas branches geram migrations em paralelo.

Exemplo:
```
V20260419080100__create_colaborador.sql
V20260420095600__create_processo.sql
V20260420123000__create_event_publication.sql
V20260420193500__add_dados_pessoais.sql
V20260421144400__add_chave_ocorrencia_jira.sql
V20260423123000__remove_bairro_telefone.sql
V20260424120000__fix_nascimento_sexo_types.sql
V20260424123000__evolve_processo.sql
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

Isso trata de schema; pasta e histórico de migração por módulo são outra coisa: ver "Migrações Flyway por módulo" abaixo.

## Migrações Flyway por módulo (Modulith 2.0+)

Regra (decisão da US orq #67, spike em módulo real com Modulith 2.1, Flyway 12 e Postgres 12): **projeto novo adota migrações por módulo; projeto existente não adota agora.** Em projeto existente a conversão tem armadilhas e o ganho é pequeno, porque o sufixo da US na versão (orq #45) já trata a colisão. Evidência completa: relatório anexo à US orq #67; aqui ficam só as regras. `[TESTADO]` foi executado; `[DOC]` vem de documentação ou de leitura do bytecode.

### Como ligar

- `spring.modulith.runtime.flyway-enabled=true` **e** a dependência `org.springframework.modulith:spring-modulith-runtime` (gerenciada pelo BOM, não vem no `spring-modulith-starter-core`). Sem a dependência, a flag não faz nada: nenhum erro e nenhum aviso, e o Flyway segue com um histórico só `[TESTADO]`. Ponha um teste que falhe se `flyway_schema_history_<módulo>` não existir depois da subida.
- Pastas `db/migration/<módulo>` e `db/migration/__root`. Cada módulo com arquivos ganha o histórico `flyway_schema_history_<módulo>`; o `__root` usa `flyway_schema_history`.
- A ordem de execução é a topológica das dependências entre módulos.

### Gotchas testados

- **`__root` roda sempre primeiro.** Arquivo nele que toque tabela de módulo (FK, `alter`, view) falha com `relation ... does not exist`. Deixe no `__root` só o que não tem dono: extensões, schema, tabelas de base.
- **Migração Java `@Component` roda em todos os históricos**, uma vez por histórico. Evite; se precisar, torne-a idempotente ou ache-a por varredura de `db.migration.<módulo>` `[DOC]`.
- **`baselineOnMigrate` não protege banco existente.** O baseline `0` de um histórico novo sobre schema já povoado faz as migrações do módulo rodarem de novo (`relation ... already exists`).
- **Ids de tabela de referência mudam na instalação limpa.** A ordem por módulo reordena os `insert`; teste que assume ids fixos quebra. Em produção os ids existentes não mudam.
- **`spring.flyway.locations` extras (testes)** ganham `/<módulo>` em cada location; migração de teste fora da subpasta do módulo é ignorada em silêncio.
- **Limpeza de banco nos ITs** não pode truncar `flyway_schema_history_<módulo>`: filtre por `not like 'flyway_schema_history%'`.
- **FK sem dependência declarada no código** não entra na ordem `[DOC]`: declare o módulo em `allowedDependencies` ou use-o no código.
- Dois arquivos de mesma versão em módulos diferentes não colidem; dentro do mesmo módulo colidem, então o sufixo da US (orq #45) continua valendo e funciona dentro dos módulos (`V…_70__x` vira a versão `….70`).

### Para quem precisar converter

Script SQL único, rodado antes do deploy: cria `flyway_schema_history_<módulo>` (`like ... including all`), insere o baseline `0`, copia do histórico antigo as linhas das versões que foram para o módulo (com checksum, mais as migrações Java) e as apaga do histórico do `__root`. Deploy e script têm de ser atômicos, não há volta simples para a imagem antiga, e o ensaio é em cópia do banco de produção. Sem converter, o `__root` reprova no validate com `Detected applied migration not resolved locally`.

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
