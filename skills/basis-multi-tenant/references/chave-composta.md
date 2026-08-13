# Chave composta `(tenant_id, id)` no Spring Data JDBC

Long tail do `SKILL.md` §6. O que o mapeamento exige, o que a migração custa e em que ordem
fazer.

O ponto que justifica tudo: com id composto, **`repository.findById(...)` não compila sem o
tenant**. A classe de bug "esqueci de filtrar por tenant" deixa de existir por construção,
em vez de ser evitada por disciplina em cada chamada nova.

## O mapeamento

Spring Data JDBC 4 suporta id composto via `@Id @Embedded.Nullable` sobre um record:

```java
public record TenantAwareId(
        @Column("tenant_id") Long tenantId,
        @Column("id") Long id) {
}
```

```java
public class Funcionario implements Persistable<TenantAwareId> {

    @Id
    @Embedded.Nullable
    private TenantAwareId pk;

    // ...

    @Override
    public TenantAwareId getId() {
        return pk;
    }
}
```

No banco:

```sql
CREATE TABLE funcionario (
    tenant_id BIGINT NOT NULL REFERENCES tenant(id),
    id        BIGINT NOT NULL,
    -- ...
    PRIMARY KEY (tenant_id, id)
);
```

A ordem das colunas na PK importa para o índice: `tenant_id` líder serve tanto
`WHERE tenant_id = ?` quanto `WHERE tenant_id = ? AND id = ?`. **Não serve `WHERE id = ?`** —
mas com o id composto adotado, esse acesso deixa de ser emitido, que é justamente o ponto.
Índice separado em `(id)` é sinal de que o mapeamento ainda é `Long`.

## Geração do id

`Persistable.isNew()` costuma ser implementado como `id == null`. Com id embutido isso muda
de sentido: o `pk` pode existir com `tenantId` preenchido e `id` nulo.

O padrão é um `BeforeConvertCallback` que monta o id completo antes da conversão:

```java
@Bean
BeforeConvertCallback<Funcionario> preencherPk() {
    return entidade -> {
        if (entidade.getPk() == null || entidade.getPk().id() == null) {
            entidade.setPk(new TenantAwareId(tenantAtual(), TSID.fast().toLong()));
        }
        return entidade;
    };
}
```

E `isNew()` passa a decidir por um campo de controle explícito (`@Transient boolean novo`, ou
`version`/`createdAt` nulo), não pelo id. Decidir por `pk == null` funciona no `INSERT` e
falha no `UPDATE` de entidade carregada e remontada.

## A técnica que decide o custo: delegar em vez de propagar

**É o item mais importante desta página.** `Persistable<TenantAwareId>` obriga `getId()` a
devolver o composto — o nome é do contrato da interface. O reflexo é propagar a mudança para
todo chamador, e é isso que faz a migração parecer inviável.

A saída é manter na superclasse os acessores antigos como **delegações sobre a chave**, e dar
um nome novo só ao que mudou de tipo:

```java
public abstract class TenantAwareEntity implements Persistable<TenantAwareId> {

    @Id @Embedded.Nullable
    private TenantAwareId pk;

    @Override
    public TenantAwareId getId() { return pk; }          // o contrato

    public Long getIdValue() {                            // o número cru
        return pk == null ? null : pk.id();
    }

    public void setId(Long id) {                          // continua existindo
        this.pk = new TenantAwareId(getTenantId(), id);
    }

    public Long getTenantId() {
        return pk == null ? null : pk.tenantId();
    }

    public void setTenantId(Long tenantId) {              // continua existindo
        this.pk = new TenantAwareId(tenantId, getIdValue());
    }
}
```

Com isso, **só `getId()` muda de tipo**. `getTenantId()`, `setId(Long)` e `setTenantId(Long)`
continuam com a mesma assinatura, e nenhum dos seus chamadores é tocado.

No `ponto`, medido depois de feito:

| Abordagem | Pontos de código a alterar |
|---|---|
| Propagar `TenantAwareId` para todos os acessores | **~117** |
| Delegar, e renomear só o getter do id cru | **~22** |

Cinco vezes menos, e a diferença entre "refatoração de uma tarde" e "projeto próprio".

Os ~22 restantes são os lugares que realmente querem o número — log, claim de JWT, chave
estrangeira — e viram `getIdValue()`. A substituição é mecânica e o compilador aponta todas.

## O que a migração toca

Medido no `ponto`, com a técnica acima aplicada:

