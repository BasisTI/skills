---
name: basis-multi-tenant
description: Isolamento multi-tenant em tabela única (single-table, coluna `tenant_id`) com Row Level Security do Postgres. Use quando alguém disser "vazamento cross-tenant", "leak cross-tenant", "RLS bypass", "isolamento multi-tenant", "esqueci de filtrar por tenant", "pk composta", "id composto", "TenantContext"; ao criar tabela nova com `tenant_id`; ao revisar endpoint que recebe `tenantId` do cliente; ou quando um `SELECT` volta vazio e ninguém sabe por quê. Prefira esta à `basis-spring-app` quando o assunto for isolamento entre clientes, porque o sintoma engana: parece bug de datasource, de transação ou de migration, e é de RLS.
---

# Multi-tenant single-table com RLS

O modelo é o de **tabela única**: uma coluna `tenant_id` em cada tabela de negócio, um
banco só, um schema só. A alternativa — schema ou banco por tenant — não é o padrão da
Basis e não está coberta aqui.

A ideia central, e a que mais se erra: **filtro por tenant escrito na aplicação é
verificação, não isolamento.** Ele depende de o desenvolvedor lembrar, em todo `findById`,
todo `UPDATE`, toda consulta derivada nova. A RLS do Postgres é o isolamento de verdade,
porque o banco recusa a linha independentemente do que o código pediu — mas ela só funciona
sob três condições que quase nunca estão presentes por default, e falha em silêncio quando
não estão. Silêncio é o problema: RLS mal configurada não dá erro, ela simplesmente não faz
nada, e o teste que "passa" é o mesmo que passaria sem policy nenhuma.

## Quando usar

Alguém diz: *"corrigir isolamento multi-tenant (RLS bypass e leak cross-tenant)"*, *"esse
endpoint aceita tenantId no path"*, *"a consulta voltou vazia e não devia"*, *"o Spring Data
JDBC não suporta chave composta"*. Ou vai criar uma tabela nova e pergunta qual migration
copiar.

## Os quatro hábitos que resolvem

**1. Desconfie de RLS que ninguém provou.** `ENABLE ROW LEVEL SECURITY` mais `CREATE POLICY`
é o que se vê no diff, e não basta. A pergunta a fazer não é "tem policy?", é "com que role
a aplicação conecta, e essa role é dona da tabela?".

**2. Prove o isolamento conectando, não lendo o schema.** Duas sessões `psql` com
`app.current_tenant` diferente, um `SELECT` e um `INSERT` cruzados. Trinta segundos, e é a
única evidência que vale.

**3. Trate `tenant_id` vindo do cliente como entrada hostil.** Path param, query param e
campo de DTO são todos controlados por quem chama. O tenant vem do token, sempre.

**4. Prefira eliminar a classe de bug a lembrar de evitá-la.** É o que a chave composta faz
— ver §6.

## 1. A role da aplicação não pode ser dona das tabelas

**O Postgres não aplica policy de RLS ao dono da tabela.** Não é configuração, é o
comportamento padrão. Uma aplicação que conecta com a role dona tem isolamento nenhum, por
mais policy que exista — e todas elas continuam aparecendo bonitas no `\d`.

Nenhum erro é emitido. A consulta simplesmente devolve as linhas de todos os tenants.

Duas roles, com papéis distintos:

| Role | Quem usa | Dona? | Superuser? |
|---|---|---|---|
| `<app>` | Flyway, migrations, manutenção | Sim | Irrelevante, mas costuma ser |
| `<app>_app` | A aplicação em runtime | **Não** | **Não** (`rolsuper = f`) |

`rolsuper = f` é condição necessária: superuser também escapa da RLS.

A role vai no `docker/postgres/init.sql`, que o entrypoint do Postgres roda antes do Flyway.
Os `GRANT` sobre as tabelas ficam na migration de baseline, que é quem sabe quais tabelas
existem — com um `ALTER DEFAULT PRIVILEGES` cobrindo as futuras, para que migration de
tabela nova não precise repetir `GRANT` nenhum.

**`FORCE ROW LEVEL SECURITY` é defesa em profundidade, não a correção.** Ele faz o próprio
dono ser filtrado, o que protege contra alguém apontar a aplicação ou um script de
manutenção para a role dona por engano. Mas a correção é a role não-dona; `FORCE` sem ela
apenas move o problema.

## 2. A policy precisa da forma `missing_ok`

```sql
CREATE POLICY tenant_isolation_<tabela> ON <tabela>
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::bigint);
```

