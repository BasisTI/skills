# Testes de estrutura com Spring Modulith

App com `@Modulithic`/Spring Modulith tem um teste de estrutura **obrigatório**. Sem ele, "módulo" é convenção de pasta: qualquer `import` entre pacotes internos passa no build e a modularidade se dissolve em algumas sprints, sem nenhum sinal.

O teste é barato (roda em milissegundos, sem contexto Spring) e falha no build assim que alguém cruza uma fronteira.

## Teste base

```java
package br.com.basis.<app>;

import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;
import org.springframework.modulith.docs.Documenter;

class ModularityTests {

    ApplicationModules modules = ApplicationModules.of(<App>Application.class);

    @Test
    void verificaModularidade() {
        // Valida as regras: sem acesso a pacotes .internal de outro módulo,
        // sem dependência cíclica entre módulos, dependências declaradas respeitadas
        modules.verify();
    }

    @Test
    void geraDocumentacao() {
        // Diagramas PlantUML/C4 + tabelas dos módulos em target/modulith-docs
        new Documenter(modules).writeModulesAsPlantUml().writeDocumentation();
    }
}
```

`modules.verify()` cobre:

- acesso a tipo em pacote interno (`<modulo>.internal.*`, ou qualquer subpacote não exposto) a partir de outro módulo;
- ciclo de dependência entre módulos;
- dependência para módulo não declarado em `@ApplicationModule(allowedDependencies = ...)`, quando a anotação é usada.

`Documenter` não valida nada — gera o diagrama de módulos em `target/modulith-docs`. Vale manter porque o diagrama é o artefato que a equipe olha em revisão de arquitetura, e gerado no build ele nunca desatualiza.

## Fronteiras específicas do domínio

`verify()` garante as regras genéricas. As invariantes que importam para o negócio — quem pode depender de quem — se declaram explicitamente:

```java
@Test
void fronteirasCriticasDoFluxoPermanecemUnidirecionais() {
    var candidaturas = modules.getModuleByName("candidaturas").orElseThrow();
    var matching = modules.getModuleByName("matching").orElseThrow();
    var vagas = modules.getModuleByName("vagas").orElseThrow();

    assertThat(candidaturas.getDirectDependencies(modules).containsModuleNamed("matching")).isTrue();
    assertThat(matching.getDirectDependencies(modules).containsModuleNamed("candidaturas")).isFalse();
    assertThat(vagas.getDirectDependencies(modules).containsModuleNamed("candidaturas")).isFalse();
}
```

Escrever esses testes para as dependências que **não podem existir** (o `isFalse()`): é o acoplamento que aparece sozinho quando alguém precisa de um dado "só desta vez".

Alternativa declarativa, quando a regra vale sempre: `@ApplicationModule(allowedDependencies = {"vagas", "shared"})` no `package-info.java` do módulo — aí o próprio `verify()` cobre.

## Teste de integração por módulo

Para exercitar um módulo isolado, com só os beans dele no contexto:

```java
@ApplicationModuleTest
class CandidaturasIntegrationTests {

    @Test
    void publicaEventoAoRegistrarCandidatura(Scenario scenario) {
        scenario.stimulate(() -> service.registrar(novaCandidatura()))
                .andWaitForEventOfType(CandidaturaRegistrada.class)
                .toArriveAndVerify(evento -> assertThat(evento.candidaturaId()).isNotNull());
    }
}
```

- `@ApplicationModuleTest` sobe só o módulo (e os declarados como dependência), não a app inteira — bem mais rápido que `@SpringBootTest`.
- `Scenario` (do `spring-modulith-starter-test`) é a forma de testar comunicação por evento sem `Thread.sleep`: o `andWaitForEventOfType` espera o evento com timeout.
- Precisa de `spring-modulith-starter-test` no escopo `test`.

## Módulo entre módulos: o que fica público

- Tipo exposto (API do módulo) fica no pacote raiz do módulo; implementação em `internal` (ou subpacote não exposto).
- Comunicação entre módulos: **evento de domínio** por padrão; chamada direta a bean só quando é consulta síncrona simples.
- Evento cruzando módulo é DTO/record próprio do módulo publicador, nunca entidade de persistência — senão o `verify()` passa mas o acoplamento voltou pela porta dos fundos.
