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

## O que a migração toca

Medido no `ponto`, e a ordem de grandeza é o que interessa:

| Frente | Tamanho | Observação |
|---|---|---|
| Entidades com `tenant_id` | 6 | A parte fácil |
| Repositórios | 8 | Trocar o parâmetro de tipo |
| `findById`/`deleteById` fora dos repositórios | 8 | A conta ingênua para aqui |
| **`.getId()` / `.getTenantId()` em produção** | **58** | O contrato do `Persistable` obriga; não dá para escolher o nome |
| Arquivos de teste tocados | 14 | |
| Mappers MapStruct | 4 | `@Mapping` explícito nos dois sentidos, mais `partialUpdate` |

**Meça pelo `getId()`, não pelo `findById()`.** A diferença entre as duas contagens é de sete
vezes, e é o suficiente para inverter a decisão. Uma aprovação dada sobre o número errado
precisa ser devolvida, não corrigida em silêncio no meio da execução.

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
