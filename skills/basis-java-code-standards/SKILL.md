---
name: basis-java-code-standards
description: Use when writing, reviewing, or refactoring Java code in a Basis project — formatting and naming, modern Java (records, sealed types, pattern matching, text blocks), exception handling, nullability and immutability, collections and streams, date/time and money, logging, concurrency, resources/IO, security, API design, and tests (JUnit 5 + AssertJ + Mockito). Activate on any change to `.java` files, on code review, or when the user asks to check conformance with the code standards.
---

# Padrões de Código Java

Padrões de codificação da Basis para qualquer código Java. Pareada com `basis-spring-app` (aquela cobre stack, configuração e arquitetura; esta cobre como o código é escrito dentro dela).

## 1. Escopo e enforcement

- Vale para todo código Java da Basis — apps Spring, libs, ferramentas.
- Regra que dá pra automatizar não vive só em documento: o que dá pra checar por ferramenta falha o
  pipeline, não o revisor. A divisão na Basis é:
  - **SonarQube** é o lint. Roda no `check-quality` do Dagger e cobre as regras (chaves ausentes,
    `catch` genérico, complexidade, code smell, vulnerabilidade). **Não** adicionar Checkstyle,
    SpotBugs ou PMD — é a mesma análise duas vezes, com dois conjuntos de regras pra manter.
  - **Spotless** é o formatter. Sonar aponta formatação, não reescreve arquivo; `spotless:apply`
    resolve indentação, largura de linha, ordem de import e import não usado de uma vez.
  - **`-Xlint:all`** no `maven-compiler-plugin`, sem warning novo. Pega o que é do compilador
    (deprecation, unchecked, this-escape) e que não é papel do Sonar.
  - **Nulidade** é checada por JSpecify + IDE/Sonar (ver §6); NullAway/Error Prone é opcional e
    depende do suporte da versão ao JDK em uso.
- Cobertura do Sonar vale para **todos** os módulos do reactor — módulo fora da lista de análise é
  código sem lint nenhum, e é sempre o `-domain`/`-commons` que fica de fora por esquecimento.
- Revisão humana/agente foca no que ferramenta não pega: design, nomes, tratamento de erro, teste.

## 2. Formatação

- Chaves sempre presentes em `if`, `if-else`, `if-else-if-else`, `for`, `while`, `do-while`, `switch`, `try-catch` e `try-catch-finally`, mesmo com bloco vazio ou de uma linha.
- Posição das chaves no padrão One True Brace.
- Limite de 120 colunas por linha.
- Uma instrução por linha.
- Sem `import *` (nem estático).
- Indentação e espaçamento são responsabilidade do formatter — não gastar review com isso.

## 3. Nomes

- Classes/records/enums em `PascalCase`; métodos e variáveis em `camelCase`; `static final` em `CONSTANT_CASE`; pacotes em minúsculo sem underscore.
- Nome descreve intenção, não tipo nem implementação: `usuariosAtivos`, não `listaUsr`; `PagamentoService`, não `PagamentoManagerImpl`.
- Sem prefixo `I` em interfaces e sem sufixo `Impl` quando existe uma única implementação — nesse caso normalmente a interface é desnecessária.
- Abreviação só quando é o vocabulário do domínio (`cnpj`, `cpf`, `nfe`).
- Boolean lê como afirmação: `ativo`, `temSaldo`, `podeAprovar`.
- `@Override` sempre que sobrescreve.

## 4. Java moderno

Usar os recursos da LTS em uso (ver `basis-spring-app` para a versão vigente) em vez de reproduzir padrões pré-Java 17:

