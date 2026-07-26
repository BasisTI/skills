# Logging: banner de startup e logs de depuração

Complementa `basis-java-code-standards` §9 (SLF4J, placeholders, níveis, nada sensível em log). Aqui está o que é específico de app Spring.

## Banner de startup

Toda app Spring da Basis loga, depois de subir, um bloco com nome, URLs e profiles ativos. Serve para responder na hora as três perguntas que aparecem em qualquer suporte: *qual app é essa*, *em que porta/URL ela está* e *com que profile ela subiu* — sem precisar de acesso ao pod nem ao console.

`main` captura o `Environment` do contexto já iniciado e loga:

```java
package br.com.basis.<app>;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.Marker;
import org.slf4j.MarkerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.core.env.Environment;
import org.springframework.modulith.Modulithic;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.Optional;

@SpringBootApplication
@EnableConfigurationProperties(ApplicationProperties.class)
@Modulithic
public class <App>Application {

    public static final Marker CRLF_SAFE_MARKER = MarkerFactory.getMarker("CRLF_SAFE");
    private static final Logger LOG = LoggerFactory.getLogger(<App>Application.class);

    static void main(String[] args) {
        SpringApplication app = new SpringApplication(<App>Application.class);
        Environment env = app.run(args).getEnvironment();
        logApplicationStartup(env);
    }

    private static void logApplicationStartup(Environment env) {
        String protocol = Optional.ofNullable(env.getProperty("server.ssl.key-store"))
                .map(_ -> "https")
                .orElse("http");
        String applicationName = env.getProperty("spring.application.name");
        String serverPort = env.getProperty("server.port");
        String contextPath = Optional.ofNullable(env.getProperty("server.servlet.context-path"))
                .filter(path -> !path.isBlank())
                .orElse("/");
        String hostAddress = "localhost";
        try {
            hostAddress = InetAddress.getLocalHost().getHostAddress();
        } catch (UnknownHostException _) {
            LOG.warn("Nao foi possivel determinar o host, usando `localhost` como fallback");
        }
        LOG.info(
                CRLF_SAFE_MARKER,
                """

                        ----------------------------------------------------------
                        \tApplication '{}' is running! Access URLs:
                        \tLocal: \t\t{}://localhost:{}{}
                        \tExternal: \t{}://{}:{}{}
                        \tProfile(s): \t{}
                        ----------------------------------------------------------""",
                applicationName,
                protocol,
                serverPort,
                contextPath,
                protocol,
                hostAddress,
                serverPort,
                contextPath,
                env.getActiveProfiles().length == 0 ? env.getDefaultProfiles() : env.getActiveProfiles()
        );
    }
}
```

Detalhes que importam:

- **Loga depois de `app.run(...)`**, com o `Environment` do contexto pronto — antes disso os profiles e a porta efetiva ainda não estão resolvidos.
- **`server.port` resolvido pelo `Environment`**, não a constante do yml — com `server.port: 0` (porta aleatória em teste) o valor real aparece.
- **Marker `CRLF_SAFE`**: analisadores estáticos (Sonar, Fortify) marcam log com dado dinâmico como possível log injection/CRLF. O marker documenta que o conteúdo vem do `Environment`, não de entrada de usuário, e permite excluir a ocorrência pela regra em vez de por `//NOSONAR` espalhado.
- **Text block com `\t`** em vez de concatenação — o bloco sai formatado no console e num agregador de log continua sendo um evento só.
- **`_` como parâmetro não usado** (unnamed variable, Java 21+) no lambda e no `catch`.
- Nada de segredo no banner. Se for útil listar dependências (URL do banco, issuer do Keycloak), só host/porta — nunca usuário e senha.

Amplia bem quando a app tem mais contexto relevante: adicionar linha com versão da aplicação (`build.version` via `build-info` do `spring-boot-maven-plugin`) e com o issuer OIDC ativo.

## Logs de DEBUG nos pontos de entrada

Todo ponto onde um estímulo externo entra na aplicação loga em `DEBUG` **o que chegou**. Sem isso, depurar um comportamento estranho em ambiente começa por adivinhar se a requisição/mensagem chegou.

