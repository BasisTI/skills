---
name: basis-java-code-standards
description: Use when writing, reviewing, or refactoring Java code in a Basis project — formatting and naming, modern Java (records, sealed types, pattern matching, text blocks), exception handling, nullability and immutability, collections and streams, date/time and money, logging, concurrency, resources/IO, security, dependency scanning (OWASP Dependency-Check), API design, and tests (JUnit 5 + AssertJ + Mockito). Activate on any change to `.java` files, on code review, when the build fails on a CVE in a dependency, or when the user asks to check conformance with the code standards.
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
  - **Spotless** é o formatter, com **palantir-java-format** como engine. Sonar aponta
    formatação, não reescreve arquivo; `spotless:apply` resolve indentação, largura de linha,
    ordem de import e import não usado de uma vez. A configuração completa, os erros que o
    rascunho óbvio comete e como implantar num projeto que ainda não tem estão em **§2.1 e
    §2.2** — não improvise um `<plugin>` novo.
  - **Antes de empurrar, rode a análise no que está no índice:** `git add` e depois
    `sonar analyze --staged` (CLI `sonar`, autenticada com `sonar auth login`). São segundos, e
    pega de graça o que seria uma MR reprovada.

    **Mas "No issues found" ali não é o gate.** A análise local roda sem compilar e sem
    classpath — é a diferença entre 200 ms e o `check-quality` inteiro —, e sem bytecode as
    regras que dependem de fluxo de dados não têm como rodar. Medido neste projeto: um arquivo
    que o CLI declarou limpo chegou à MR com dois `java:S2259` ("A NullPointerException could be
    thrown") e um `java:S7467`. Use-a como filtro, nunca como aval.

    **E ela não mede cobertura**, que é a outra metade do gate e a que reprova em silêncio:
    código novo bem escrito e sem teste passa no `analyze` e derruba a MR.

  - **Para ter o que o `check-quality` teria, rode a análise de verdade na sua branch.** É o
    mesmo scanner da pipeline, com bytecode, classpath e o `jacoco.xml` que o `verify` acabou de
    escrever — e por isso pega as regras de fluxo de dados que a análise local não alcança:

    ```bash
    ./mvnw clean verify
    ./mvnw org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
      -Dsonar.host.url=https://codequality.basis.com.br -Dsonar.token="$SONAR_TOKEN" \
      -Dsonar.projectKey=<chave> -Dsonar.branch.name=$(git branch --show-current)
    ```

    Duas coisas a não errar. O plugin **não** está declarado no pom (nem precisa: quem invoca na
    pipeline é o orchestrator), então vai pelo nome completo — `sonar:sonar` por prefixo falha com
    `No plugin found for prefix 'sonar'`. E **`-Dsonar.branch.name` não é opcional**: sem ele a
    análise entra como a branch principal do projeto e passa a valer como o retrato oficial dele.

    Isso **escreve no servidor compartilhado** — cria (ou atualiza) a branch no Sonar. Numa branch
    de feature é barato e some com ela; combine antes de fazer em `develop` ou `main`.

    Depois da análise, a conta sai por API:

    ```bash
    curl -sS -u "$SONAR_TOKEN:" "https://codequality.basis.com.br/api/measures/component_tree\
?component=<chave>&pullRequest=<n>&qualifiers=FIL&metricKeys=new_uncovered_lines,new_uncovered_conditions"
    ```

    Ela aponta **arquivo e contagem**; `api/sources/lines?key=<chave>:<caminho>&pullRequest=<n>`
    desce à linha, com `isNew`, `lineHits` e `coveredConditions` — que é o que diz qual `if`
    ficou sem teste, em vez de mandar procurar.
  - **`-Xlint:all`** no `maven-compiler-plugin`, sem warning novo. Pega o que é do compilador
    (deprecation, unchecked, this-escape) e que não é papel do Sonar.
  - **Nulidade** é checada por JSpecify + IDE/Sonar (ver §6); NullAway/Error Prone é opcional e
    depende do suporte da versão ao JDK em uso.
  - **OWASP Dependency-Check** é a varredura de dependência: cruza a árvore resolvida com o NVD
    e reporta CVE conhecida. O goal `check` liga na fase `verify`, então roda junto do resto.
    **Exige chave da API do NVD desde o 13.0.0** — sem ela aborta o goal e derruba o build, e
    não é aviso. A configuração, a armadilha da chave e como ler o relatório estão em **§1.1**;
    não improvise o `<plugin>`.
- Cobertura do Sonar vale para **todos** os módulos do reactor — módulo fora da lista de análise é
  código sem lint nenhum, e é sempre o `-domain`/`-commons` que fica de fora por esquecimento.
- Revisão humana/agente foca no que ferramenta não pega: design, nomes, tratamento de erro, teste.

### 1.1 OWASP Dependency-Check: a chave e a leitura do relatório

O plugin cruza a árvore de dependências resolvida com o NVD e escreve
`target/dependency-check-report.html` — HTML é o formato padrão do goal, e `<formats>` aceita
também `XML`, `JSON`, `SARIF` e `GITLAB` (esse último vira artefato de *Dependency Scanning* e
aparece na aba de segurança da MR, em vez de ficar só no log).

```xml
<plugin>
    <groupId>org.owasp</groupId>
    <artifactId>dependency-check-maven</artifactId>
    <version>${dependency-check-maven.version}</version>
    <configuration>
        <nvdApiKeyEnvironmentVariable>NVD_API_KEY</nvdApiKeyEnvironmentVariable>
        <!-- O analisador .NET vê os .dll/.exe que o npm desempacota em node_modules (o oxide
             do Tailwind e companhia), não acha `dotnet` no PATH e cospe um banner de ERROR a
             cada build. Não há código .NET nos nossos projetos. -->
        <assemblyAnalyzerEnabled>false</assemblyAnalyzerEnabled>
    </configuration>
    <executions>
        <execution>
            <goals>
                <goal>check</goal>
            </goals>
        </execution>
    </executions>
</plugin>
```

**A chave da API do NVD não é opcional a partir do 13.0.0.** O cliente recusa a requisição
antes de sair e o goal aborta:

```
Caused by: NvdApiException: Invalid API Key, length of 0 too short to provided a masked partial key
```

Como `check` liga na fase `verify`, isso **derruba o build inteiro** — não é aviso, e não
existe mais o acesso anônimo lento das versões antigas. Chave gratuita em
<https://nvd.nist.gov/developers/request-an-api-key>. Sem chave, a única alternativa é
`<nvdDatafeedUrl>` apontando para os datafeeds públicos do NIST, que baixa o feed inteiro em
vez de paginar a API.

**A chave entra por variável de ambiente, nunca pela property.** `<nvdApiKey>` com o valor
direto é ecoado pelo debug logging do Maven — é exatamente o vazamento de
GHSA-qqhq-8r2c-c3f5. Para desenvolvimento local, `<nvdApiKey>` nas properties do
`settings.xml` funciona e **tem precedência** sobre a variável de ambiente, então as duas
formas convivem sem conflito.

**No CI, a variável do GitLab não chega sozinha no build**: o container do Dagger é hermético.
Exige `ci-templates` ≥ `v1.13.0` e a variável `NVD_API_KEY` no projeto — o mecanismo está em
`basis-ci-gitlab`.

**`failBuildOnCVSS` no default (11) só relata.** O `verify` passa **verde** com CVE crítica na
tela: o plugin informa, não bloqueia. Para reprovar MR a partir de um limiar, é preciso baixar
esse valor de propósito. Vale o hábito de sempre — verde não é prova; pergunte o que a
checagem avaliou.

**O primeiro update baixa a base inteira.** Medido no `triagem.ai`: 394.865 registros, ~23
minutos, ~250 MB em `~/.m2/repository/org/owasp/dependency-check-data`. As execuções seguintes
fazem só o delta (`Skipping the NVD API Update as it was completed within the last 240
minutes`). No CI isso sobrevive porque o `/root/.m2` é cache volume do Dagger — se a duração
não cair na segunda pipeline, o cache não está persistindo e a conta muda.

#### Ler o relatório

**O casamento é por CPE, e CPE erra.** Antes de agir num achado, confira a faixa de versão que
o NVD publica para ele. Dois falsos positivos reais:

- `kotlin-stdlib` / `kotlin-stdlib-common`: CVE-2026-53914 (9.8) é desserialização insegura no
  metadado do **build cache** do Kotlin — atinge quem compila Kotlin, não quem tem a stdlib no
  classpath por causa do okhttp.
- `jbig2-imageio` 3.0.4: casou com o CPE `apache:pdfbox` e o NVD situa a correção em 3.0.8,
  versão que nunca existiu para esse artefato — o último release é 3.0.5.

**Agrupe os achados pela alavanca que os corrige, não por artefato.** Quase tudo é transitivo,
e um bump de BOM limpa dezenas de CVEs de uma vez. No `triagem.ai`, 111 CVEs em 27 artefatos
saíam com quatro bumps de BOM — e o Tika arrastava junto pdfbox, junrar e jackson-databind,
que não precisavam de bump próprio. Relatório organizado por artefato produz 27 tarefas onde
havia quatro.

**Bump do parent não garante que a dependência gerenciada esteja corrigida.** Confira a versão
efetiva contra a faixa do CVE e sobrescreva a property quando ela ficar aquém. O contraexemplo
apareceu em dois projetos independentes: o Spring Boot 4.0.8 e o 4.1.1 gerenciam Tomcat
11.0.24, e CVE-2026-65637 e CVE-2026-65905 (ambas 9.8) só terminam em 11.0.25 — sem
`<tomcat.version>11.0.25</tomcat.version>` as críticas continuam de pé **depois** de subir o
parent, com o relatório parecendo resolvido.

**Duas lacunas de cobertura que o relatório não anuncia.** O Sonatype OSS Index fica
desabilitado por falta de credencial (hoje exige token), então os achados vêm do NVD, da KEV da
CISA e do RetireJS. E o `package-lock.json` só é analisado por inteiro com `node_modules`
presente — no CI existe, porque o `frontend-maven-plugin` roda `npm install` durante o build;
numa execução local sem `npm ci` a árvore JS é avaliada só pelo lockfile.


## 2. Formatação

- Chaves sempre presentes em `if`, `if-else`, `if-else-if-else`, `for`, `while`, `do-while`, `switch`, `try-catch` e `try-catch-finally`, mesmo com bloco vazio ou de uma linha.
- Posição das chaves no padrão One True Brace.
- Limite de 120 colunas por linha.
- Uma instrução por linha.
- Sem `import *` (nem estático).
- Indentação e espaçamento são responsabilidade do formatter — não gastar review com isso.

### 2.1 Spotless: a configuração

O formatter é **palantir-java-format**, não google-java-format. O motivo está na
regra acima: o google-java-format fixa **100 colunas e não permite alterar**, então
ele é incapaz de implementar o limite de 120 exigido aqui. O Palantir se descreve como
*"a modern, lambda-friendly, 120 character Java formatter"* — 120 fixo, que é
exatamente o número exigido aqui.

**Surpresa do Palantir que ninguém antecipa:** além das 120 colunas, ele aplica
**80 colunas para cadeias de método** — o último ponto da cadeia tem que vir antes
da coluna 80, senão a cadeia não é inlinada e quebra em várias linhas. É
deliberado (legibilidade em review) e não é configurável. Cadeia que hoje cabe em
120 vai quebrar.

```xml
<properties>
  <spotless.version>3.10.1</spotless.version>
  <palantir.version>2.97.0</palantir.version>
</properties>

<plugin>
  <groupId>com.diffplug.spotless</groupId>
  <artifactId>spotless-maven-plugin</artifactId>
  <version>${spotless.version}</version>
  <configuration>
    <formats>
      <!-- Só o que nenhum bloco de linguagem cobre. NÃO incluir .java aqui. -->
      <format>
        <includes>
          <include>src/main/resources/templates/**/*.html</include>
          <include>*.md</include>
        </includes>
        <trimTrailingWhitespace/>
        <endWithNewline/>
      </format>
    </formats>

    <java>
      <!-- <includes> omitido de propósito: o default do bloco <java> já é
           src/main/java/**/*.java + src/test/java/**/*.java -->
      <importOrder/>
      <removeUnusedImports/>
      <expandWildcardImports/>
      <!-- trocar por <forbidWildcardImports/> quando a base estiver estável:
           aí o wildcard passa a reprovar o build em vez de ser expandido -->
      <shortenFullyQualifiedTypes/>

      <!-- <style> importa: GOOGLE ou AOSP aqui voltariam para 100 colunas -->
      <palantirJavaFormat>
        <version>${palantir.version}</version>
        <style>PALANTIR</style>
      </palantirJavaFormat>

      <!-- DEPOIS do formatter, sempre: ele conserta quebras de linha que o
           formatter introduziu em anotações. Antes dele não há o que consertar. -->
      <formatAnnotations/>
    </java>
  </configuration>

  <executions>
    <execution>
      <goals><goal>check</goal></goals>
      <phase>verify</phase>
    </execution>
  </executions>
</plugin>
```

**Três erros que o rascunho óbvio comete:**

| Erro | Por quê |
|---|---|
| `<include>.java</include>` | Casa um arquivo *literalmente chamado* `.java`. Precisa de glob — ou, melhor, omitir `<includes>` e usar o default do bloco `<java>` |
| `<format>` genérico cobrindo `.java` | O bloco `<java>` já trata esses arquivos; dois blocos sobre o mesmo alvo uma hora conflitam |
| `<formatAnnotations/>` antes do formatter | O README é explícito: *"add the `formatAnnotations` rule **after** a Java formatter"* |

### 2.2 Implantar Spotless num projeto que ainda não tem

**Palantir e google-java-format são formatters totais**: reescrevem o arquivo
inteiro, não apenas as linhas longas. Escolher 120 em vez de 100 **não diminui o
primeiro `spotless:apply`** — ele reformata tudo de qualquer jeito.

A decisão da equipe é **commit isolado por projeto**, com todos atualizando o
repositório local em seguida. Nessa ordem:

1. **Fechar ou mergear as MRs abertas antes.** Reformatação global conflita com
   toda MR viva. Rebasear depois é pior do que esperar.
2. Aplicar e commitar **só a formatação**, sem nenhuma mudança de lógica junto —
   é o que torna o commit revisável sem lê-lo linha a linha.
3. Registrar o hash em `.git-blame-ignore-revs` na raiz do repositório. Sem isso,
   `git blame` de todo o projeto passa a apontar para esse commit.
4. Cada pessoa habilita o arquivo localmente — **não é automático**:
   `git config blame.ignoreRevsFile .git-blame-ignore-revs`
5. Avisar a equipe para atualizar antes de começar qualquer trabalho novo.

**O beco sem saída: o commit de reformatação move a linha de corte do Sonar.**
O SCM Publisher usa `git blame` para decidir o que é código novo (ver
`basis-ci-gitlab/references/sonar-analise-e-quality-gate.md`). Depois da
reformatação em massa, **toda linha reformatada passa a ter a data do commit de
formatação** — e cai dentro do período de *new code*. O gate, que cobra cobertura
e zero issues em código novo, passa a julgar a base legada inteira. A primeira MR
depois disso reprova por código que ninguém tocou.

`.git-blame-ignore-revs` resolve o `git blame` humano; **não há garantia de que o
SCM Publisher do Sonar o respeite** — confirme na instância antes de contar com
isso. O caminho seguro é **redefinir a baseline de new code no Sonar logo após
mergear a reformatação**, para que o commit fique fora da janela.

**A alternativa que foi considerada e não escolhida** — registrada para não ser
re-litigada às cegas: `<ratchetFrom>origin/develop</ratchetFrom>` faz o Spotless
formatar e cobrar **apenas os arquivos tocados desde a `develop`**. A base
converge branch a branch, sem commit global, sem conflito em MR aberta e sem
mexer na baseline do Sonar — é o mesmo modelo *Clean as You Code* que o Sonar já
aplica. O custo é conviver com formatação heterogênea durante a transição. Se um
projeto novo entrar depois, ou se o big-bang doer num repo grande, é esta a saída.

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

### Asserções do mesmo `actual` vão numa cadeia só

**Dois `assertThat` seguidos sobre o mesmo valor reprovam o quality gate.** É a
`java:S5853` — *Consecutive AssertJ "assertThat" statements should be chained*, code smell de
severidade MINOR —, e a mensagem que aparece na MR é *"Join these multiple assertions subject to
one assertion chain."* Já derrubou MR mais de uma vez pelo mesmo caminho: a segunda verificação
nasce depois da primeira, na revisão ou num ajuste, e entra como statement novo em vez de entrar
na cadeia que já estava lá.

A regra, no Sonar da Basis:
<https://codequality.basis.com.br/coding_rules?open=java%3AS5853&rule_key=java%3AS5853>

```java
// Reprova
assertThat(pagina).contains("Versão " + versao);
assertThat(pagina).doesNotContain("href=\"/retomar\"");

// Passa
assertThat(pagina)
        .contains("Versão " + versao)
        .doesNotContain("href=\"/retomar\"");
```

O que dispara é **adjacência com o mesmo valor testado** — está no nome da regra:
*Consecutive*. Dois `assertThat` em sequência, sem statement no meio, sobre a mesma expressão.
`actual` diferente não dispara, e statement entre as duas quebra a sequência.

**`.as(...)` descreve o que vem depois dele na cadeia**, então dar nome a uma asserção
específica não obriga a quebrá-la em duas:

```java
assertThat(pagina)
        .contains("Versão " + versao)
        .as("prova que a versão está fora do `th:if` do link de retomada")
        .doesNotContain("href=\"/retomar\"");
```

**Não saia varrendo a suíte inteira atrás disso.** Numa base com suíte grande há dezenas de
ocorrências antigas que o Sonar nunca reportou, e o motivo é estrutural: o `check-quality` só
roda em MR, então o que existe é análise de *pull request* — que olha as linhas da MR — e não
análise de branch. Num projeto assim a branch principal pode nunca ter sido analisada, e aí
`api/issues/search` com `branch=` devolve zero enquanto a `pullRequest=<n>` devolve o achado
(ver `basis-ci-gitlab` §6).

**Mas a linha que você tocar entra na análise da MR.** Editar um teste antigo faz as asserções
vizinhas serem avaliadas, e o gate reprova por código que "já estava lá". Ao mexer num arquivo de
teste, encadeie as ocorrências **daquele arquivo** na mesma passada; é mais barato que descobrir
na pipeline.

Para conferir sem esperar a pipeline, com um token de API:

```bash
curl -sS -u "$SONAR_TOKEN:" \
  "https://codequality.basis.com.br/api/issues/search?componentKeys=<chave>&rules=java:S5853&pullRequest=<n>"
```

## 15. Checklist de revisão

Ao revisar ou gerar código Java, verificar em ordem:

1. Erro: exceção tratada uma vez, causa aninhada, tipo do projeto, nada engolido.
2. Nulidade: pacote `@NullMarked`, `@Nullable` só onde o nulo é real, sem `null` retornado em
   coleção, `Optional` só em retorno, `requireNonNull` nas fronteiras não anotadas.
3. Recurso: try-with-resources em tudo que fecha, charset explícito.
4. Segurança: query parametrizada, entrada validada, nada sensível em log, sem segredo no código.
5. Design: dependências por construtor, visibilidade mínima, método curto, sem efeito colateral escondido.
6. Teste: comportamento coberto, nome descritivo, determinístico, asserções do mesmo `actual`
   numa cadeia só.
7. Estilo: Spotless e SonarQube passaram — se não passaram, é build quebrado, não comentário de review.
