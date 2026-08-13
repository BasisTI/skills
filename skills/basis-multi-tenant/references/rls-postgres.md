# Row Level Security no Postgres — a mecânica

Long tail do `SKILL.md`. Aqui está o comportamento do Postgres que faz a diferença entre
isolamento real e policy decorativa.

## Quem escapa das policies

Três categorias escapam, e as três aparecem em ambiente nosso:

| Quem | Escapa? | Como impedir |
|---|---|---|
| Dono da tabela | **Sim, por padrão** | `FORCE ROW LEVEL SECURITY`, ou não conectar como dono |
| Superuser | **Sim, sempre** | Não há como impedir — a role da app não pode ser superuser |
| Role com `BYPASSRLS` | Sim | Não conceder |

`FORCE` não afeta superuser nem `BYPASSRLS`. Por isso a role da aplicação é criada sem os
dois, e a verificação é `rolsuper = f` no `pg_roles`, não a leitura do `CREATE ROLE`.

```sql
SELECT rolname, rolsuper, rolbypassrls FROM pg_roles WHERE rolname IN ('<app>', '<app>_app');
```

## Ler o estado real das tabelas

```sql
SELECT c.relname,
       c.relrowsecurity   AS rls,
       c.relforcerowsecurity AS forced,
       pg_get_userbyid(c.relowner) AS dono
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r'
 ORDER BY 1;
```

As policies em si:

```sql
SELECT tablename, policyname, cmd, qual, with_check FROM pg_policies WHERE schemaname = 'public';
```

`qual` é a expressão do `USING`; `with_check` é a do `WITH CHECK`. `with_check` nulo com
`USING` preenchido significa que o Postgres reaproveita o `USING` para escrita — o que é o
que se quer no caso simples.

## `USING` e `WITH CHECK`

- **`USING`** filtra o que a linha existente precisa satisfazer para ser **vista** —
  `SELECT`, e as linhas alvo de `UPDATE`/`DELETE`.
- **`WITH CHECK`** valida a linha **resultante** de `INSERT`/`UPDATE`.

Com uma policy `FOR ALL` e só `USING`, o `WITH CHECK` herda a mesma expressão. É por isso que
`INSERT` com `tenant_id` alheio falha com `new row violates row-level security policy` sem
precisar de cláusula extra.

Cuidado com o caso menos óbvio: `UPDATE` que **muda** o `tenant_id` de uma linha. O `USING`
autoriza pela linha antiga e o `WITH CHECK` recusa pela nova — o que é o comportamento
desejado, e só acontece porque o `WITH CHECK` está herdado. Uma policy que declare `USING`
explícito e `WITH CHECK (true)` abre exatamente essa porta.

## Permissiva e restritiva — como as policies se combinam

Este é o detalhe que decide se um buraco pontual vira buraco geral.

| Tipo | Combinam por | Efeito de acrescentar uma |
|---|---|---|
| `PERMISSIVE` (default) | **OR** | **Amplia** o que é visível |
| `AS RESTRICTIVE` | **AND** | Estreita |

Toda policy criada sem qualificador é permissiva. Duas policies permissivas na mesma tabela
significam "vale a primeira **ou** a segunda", e é fácil escrever a segunda achando que se
está somando uma condição quando se está somando uma exceção.

O caso concreto: uma policy de isolamento por tenant mais uma de pré-autenticação —

```sql
CREATE POLICY tenant_isolation_usuario ON usuario
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::bigint);

CREATE POLICY pre_auth_usuario ON usuario
    USING (NULLIF(current_setting('app.current_tenant', true), '') IS NULL);
```

Com o tenant indefinido, a segunda casa e a tabela **inteira** aparece. É o comportamento
que o login precisa; o problema é que ele vale para qualquer outro caminho que também esteja
sem contexto — um serviço sem `@Transactional`, um `@Scheduled`, um consumidor de mensagem.
O modo de falha de "contexto perdido" deixa de ser zero linhas e passa a ser todas.