| Frente | Tamanho | Observação |
|---|---|---|
| Entidades com `tenant_id` | 6 | A parte fácil |
| Repositórios | 8 | Trocar o parâmetro de tipo |
| `findById`/`deleteById` fora dos repositórios | 8 | Onde a mudança tem valor: cada um passa a exigir o tenant |
| `getId()` → `getIdValue()` | ~22 | De 39 `getId()` no total, só os de entidade multi-tenant |
| Mappers MapStruct | 4 | `@Mapping` explícito nos dois sentidos |
| Testes com asserção sobre id | 6 falhas | Ver abaixo — compilam e falham em runtime |

**Sobre estimar antes:** conte `getId()` **filtrando por entidade multi-tenant**, não o total
do projeto. A conta por `findById()` subestima; a conta por `getId()` bruto superestima. E se
a estimativa mudar no meio, devolva a decisão a quem aprovou — aprovação dada sobre número
errado é decisão não tomada.

### Consultas derivadas mudam de caminho

```java
List<Funcionario> findByTenantId(Long tenantId);      // deixa de resolver
List<Funcionario> findByPkTenantId(Long tenantId);    // o caminho novo
```

`tenantId` passa a ser `pk.tenantId`. Toda consulta derivada que mencione `id` ou `tenantId`
no nome quebra em tempo de inicialização do contexto — o que é bom: falha cedo e alto. As
`@Query` escritas à mão, não. Elas continuam compilando e passando a apontar para coluna que
ainda existe, então precisam ser revisadas uma a uma.

### A hierarquia de entidade racha

Id de coluna única e id composto não convivem na mesma superclasse: `Persistable<Long>` e
`Persistable<TenantAwareId>` são contratos diferentes. Uma `TenantAwareEntity` que hoje
estende `BaseEntity` deixa de poder estender.

O desenho que sai disso é limpo e vale por si:

- `BaseEntity` — entidades **globais**, sem tenant (`Tenant`, `Perfil`).
- `TenantAwareEntity` — entidades de tenant, com `TenantAwareId`.

O tipo passa a dizer se a entidade é isolada ou global, o que hoje só se sabe olhando se
existe uma coluna.

## As armadilhas, na ordem em que aparecem

Todas encontradas executando a migração, e nenhuma delas é adivinhável lendo a doc.

**1. `requireNonNull` no record quebra os construtores.** A tentação é validar os dois campos
no compact constructor. Não dá: a chave é montada em partes — os construtores das entidades
fazem `setId(...)` antes de `setTenantId(...)`, e o Spring Data instancia o record lendo linha
a linha. Deixe o record sem validação e garanta o preenchimento no `Objects.requireNonNull`
de cada entidade, mais o `NOT NULL` das colunas.

**2. Construtor all-args `(Long id, Long tenantId, ...)` faz o Spring Data perder a
propriedade `id`.** Ele deixa de achar o mapeamento e falha na leitura. A correção é um
construtor de persistência dedicado; o all-args continua existindo para o código de aplicação.

**3. Tabela de ligação precisa da coluna de tenant.** O Spring Data passa a emitir
`WHERE usuario_id = ? AND usuario_tenant_id = ?` para carregar a coleção. Se a tabela só tem
`usuario_id`, a consulta quebra. O DDL correto propaga a chave inteira:

```sql
CREATE TABLE usuario_perfil (
    usuario_tenant_id BIGINT NOT NULL,
    usuario_id        BIGINT NOT NULL,
    perfil_id         BIGINT NOT NULL,
    CONSTRAINT pk_usuario_perfil PRIMARY KEY (usuario_tenant_id, usuario_id, perfil_id),
    CONSTRAINT fk_usuario_perfil_usuario FOREIGN KEY (usuario_tenant_id, usuario_id)
        REFERENCES usuario(tenant_id, id) ON DELETE CASCADE
);
```

**Isto é um ganho de segurança, não só uma correção de compilação.** Antes, a tabela de
ligação não tinha coluna de tenant nenhuma — e por isso a policy dela era `USING (true)`, que
não isola nada. Com a coluna, a policy passa a existir de verdade:

```sql
CREATE POLICY tenant_isolation_usuario_perfil ON usuario_perfil
    USING (usuario_tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::bigint);
```

A chave composta **propaga o tenant pelas chaves estrangeiras**, e é isso que torna tabela de
ligação isolável. Vale procurar as outras: toda tabela que referencia entidade multi-tenant e
hoje guarda só o id é candidata ao mesmo problema.