- `record` para DTOs, value objects e retornos multi-valor — em vez de classe com getters/`equals`/`hashCode` manuais.
- `sealed` interface + `switch` com pattern matching para hierarquias fechadas (estados, resultados, comandos) — o compilador garante exaustividade.
- `switch` como expressão (`->`) em vez de statement com `break`.
- Text block (`"""`) para SQL, JSON e mensagens multi-linha.
- `instanceof` com pattern (`if (o instanceof Pedido p)`) em vez de `instanceof` + cast.
- `var` só quando o tipo é óbvio no lado direito (`var pedido = new Pedido()`); nunca com retorno de método genérico ou literal ambíguo.
- `Stream.toList()`, `List.of()`, `Map.of()` para coleções imutáveis.

## 5. Tratamento de exceções

- Toda exceção capturada é tratada — nenhuma ignorada ou escondida. Dois tratamentos válidos: logar ou relançar. Escolher **um**: logar e relançar duplica o erro no log.
- No caso raro em que uma exceção não deve ser tratada, o bloco `catch` leva um comentário explicando o porquê.
- Exceção relançada usa classe de exceção do projeto (`<Application>Exception`) e **aninha a original** (`throw new PedidoException("...", e)`) — nunca perder a causa nem só a mensagem (`e.getMessage()`).
- Não lançar exceções genéricas (`RuntimeException`, `IllegalArgumentException`, `IllegalStateException`) para erro de negócio — usar exceções da aplicação, com nome que descreve a falha (`SaldoInsuficienteException`).
- Guardas internas de programação (`Objects.requireNonNull`, pré-condições de método privado) podem manter `NullPointerException`/`IllegalArgumentException` — são bug, não fluxo de negócio.
- Capturar exceções específicas (`IOException`, `NoSuchAlgorithmException`), nunca `Exception`, `Throwable` ou `RuntimeException`. Única exceção: handler de fronteira (`@ControllerAdvice`, loop de consumidor de mensageria), onde capturar `Exception` é intencional e existe para não derrubar o processo — ali documente.
- Nunca engolir `InterruptedException`: restaurar o flag (`Thread.currentThread().interrupt()`) ou propagar.
- Exceção não é fluxo de controle — não usar para sinalizar caso esperado (ex: "não encontrado" em busca opcional).
- Mensagem de exceção diz o que falhou e com quais dados de contexto — sem dado sensível.

## 6. Nulidade e imutabilidade

### JSpecify é o padrão

Spring Framework 7 / Spring Boot 4 migraram todo o codebase para **JSpecify**, e é o que a Basis usa.
As anotações são `org.jspecify.annotations.*` — não `javax.annotation`, não
`org.springframework.lang.Nullable` (removida no Spring 7), não `jakarta.annotation.Nullable`.

- **`@NullMarked` no `package-info.java` de cada pacote.** Dentro de um pacote marcado, todo tipo
  não anotado é **não-nulo**; só a exceção leva `@Nullable`. É o inverso do default do Java, e é o
  que faz a anotação valer a pena: quem lê a assinatura sabe a resposta sem abrir a implementação.
- Declarar `org.jspecify:jspecify` **explicitamente** no pom de cada módulo que usa as anotações.
  Ela chega transitivamente pelo Spring, mas depender de transitiva pra algo que se `import` quebra
  no dia em que a cadeia muda. A versão vem do BOM do Spring Boot.
- `@Nullable` vai **no tipo**, não no membro (`@Nullable String buscar()`, `List<@Nullable String>`)
  — JSpecify é anotação de tipo, e a posição importa em genérico e array.
- Módulo sem Spring (`-domain`, libs) também é `@NullMarked`; ali a dependência é obrigatória.
- Enforcement: IntelliJ e SonarQube entendem JSpecify direto. NullAway (via Error Prone) leva a
  checagem pro compilador quando a versão suporta o JDK em uso — desejável, não obrigatório.

### Regras que continuam valendo

- Não retornar `null` em métodos que retornam coleções — retornar coleção vazia. Isso vale mesmo com
  `@Nullable` disponível: coleção vazia é o contrato, não uma ausência a ser tratada.
- `Optional` só como tipo de retorno de método; nunca campo, parâmetro ou dentro de coleção. Com
  JSpecify, campo/parâmetro opcional é `@Nullable`, que não aloca e não vaza `Optional` na API.