Estreitar, quando o custo do buraco não compensa:

```sql
CREATE POLICY pre_auth_usuario ON usuario
    FOR SELECT
    USING (NULLIF(current_setting('app.current_tenant', true), '') IS NULL);
```

`FOR SELECT` já impede escrita cross-tenant por esse caminho. Para fechar mais, o isolamento
pode virar restritivo — com a ressalva de que restritivas se aplicam **também** ao login, e
portanto o desenho passa a exigir que o fluxo pré-autenticação defina algum valor de tenant
antes de consultar.

### `USING (true)` é o mesmo que não ter policy

```sql
CREATE POLICY usuario_perfil_all ON usuario_perfil USING (true);
```

A tabela aparece com `relrowsecurity = t`, `relforcerowsecurity = t` e uma policy. Toda
verificação que conte policies dá verde. Nada é filtrado.

Costuma nascer de uma necessidade real — habilitar RLS numa tabela de ligação sem saber qual
predicado usar — e ficar. O predicado para tabela de ligação existe e é um `EXISTS` no lado
que tem tenant:

```sql
CREATE POLICY tenant_isolation_usuario_perfil ON usuario_perfil
    USING (EXISTS (SELECT 1 FROM usuario u WHERE u.id = usuario_perfil.usuario_id));
```

A RLS de `usuario` já filtra o `EXISTS`, então não é preciso repetir a comparação de tenant —
e assim a regra fica num lugar só.

## Tabelas de infraestrutura com `tenant_id`

`event_publication`, do Spring Modulith, é o caso que aparece em toda app nossa que usa
eventos com JDBC e acrescenta `tenant_id` a ela.

**Pré-requisito, e ele vem antes da discussão de RLS:** a tabela tem que ser do Flyway, não
do framework. `spring.modulith.events.jdbc.schema-initialization.enabled: false` desde a
criação da aplicação — ver `basis-spring-app` §4. Sem isso não há onde escrever a policy, e
os dois criadores ainda disputam a inicialização.

Com a tabela na baseline, a pergunta que sobra é se ela entra na RLS. A resposta encontrada
na prática — e a armadilha do raciocínio:

```sql
-- Sem RLS: é infraestrutura, e o tenant_id aqui é apenas informacional.
CREATE TABLE event_publication (
    id               UUID PRIMARY KEY,
    serialized_event TEXT NOT NULL,   -- <- o payload do evento de domínio
    tenant_id        BIGINT,
    ...
);
```

A justificativa responde pela **coluna** e não pelo **conteúdo**. `tenant_id` de fato é
informacional ali; `serialized_event` não é. É o payload do evento de domínio, em texto, de
todos os tenants, legível por qualquer conexão da aplicação.

O critério correto:

| Pergunta | Peso |
|---|---|
| A tabela cumpre papel de infraestrutura? | Nenhum |
| Alguma coluna guarda dado de negócio de mais de um tenant? | Decide |

Aplicar RLS aqui não é trivial — o publisher lê e completa publicações fora do contexto de
requisição, então uma policy por `tenant_id` barra o próprio Modulith. Duas saídas:

- **Não colocar dado sensível no payload.** O evento carrega identificador; o consumidor
  busca o resto já sob RLS. É a saída barata e a que resolve na origem.
- **Policy com exceção para a role do publisher**, se o payload precisar ser gordo. Custa uma
  role a mais e uma exceção documentada — e a exceção precisa estar no `AGENTS.md`.

Qualquer que seja a escolha, ela vira comentário na migration dizendo **por que o payload
pode ou não pode ser lido por todos os tenants**. "É infraestrutura" descreve a função e não
responde à pergunta.

## As formas de `current_setting`

```sql
current_setting('app.current_tenant')          -- lança erro se indefinida
current_setting('app.current_tenant', true)    -- devolve NULL se indefinida
NULLIF(current_setting('app.current_tenant', true), '')  -- NULL também para string vazia
```

A terceira é a que se usa. As duas primeiras têm modos de falha reais:

- Sem `missing_ok`, todo caminho pré-autenticação quebra com erro de SQL — login, checagem
  de passkey, verificação de e-mail.
- Com `missing_ok` mas sem `NULLIF`, uma variável definida como string vazia faz
  `''::bigint` lançar `invalid input syntax for type bigint`.

O cast fica **depois** do `NULLIF`, nunca antes.

## `set_config` e o terceiro argumento

```sql
SELECT set_config('app.current_tenant', '1', true);   -- transaction-local
SELECT set_config('app.current_tenant', '1', false);  -- vale pela sessão
```

| Contexto | Valor | Por quê |
|---|---|---|
| Aspecto da aplicação, por requisição | `true` | Conexão volta ao pool sem carregar tenant da requisição anterior |
| Migration Flyway com DML | `false` | Não há transação por requisição; o valor precisa durar a migration |
| `psql` de investigação | `SET app.current_tenant='1'` | Equivalente a `false`, e mais curto de digitar |

**`true` sem transação aberta é o modo de falha mais caro do assunto.** Cada statement vira
sua própria transação, o valor morre com ela e a consulta seguinte roda sem tenant. Não dá
erro: devolve zero linhas.

Diagnóstico em uma linha, dentro da mesma transação da consulta suspeita:

```sql
SELECT current_setting('app.current_tenant', true);
```

Se vier `NULL` no meio de um fluxo autenticado, o problema é transação, não dado.

## Privilégio é assunto separado de RLS

RLS filtra linha; `GRANT` autoriza a operação. São ortogonais, e uma role sem `GRANT` recebe
`permission denied for table`, não zero linhas — o que ajuda a separar os dois sintomas.

Na baseline, uma vez:

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO <app>_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO <app>_app;

ALTER DEFAULT PRIVILEGES FOR ROLE <app> IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO <app>_app;
ALTER DEFAULT PRIVILEGES FOR ROLE <app> IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO <app>_app;
```

`ALTER DEFAULT PRIVILEGES` vale só para objetos criados **depois**, e só para os criados
**pela role nomeada no `FOR ROLE`**. Com isso, migration de tabela nova não repete `GRANT`
nenhum — o que é bom de contar a quem está começando, porque a ausência de `GRANT` no
modelo parece esquecimento.

## O que a RLS não cobre

- **Sequências.** `nextval` não tem policy. Id previsível revela volume por tenant; TSID ou
  UUID resolvem, e são o padrão nosso por outros motivos.
- **Índices únicos globais.** `UNIQUE (email)` cruzando tenants vira vazamento por canal
  lateral: o erro de duplicidade revela que o valor existe em outro tenant. Unicidade de
  negócio é sempre `UNIQUE (tenant_id, <coluna>)`.
- **Tabelas sem `tenant_id`.** Tabelas globais — `tenant`, `perfil`, `flyway_schema_history`
  — ficam de fora de propósito. Vale conferir a lista de fora, não só a de dentro: tabela
  que deveria ter `tenant_id` e não tem não aparece em nenhuma varredura de RLS.
- **Agregados e `COUNT`.** Filtram junto com as linhas; nada a fazer. Mas plano de execução e
  estatística podem revelar cardinalidade de outros tenants em cenário adversarial — irrelevante
  para o nosso modelo de ameaça, registrado para não ser redescoberto.
- **Log de SQL.** `org.springframework.jdbc.core: TRACE` loga valores de parâmetro, inclusive
  o `tenant_id` e o que mais estiver na consulta.

## Verificar depois de toda migration

O ganho de ter isto num teste, e não num checklist, é que tabela nova sem RLS é invisível na
revisão de um diff grande:

```sql
SELECT c.relname
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN information_schema.columns col
       ON col.table_name = c.relname AND col.column_name = 'tenant_id'
 WHERE n.nspname = 'public' AND c.relkind = 'r'
   AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
```

Zero linhas é o único resultado aceitável. Qualquer nome que apareça é uma tabela que vaza.