**4. Asserção de teste compila e falha em runtime.** `assertThat(x.getId()).isEqualTo(1L)`
continua compilando — `isEqualTo` recebe `Object` — e passa a comparar `TenantAwareId` com
`Long`. O compilador não ajuda; a suíte pega. Foram 6 falhas dessa família, todas do mesmo
recorte mecânico.

**5. Compilação incremental mente.** Depois de trocar o parâmetro de tipo dos repositórios, o
Maven relata "nothing to compile" e a build passa sem recompilar o que deveria falhar. Force
a recompilação antes de acreditar em build verde.

**6. `@Query` escrita à mão não quebra — fica incompleta.** Um `LEFT JOIN usuario_perfil up
ON u.id = up.usuario_id` continua válido e passa a juntar sem o tenant. As consultas derivadas
falham alto na inicialização do contexto; as escritas à mão, não. Reveja uma a uma, com busca
por nome de tabela, não por erro de compilação.

## Provar que o tenant entrou na consulta

Depois da migração, um 404 pode vir da RLS (a policy filtrou) ou da chave composta (a consulta
pediu o par certo e não existe). São causas diferentes e o sintoma é o mesmo.

Ligue o log de SQL no Postgres e leia a consulta emitida:

```sql
ALTER SYSTEM SET log_statement = 'all';
SELECT pg_reload_conf();
```

O que se procura, literalmente:

```
WHERE "funcionario"."id" = $1 AND "funcionario"."tenant_id" = $2
```

Com os dois predicados, **o tenant entrou na consulta, não só na policy** — que é o objetivo
inteiro da migração. Sem o segundo, o mapeamento não foi adotado naquela entidade e a
segurança continua dependendo só da RLS.

Desligue o log depois: ele registra valor de parâmetro.

## O pré-requisito: teste de integração

**Suíte só de teste unitário com repositório mockado não exercita mapeamento
objeto-relacional.** É exatamente a camada que a migração quebra. Trezentos testes verdes não
são evidência nenhuma aqui.

O que dá a rede, por entidade: salvar, buscar por id composto, listar por tenant, confirmar
que o tenant vizinho não vê. Com Testcontainers + Postgres real, porque o comportamento a
verificar inclui a RLS.

Dois tropeços de infraestrutura que aparecem antes do primeiro teste rodar, e são da mesma
classe:

- **Versão fixada no pom sobrescrevendo a do parent.** `failsafe` preso em 3.1.2 com o
  `surefire` em 3.5.6; `testcontainers-bom` preso em 1.18.3 (de 2023) contra engine Docker
  moderna. Nos dois casos a correção é **remover a versão fixa** e herdar do parent do Spring
  Boot, não fixar outro número.
- **`*IT.java` dentro de pacote de produção.** Os testes ArchUnit varrem por reflexão,
  encontram a classe e disparam o container durante a suíte unitária. O IT vai para pacote
  próprio, fora do que o ArchUnit varre.

Antes de escrever qualquer coisa, confira o que já existe: `failsafe` costuma estar
configurado no pom e nunca ter rodado, por não haver nenhum `*IT.java`.

## Ordem de execução

1. **Teste de integração primeiro**, com o mapeamento atual. Ele passa, e vira a rede.
2. **`TenantAwareId` + uma entidade** de menor risco — nunca a do caminho de autenticação.
3. **`BaseEntity`/`TenantAwareEntity`** separadas, entidades globais para a primeira.
4. **As demais entidades**, uma por commit, com o IT verde entre cada.
5. **Autenticação por último** — `Usuario`, `Passkey` e o que o login toca.
6. **Remover os índices em `(id)`** e o padrão defensivo `carregar(tenantId, id)`, que a essa
   altura virou código morto. Este passo é o que paga a migração; deixar de fazê-lo mantém o
   custo e perde o benefício.

## Quando não fazer

- Sistema já em produção com integração externa que consome o id como escalar — API pública,
  ETL, relatório. O id composto vaza para o contrato.
- Projeto sem teste de integração e sem orçamento para escrever — o passo 1 não é opcional.
- Perto de entrega, com o caminho de autenticação instável. `Usuario` e `Passkey` são o
  ponto sensível, e a migração passa obrigatoriamente por eles.

Fora esses casos, **decida cedo**. O custo cresce com o número de entidades escritas no
padrão antigo, e quem entra no projeto copia o que encontra.