Pontos de entrada: `@Controller`/`@RestController`, consumer de SCS/Rabbit, `@Scheduled`, listener de evento Modulith, callback de webhook, job de linha de comando.

```java
@GetMapping("/pedidos/{id}")
public String detalhe(@PathVariable Long id, Model model) {
    LOG.debug("GET /pedidos/{}", id);
    ...
}
```

```java
@Bean
Consumer<CurriculoRecebido> curriculoRecebido() {
    return evento -> {
        LOG.debug("Mensagem recebida: curriculoRecebido candidatura={}", evento.candidaturaId());
        ...
    };
}
```

Regras:

- **Identificador, não payload inteiro.** Logar id/chave e os campos que direcionam o fluxo. Payload completo em `TRACE`, quando útil.
- **Nada de PII/segredo**, nem em `DEBUG`: currículo, CPF, e-mail, token e senha ficam de fora — o log de dev vaza igual ao de prod.
- **Não substituir por interceptor genérico** que loga toda requisição: o log no método diz qual handler foi escolhido, o que é justamente o que costuma estar errado.
- Em consumer, logar também o **desfecho** (`processado` / `rejeitado, motivo=...`) — mensagem que entra e não tem contraparte no log é o sintoma mais claro de consumer travado.

## Logs de DEBUG em processamento complexo

Método com várias etapas, chamada externa, regra de negócio densa ou laço sobre volume: um `DEBUG` no início (com a entrada) e um no fim (com o resultado e, quando faz sentido, a duração).

```java
public ResultadoMatching calcular(Long vagaId, List<Long> candidaturas) {
    LOG.debug("Iniciando matching vaga={} candidaturas={}", vagaId, candidaturas.size());
    long inicio = System.nanoTime();

    ResultadoMatching resultado = ...;

    LOG.debug("Matching concluido vaga={} aprovadas={} duracao={}ms",
            vagaId, resultado.aprovadas().size(), Duration.ofNanos(System.nanoTime() - inicio).toMillis());
    return resultado;
}
```

Critério para decidir se o método merece o par início/fim: se ele falhar em produção, o log de erro sozinho responde *com que entrada* e *até onde foi*? Se não responde, tem que ter o par.

- Início e fim **do mesmo método**, com o mesmo identificador nas duas linhas — é o que permite parear e medir.
- Etapas intermediárias só quando cada etapa pode falhar sozinha; caso contrário viram ruído.
- Caminho de exceção não precisa de `DEBUG` de fim — o log/relançamento da exceção já cobre (ver `basis-java-code-standards` §5).
- Medição de duração no `DEBUG` é diagnóstico, não métrica. O que precisa de acompanhamento contínuo vai para Micrometer (`@Timed`/`Timer`), exposto no Actuator.
- `LOG.isDebugEnabled()` só quando montar o argumento custa (serializar, consultar, concatenar coleção grande) — com placeholder `{}` e argumento pronto, o guard é ruído.

## Níveis por ambiente

`application.yml` (default, vale para qualquer ambiente):

```yaml
logging:
  level:
    root: INFO
    br.com.basis.<app>: INFO
```

`application-dev.yml`:

```yaml
logging:
  level:
    br.com.basis.<app>: DEBUG
```

Em prod o pacote da app fica em `INFO` e sobe para `DEBUG` sob demanda, sem redeploy, via env var (`LOGGING_LEVEL_BR_COM_BASIS_<APP>=DEBUG`) ou pelo endpoint `/actuator/loggers` quando exposto. É essa a razão de o `DEBUG` estar espalhado no código: ele é o botão de diagnóstico que se liga em produção.

Ligar `DEBUG` em pacote de terceiro (`org.springframework.security`, `org.springframework.jdbc.core: TRACE`) é ferramenta de investigação pontual — fica no `dev` durante a investigação, não commitado como padrão. `org.springframework.jdbc.core: TRACE` em particular loga valores de parâmetro de SQL, ou seja, dado de negócio inteiro no log.