O segundo argumento (`missing_ok = true`) não é detalhe de estilo. **Sem ele,
`current_setting` lança erro quando a variável não foi definida** — e isso acontece de
verdade, no fluxo de login: antes de autenticar não existe tenant no contexto, então os
métodos marcados para pular o filtro deixam a variável indefinida. Com a forma sem
`missing_ok`, o login quebra com erro de SQL no dia em que a RLS passa a valer.

O `NULLIF(..., '')` cobre o caso da variável definida como string vazia. Com os dois, o
resultado é `NULL`, a comparação é falsa e a linha não aparece — que é o comportamento
desejado: **zero linhas, não exceção**.

### Contar policies não diz nada

Uma policy pode existir e não isolar:

```sql
CREATE POLICY usuario_perfil_all ON usuario_perfil USING (true);
```

`\d` mostra a policy. Qualquer verificação que conte policies devolve 1. E ela permite
tudo. **Inspecione a expressão, não a quantidade** — o predicado precisa mencionar
`tenant_id`.

### A policy pré-autenticação é um buraco deliberado

O fluxo de login precisa ler `usuario` antes de existir tenant. A saída usual é uma segunda
policy:

```sql
CREATE POLICY pre_auth_usuario ON usuario
    USING (NULLIF(current_setting('app.current_tenant', true), '') IS NULL);
```

**Policies permissivas se somam por OR.** Isso significa que, com o tenant indefinido, a
tabela inteira fica visível — e não só para o login: para todo caminho de código que
simplesmente esqueceu de abrir transação ou de definir o contexto. O modo de falha de §3
deixa de devolver zero linhas e passa a devolver **tudo**, em silêncio.

Duas providências, e a segunda é a que importa:

- Restrinja a policy ao mínimo: `FOR SELECT` apenas, e nas tabelas do caminho de
  autenticação apenas (`usuario`, `passkey`, `email_verification_code`).
- Considere `AS RESTRICTIVE` para o predicado de tenant. Policies restritivas se somam por
  **AND**, então a permissiva de pré-autenticação deixa de poder abrir sozinha a tabela.

Toda policy pré-autenticação é dívida de segurança consciente. Ela precisa estar listada no
`AGENTS.md`, com a justificativa, para não ser copiada para uma tabela onde não faz sentido.

## 3. O contexto de tenant é transaction-local

O aspecto que define o tenant emite:

```java
jdbcTemplate.queryForObject("SELECT set_config('app.current_tenant', ?, true)", String.class, tenantId);
```

O terceiro argumento `true` significa **`is_local`: o valor vale até o fim da transação
corrente**. Sem uma transação aberta, cada statement é sua própria transação — o
`set_config` vale para si mesmo e evapora antes da consulta seguinte rodar.

O sintoma é cruel porque parece bug de dado: a consulta volta vazia, o registro existe, o
tenant está certo. No `ponto` foi exatamente isso — dois métodos de leitura sem
`@Transactional` faziam um endpoint pré-autenticação responder 400 com erro de SQL, e o
endpoint estava quebrado no `develop` sem ninguém ter notado.

**Regra:** todo método de serviço que toca repositório em app multi-tenant é
`@Transactional`, inclusive os de leitura, inclusive os de um `findBy` só. Não é rigor
cerimonial: **sem a transação, o isolamento não existe.**

O jeito de garantir isso sem depender de memória está na `basis-spring-app` §4:
`@Transactional(readOnly = true)` na classe e override explícito nos métodos de escrita.
Em app multi-tenant esse padrão deixa de ser boa prática e vira requisito de segurança —
é a diferença entre "o desenvolvedor lembrou" e "a classe já vem transacional".

E aqui a aposta é assimétrica: esquecer o `@Transactional` num método de leitura custa uma
consulta vazia, ou, nas tabelas com policy pré-autenticação (§2), **todas as linhas de todos
os tenants**. Esquecer o override num método de escrita custa uma exceção no primeiro teste.
Errar para o lado do `readOnly` é sempre o erro barato.

## 4. Copie a migration certa, não a mais recente

O reflexo de quem vai criar uma tabela é abrir a migration de `CREATE TABLE` mais nova e
copiar. **Isso reintroduz vazamento sempre que a mais nova for justamente a que esqueceu a
RLS** — e é o que aconteceu no `ponto`: a `V3` criou `configuracao_tenant` sem policy
nenhuma, meses depois de a `V1` ter feito certo.

Duas providências, porque a primeira sozinha não segura:

- **Um modelo declarado** — no `AGENTS.md` do projeto, dizendo qual arquivo copiar pelo
  nome. "A mais recente" não é instrução, é sorte.