- Não usar `Optional.get()` — usar `orElseThrow()`, `orElse()`, `map()`.
- `Objects.requireNonNull` fica para as fronteiras que o compilador **não** vê: entrada
  desserializada (JSON, mensagem, banco), reflexão, e API pública consumida por código não anotado.
  Dentro de código `@NullMarked`, repetir `requireNonNull` em todo parâmetro é ruído — a anotação já
  é o contrato.
- Preferir campos `final` e imutabilidade sempre que possível (records, builders, sem setter desnecessário).
- Coleção exposta por API é imutável (`List.copyOf`, `Collections.unmodifiableList`) ou cópia defensiva — nunca a referência interna mutável.
- Sobrescrever `equals()` e `hashCode()` sempre juntos; se a classe entra em coleção ordenada, `compareTo` consistente com `equals`.
- `toString()` útil em entidades e value objects — e sem dado sensível.

## 7. Coleções e streams

- Escolher a estrutura pelo acesso: `List` para ordem, `Set` para unicidade, `Map` para lookup — não `List` com `contains` em laço.
- Stream quando deixa mais legível; laço quando não. Stream de mais de 3-4 operações encadeadas normalmente pede extração de método.
- Sem efeito colateral dentro de lambda (`forEach` que muta estado externo, `peek` para logar) — coletar e agir sobre o resultado.
- Nunca modificar coleção durante iteração — usar `removeIf` ou `Iterator.remove`.
- Não usar stream paralelo sem medição; na prática quase nunca é a resposta.

## 8. Data/hora e valores monetários

- `java.time` sempre. Proibido `Date`, `Calendar`, `SimpleDateFormat`.
- Timestamp de evento/auditoria: `Instant` em UTC. Data de negócio sem hora: `LocalDate`. Data/hora com fuso relevante: `ZonedDateTime` com `ZoneId` explícito.
- Nunca depender do fuso default da JVM (`ZoneId.systemDefault()` implícito) — o pod tem o fuso que o cluster deu.
- Dinheiro e quantidade fiscal em `BigDecimal` com escala e `RoundingMode` explícitos — nunca `double`/`float`.
- `new BigDecimal("0.1")` (string), nunca `new BigDecimal(0.1)`; comparar com `compareTo`, não `equals`.

## 9. Logging

- SLF4J com logger `private static final` por classe. Sem `System.out`/`System.err` e sem `e.printStackTrace()`.
- Placeholder `{}`, nunca concatenação: `log.debug("Pedido {} processado", id)`.
- Exceção vai como último argumento (`log.error("Falha ao processar {}", id, e)`) para preservar o stack trace.
- Níveis: `error` = precisa de ação humana; `warn` = degradação recuperável; `info` = evento de negócio relevante; `debug` = diagnóstico.
- Sem dado sensível (senha, token, PII) em nenhum nível.
- Identificador de correlação via MDC quando há requisição/mensagem em contexto.

## 10. Concorrência

- Evitar estado mutável compartilhado sem sincronização explícita — o padrão é não compartilhar.
- Preferir `java.util.concurrent` (`ConcurrentHashMap`, `AtomicInteger`, `ExecutorService`) a `synchronized` manual.
- Documentar explicitamente se uma classe é thread-safe ou não.
- Nunca criar `Thread` na mão — usar executor (virtual threads para carga IO-bound na LTS atual).
- `ExecutorService` com try-with-resources ou `shutdown()` garantido; sempre tratar `Future`/exceção da task, senão a falha some.
- `ThreadLocal` sempre limpo em `finally` — pool reaproveita a thread.

## 11. Recursos e IO

- try-with-resources para todo `Closeable`/`AutoCloseable` (conexão, stream, arquivo).
- Nunca depender de `finalize()` (removido) nem de `Cleaner` como estratégia principal.
- `java.nio.file.Path`/`Files` em vez de `java.io.File`.
- Charset **sempre** explícito (`StandardCharsets.UTF_8`) em leitura, escrita e conversão `String`/`byte[]`.
- Não carregar arquivo inteiro em memória quando dá para streamar.