- **Um teste que varre o schema**, afirmando que toda tabela com coluna `tenant_id` tem
  `relrowsecurity` e `relforcerowsecurity` verdadeiros. É o único mecanismo que pega a
  tabela nova sem policy antes de ela chegar em produção. Revisão humana não pega — a
  ausência de quatro linhas de SQL num diff de duzentas não salta.

Quando as migrations antigas já divergiram a ponto de não se conseguir deduzir o schema
final lendo em ordem — uma desfazendo a outra, uma esquecendo RLS —, consolide em baseline
enquanto o sistema só existe em dev. Depois de estar em produção essa porta fecha.

### As tabelas de infraestrutura que carregam `tenant_id`

A varredura precisa cobrir **toda** tabela com `tenant_id`, não as que o time lembra como
"de negócio". O caso concreto é a `event_publication` do Spring Modulith.

Ela é criada pelo Flyway — o `schema-initialization` do Modulith está desligado, como manda
a `basis-spring-app` §4 — e ficou deliberadamente de fora da RLS, com a justificativa escrita
na própria migration:

> `-- Sem RLS: é infraestrutura, e o tenant_id aqui é apenas informacional.`

**A decisão é defensável e a justificativa está incompleta**, e é essa a lição. Ela responde
pela coluna e não responde pelo conteúdo: `serialized_event` guarda o payload do evento de
domínio, em texto, de todos os tenants, legível por qualquer conexão da aplicação. Se o
evento carrega CPF, salário ou e-mail, o dado atravessa a fronteira que todas as outras
tabelas respeitam — e atravessa numa tabela que ninguém pensa em auditar.

**A regra que sai daqui:** decisão de deixar tabela fora da RLS se justifica pelo **conteúdo
que ela guarda**, nunca pelo papel que ela cumpre. "É infraestrutura" descreve a função, não
o dado. Ou a tabela entra na RLS, ou a migration explica por que o payload pode ser lido por
todos os tenants — e essa frase é bem mais difícil de escrever, que é justamente o ponto.

Para `event_publication` especificamente, a saída barata costuma ser não deixar dado sensível
no payload: evento carrega identificador, o consumidor busca o resto já sob RLS.

**Varra por coluna, não por lista.** Foi assim que este caso apareceu, num banco onde o
isolamento tinha acabado de ser declarado provado ponta a ponta — a verificação da sessão
percorreu as tabelas de negócio que o time enumerou, e essa não estava entre elas.

O inverso também merece olhada: tabela isolada **sem** ter `tenant_id`, por policy que passa
por join. Ela não aparece na varredura por coluna, e por isso o script imprime também a
lista das tabelas sem `tenant_id` — para leitura humana, item a item.

## 5. `FORCE` depois do seed, e o que isso faz com DML futuro

Com `FORCE` ativo o dono passa a ser filtrado. Os `INSERT` de seed do Flyway rodam **como a
role dona e sem `app.current_tenant` definido** — seriam rejeitados pelas próprias policies.

A ordem que resolve, sem gambiarra:

```
V<ts>0__baseline_schema.sql          DDL, GRANT, ENABLE RLS + policies
V<ts>1__seed_dados_iniciais.sql      DML, ainda sem FORCE
V<ts>2__force_row_level_security.sql FORCE em todas as tabelas de tenant
```

**Consequência permanente, e a parte que se esquece:** toda migration futura que faça DML em
tabela com `tenant_id` roda depois do `FORCE` e será filtrada. Ela precisa definir o tenant
antes:

```sql
SELECT set_config('app.current_tenant', '1', false);
UPDATE funcionario SET ...;
```

Note o `false` — aqui se quer valor de sessão, não transaction-local. DDL (`CREATE`/`ALTER
TABLE`) não é afetado por RLS e não precisa disso.

## 6. Chave primária composta — o que elimina a classe de bug

**Com `PRIMARY KEY (tenant_id, id)` e o id mapeado como composto, "esqueci de filtrar por
tenant" deixa de ser possível.** Não é mitigação: é impossível pedir um registro sem dizer
de qual tenant, porque a assinatura do método exige os dois.

Todo o padrão defensivo que se escreve sem isso — o `carregar(tenantId, id)` privado que
refaz `findById(id).filter(e -> e.getTenantId().equals(tenantId))` em todo serviço — existe
apenas porque `findById` aceita um `Long` sem tenant.

O Spring Data JDBC 4 suporta isso nativamente, via `@Id @Embedded.Nullable` num record:

```java
public record TenantAwareId(
        @Column("tenant_id") Long tenantId,
        @Column("id") Long id) {
}
```

`repository.findById(new TenantAwareId(tenantId, id))` emite `WHERE tenant_id = ? AND id = ?`.

**Conhecimento negativo, e ele custou tempo:** existe a crença de que Spring Data JDBC não
lida com chave composta, e ela aparece até em comentário de migration — *"índice separado em
`(id)`, porque o Spring Data JDBC emite `WHERE id = ?` e a PK composta não atende esse
acesso"*. **A afirmação está errada no enquadramento.** O framework suporta; o que força o
`WHERE id = ?` é o projeto ter mapeado o id como `Long` simples. Apresentado como limitação
da ferramenta, o problema fica sem solução; enunciado como escolha de mapeamento, tem.

O índice extra em `(id)` é o sintoma dessa escolha. Com o id composto adotado, ele some — a
própria PK atende o acesso.

### O custo, medido e não estimado

Adotar não é gratuito, e a conta precisa ser feita antes, porque **a parte cara não é a
entidade, é o contrato do `Persistable`**:

| Frente | Tamanho real |
|---|---|
| `Persistable<TenantAwareId>` obriga `getId()` a devolver o composto | **58 chamadas** de `.getId()`/`.getTenantId()` em produção esperando `Long`, mais 14 arquivos de teste |
| Mappers MapStruct | Cada um precisa de `@Mapping` explícito nos dois sentidos, mais o `partialUpdate` |
| Consultas derivadas | `findByTenantId(Long)` deixa de resolver — `tenantId` vira `pk.tenantId` |
| Hierarquia de entidade | Id de coluna única e id composto não convivem na mesma superclasse; entidades globais ficam na antiga |
| Geração de id | `isNew` decidido por `id == null` para de valer; costuma exigir um `BeforeConvertCallback` que monta o id |

A contagem ingênua olha entidades e repositórios e dá "8 chamadas". A real olha `getId()` e
dá 58. **Meça pelo `getId()`, não pelo `findById()`** — é onde a estimativa erra por sete
vezes, e uma decisão aprovada com o número errado é uma decisão não tomada.

### Quando decidir

**Antes de o padrão se espalhar.** Se novas entidades forem escritas com `@Id Long` e o
projeto migrar depois, elas são reescritas inteiras — entidade, repositório, serviço e
testes. Em projeto com gente entrando, o código existente é o que vai ser copiado.

### O pré-requisito que quase sempre falta

Migração de id composto quebra na camada de mapeamento objeto-relacional. Suíte só de teste
unitário com repositório mockado **não exercita essa camada** — 322 testes verdes não dizem
nada sobre isso. Antes de migrar: teste de integração com Testcontainers que, para cada
entidade, salva, busca por id, lista por tenant e confirma o isolamento. Sem essa rede, a
única verificação é subir a aplicação e clicar em tela.

## 7. O tenant vem do token, nunca do cliente

Duas formas do mesmo bug, ambas encontradas no mesmo projeto:

- Endpoint que aceita `tenantId` como **path param** e usa esse valor para consultar.
- Resource que grava com `dto.tenantId()`, **do corpo da requisição**.

Com RLS de verdade nas duas pontas, pedir o tenant alheio devolve `[]` e escrever no tenant
alheio dá `new row violates row-level security policy`. Sem RLS, os dois são leitura e
escrita cross-tenant com o carimbo da aplicação.

Corrigir os dois no código continua sendo necessário — a RLS é a rede, não a licença para
escrever errado. Endpoint que recebe `tenantId` do cliente deve devolver 403, não `[]`: o
silêncio esconde a tentativa.

**Não hardcode `current_setting` na consulta do repositório.** Aparece como
`tenant_id = (SELECT current_setting('app.current_tenant')::bigint)` escrito à mão, e é
duplicação do que a policy já faz — com a forma sem `missing_ok`, ainda por cima, que
explode no fluxo pré-autenticação. Filtro por tenant é responsabilidade da policy.

## 8. Provar o isolamento

```bash
scripts/verificar-isolamento.sh <container> <db> <role-dona> <role-app>
```

Somente leitura. Reconcilia numa tela só as quatro coisas que precisam ser verdadeiras ao
mesmo tempo: role da app não é dona, não é superuser, toda tabela com `tenant_id` tem `rls`
e `forced`, e existe policy. É a checagem que a leitura de schema não dá, porque cada peça
isolada parece certa.

A prova de comportamento, depois, é manual e vale por si:

| Cenário | Esperado |
|---|---|
| App role sem `app.current_tenant` | 0 linhas, **sem erro** |
| `SET app.current_tenant='1'` | só as linhas do tenant 1 |
| Tenant 1 pedindo registro do tenant 2 | 0 linhas |
| `INSERT` com `tenant_id` alheio | `new row violates row-level security policy` |