## 12. Segurança

- Nunca concatenar string para montar query SQL — prepared statement / query parametrizada.
- Validar toda entrada externa (parâmetro de API, arquivo, dado de usuário) antes de processar; Bean Validation na fronteira quando disponível.
- Nunca logar dado sensível (senha, token, PII).
- Nunca colocar segredo (senha, chave de API) no código-fonte — ver `basis-k8s-deploy` para origem de secrets.
- Não implementar algoritmo criptográfico próprio — bibliotecas consolidadas e atualizadas.
- `SecureRandom` para qualquer valor com significado de segurança (token, salt, id de sessão); `Random`/`Math.random()` nunca.
- Senha só com hash lento e salgado (bcrypt/argon2/scrypt), nunca MD5/SHA-1/SHA-256 puro.
- Não desserializar dado não confiável com serialização nativa Java; parsers configurados sem resolução de entidade externa (XXE).
- Caminho de arquivo derivado de entrada do usuário: normalizar e validar contra o diretório base (path traversal).

## 13. API e design

- Javadoc em classes e métodos públicos de API — o que faz, o que assume, o que lança. Sem Javadoc que repete a assinatura.
- Menor visibilidade que funciona: `private` > package-private > `public`. `public` é contrato.
- Composição em vez de herança quando não há "é um" claro; classe não projetada para extensão é `final`.
- Método com responsabilidade única e curto o bastante para ser entendido de uma vez.
- Getter sem efeito colateral.
- Injeção de dependência por **construtor** (campos `final`) — nunca `new` de dependência dentro de lógica de negócio nem injeção em campo.
- Interface criada quando há necessidade real (mais de uma implementação, fronteira de teste), não por padrão.
- Evitar parâmetro booleano em API pública — dois métodos nomeados são mais legíveis que `processar(pedido, true)`.
- Comentário explica **por quê**; o **o quê** é o código. Sem código comentado no repositório — o git guarda.

## 14. Testes

- Lógica de negócio tem cobertura de teste unitário. Cobertura é sinal, não meta.
- Stack padrão: JUnit 5 + AssertJ (`assertThat`) + Mockito; Testcontainers quando o teste precisa de banco/broker real.
- Nome descreve comportamento esperado, não implementação: `deveLancarExcecaoQuandoXNulo`, não `testMetodo1`.
- Estrutura arrange/act/assert visível; um comportamento por teste.
- Sem lógica (`if`, laço) no teste — se o teste precisa de lógica, ele precisa de teste.
- Teste determinístico: sem `Thread.sleep`, sem dependência de rede externa, sem ordem entre testes, relógio injetado (`Clock`) quando há tempo envolvido.
- Mockar o que é nosso e o que é lento/externo; não mockar tipo de terceiro que dá pra usar de verdade (`List`, `Optional`, entidade).
- Teste de exceção verifica tipo **e** causa/mensagem relevante (`assertThatThrownBy(...).isInstanceOf(...).hasCauseInstanceOf(...)`).

## 15. Checklist de revisão

Ao revisar ou gerar código Java, verificar em ordem:

1. Erro: exceção tratada uma vez, causa aninhada, tipo do projeto, nada engolido.
2. Nulidade: pacote `@NullMarked`, `@Nullable` só onde o nulo é real, sem `null` retornado em
   coleção, `Optional` só em retorno, `requireNonNull` nas fronteiras não anotadas.
3. Recurso: try-with-resources em tudo que fecha, charset explícito.
4. Segurança: query parametrizada, entrada validada, nada sensível em log, sem segredo no código.
5. Design: dependências por construtor, visibilidade mínima, método curto, sem efeito colateral escondido.
6. Teste: comportamento coberto, nome descritivo, determinístico.
7. Estilo: Spotless e SonarQube passaram — se não passaram, é build quebrado, não comentário de review.