Erro em vez de zero linhas na primeira: policy sem `missing_ok`. Linhas de todos os tenants:
a app está conectando como dona, ou como superuser.

## Assinatura — sintoma e causa

| Observação | Causa |
|---|---|
| Policies existem, `\d` mostra tudo certo, e vazam todos os tenants | App conecta como dona da tabela, ou como superuser |
| Consulta volta vazia com dado existente e tenant certo | `set_config(..., true)` sem transação aberta — método sem `@Transactional` |
| Erro de SQL em endpoint pré-autenticação, 400 | `current_setting` sem `missing_ok` com a variável indefinida |
| `INSERT` do Flyway rejeitado por policy | Migration de DML rodando depois do `FORCE` sem `set_config` |
| Tabela nova vaza, as antigas não | Migration copiada da mais recente, que era a sem RLS |
| Tudo passa em teste e vaza em runtime | Suíte só unitária com repositório mockado — não exercita a camada onde a RLS age |
| A tabela tem policy e mesmo assim vaza | Policy `USING (true)` — existe, conta, e não filtra |
| Vaza **tudo** em vez de nada quando o contexto se perde | Policy pré-autenticação permissiva somando por OR |
| Tabela de infraestrutura com `tenant_id` sem policy | Dispensada da RLS pelo papel ("é infraestrutura") em vez de pelo conteúdo |

## O que engana

**O `\d` da tabela.** Mostra as policies e não mostra quem conecta. A policy pode estar
perfeita e valer para ninguém.

**O teste verde.** Repositório mockado não tem RLS. A suíte inteira passa com o isolamento
desligado, o que faz dela evidência de nada nesse assunto.

**A migration mais recente.** É o modelo que todo mundo copia e o que ninguém verificou.

**A contagem de policies.** `USING (true)` conta como policy. Verificação que soma linha de
`pg_policies` dá verde numa tabela aberta.

**A lista de tabelas que o time enumera.** Sai sempre com as de negócio e sem as de
infraestrutura. Varra o catálogo por coluna `tenant_id`.

**"É só informacional".** Dito de uma coluna `tenant_id`, costuma ser verdade — e não
responde pelo resto da linha. A pergunta é o que mais a tabela guarda.

**Um `SELECT` que volta vazio.** Parece dado ausente e costuma ser contexto de tenant
perdido. Antes de investigar o dado, rode `SELECT current_setting('app.current_tenant', true)`
na mesma transação.

**`spring-boot-docker-compose` no classpath.** Ele publica um `JdbcConnectionDetails` que
tem **precedência sobre `spring.datasource.*`**, então a aplicação conecta onde o starter
mandou e não onde o yaml diz — o que impede apontar para a role não-dona e mascara erro de
configuração do datasource. Em app multi-tenant, remova.

## Checklist para tabela nova com `tenant_id`

- [ ] `tenant_id BIGINT NOT NULL` com FK para `tenant`
- [ ] `ENABLE ROW LEVEL SECURITY` **e** `FORCE ROW LEVEL SECURITY`
- [ ] Policy na forma `NULLIF(current_setting('app.current_tenant', true), '')::bigint`
- [ ] O predicado da policy menciona `tenant_id` — `USING (true)` não vale
- [ ] Sem policy pré-autenticação, a menos que a tabela esteja no caminho de login; se
      estiver, `FOR SELECT` e registrada no `AGENTS.md`
- [ ] Unicidade de negócio composta com o tenant (`UNIQUE (tenant_id, nome)`), nunca só a coluna
- [ ] Sem `GRANT` repetido, se o `ALTER DEFAULT PRIVILEGES` da baseline cobre
- [ ] Se a migration tiver DML e rodar depois do `FORCE`, tem `set_config` antes
- [ ] Classe de serviço com `@Transactional(readOnly = true)` e override explícito nas escritas
- [ ] Nenhum `tenantId` lido de path, query ou corpo

## Scripts

| Script | Muta? | Uso |
|---|---|---|
| `scripts/verificar-isolamento.sh` | Não | Reconcilia role, ownership, superuser, RLS e policies numa tela |

## References

- [`references/rls-postgres.md`](references/rls-postgres.md) — mecânica do Postgres: dono
  versus `FORCE`, formas de `current_setting`, `USING` versus `WITH CHECK`, `GRANT` e
  `ALTER DEFAULT PRIVILEGES`, o que RLS não cobre.
- [`references/chave-composta.md`](references/chave-composta.md) — id composto no Spring Data
  JDBC: mapeamento, `Persistable`, callback de geração, mappers, consultas derivadas, e o
  roteiro de migração com o teste de integração que ela exige.
