# Cliente Java: `@HttpExchange` + `RestClient`

Sem SDK. A superfície do SGO que o projeto usa vira uma interface declarativa, e o Spring gera a
implementação. Duas aplicações da Basis (`judge-admin` e `trabalhe-conosco`) chegaram à mesma
forma de forma independente.

## 1. A interface é documentação

Cada método é um endpoint, e o javadoc é onde mora o motivo. O que segue é a superfície real de
uma integração madura, encurtada:

```java
/// Superfície do SGO que este projeto usa.
///
/// Os dois endpoints `idalko-igrid` são do plugin TableGrid e não fazem parte da API do Jira.
@HttpExchange
public interface SgoClient {

    @GetExchange("/rest/api/2/issue/createmeta")
    JsonNode createmeta(@RequestParam("projectIds") String projectIds,
                        @RequestParam("issuetypeIds") String issueTypeIds,
                        @RequestParam("expand") String expand);

    @PostExchange("/rest/api/2/issue")
    JsonNode criarOcorrencia(@RequestBody JsonNode payload);

    /// Busca por JQL.
    ///
    /// `POST` e não `GET` de propósito: com `GET`, a JQL vai na URL -- e a JQL que este projeto
    /// monta tem um CPF dentro. URL entra no log de acesso do Jira, no histórico do navegador e
    /// em qualquer proxy do caminho. Dado pessoal não anda em query string.
    @PostExchange("/rest/api/2/search")
    JsonNode buscar(@RequestBody JsonNode jql);

    /// **Os campos que a tela de *edição* aceita** -- que não são os mesmos da criação.
    @GetExchange("/rest/api/2/issue/{chave}/editmeta")
    JsonNode editmeta(@PathVariable String chave);

    /// `void` porque a resposta de sucesso é `204 No Content`: um corpo desserializado aqui
    /// seria sempre vazio, e o que interessa quando dá errado vem na exceção.
    @PutExchange("/rest/api/2/issue/{chave}")
    void editarOcorrencia(@PathVariable String chave, @RequestBody JsonNode payload);

    /// O que esta credencial pode fazer nesta ocorrência. `EDIT_ISSUE` é a que decide.
    @GetExchange("/rest/api/2/mypermissions")
    JsonNode minhasPermissoes(@RequestParam("issueKey") String chave);

    /// `fields=attachment` não é economia de banda: sem ele o Jira devolve a ocorrência
    /// inteira -- e a ocorrência inteira é o cadastro da pessoa.
    @GetExchange("/rest/api/2/issue/{chave}?fields=attachment")
    JsonNode anexosDaOcorrencia(@PathVariable String chave);

    @GetExchange("/rest/idalko-igrid/1.0/grid/{gridId}/issue/{issueId}")
    JsonNode listarLinhasGrid(@PathVariable String gridId, @PathVariable String issueId);

    @PostExchange("/rest/idalko-igrid/1.0/grid/{gridId}/issue/{issueId}")
    JsonNode inserirLinhasGrid(@PathVariable String gridId, @PathVariable String issueId,
                               @RequestBody JsonNode payload);

    /// O Jira exige `X-Atlassian-Token: no-check` no envio de anexo; o cabeçalho é aplicado
    /// a todas as chamadas na configuração, porque é inócuo nas demais.
    @PostExchange(value = "/rest/api/2/issue/{chave}/attachments",
                  contentType = MediaType.MULTIPART_FORM_DATA_VALUE)
    JsonNode anexar(@PathVariable String chave,
                    @RequestBody MultiValueMap<String, Object> parte);
}
```

`JsonNode` e não DTO: a resposta do Jira é larga, instável entre versões e usada em pedaços. Um
DTO por endpoint seria um segundo mapa a manter, divergindo do primeiro na próxima mudança do RH.

## 2. A configuração do bean

Está na §1 da SKILL. Três pontos que costumam ser esquecidos:

- **HTTP/1.1 explícito.** O cliente do JDK negocia HTTP/2 por padrão, e o SGO é anterior a ele.
- **`X-Atlassian-Token: no-check` como header default.** Exigido só no anexo; inócuo no resto.
- **Diga no arranque se há credencial.** `log.warn("sem credencial: só leitura anônima
  funciona")` é o que separa "a verificação está desligada" de "a verificação diz que está
  tudo livre".

## 3. As propriedades

`@ConfigurationProperties` record, prefixo `application.sgo`, com defaults no compact constructor
— e o javadoc carregando o porquê de cada um:

```java
/// @param fuso fuso do servidor Jira. As colunas de data do TableGrid guardam milissegundos de
///     época, e o servidor os renderiza no fuso dele -- meia-noite em UTC apareceria como 21h do
///     dia anterior, fazendo a data andar um dia para trás.
/// @param agendamento liga o consumidor da fila de envio. **Checado em runtime**, e não por
///     `@ConditionalOnProperty`.
@ConfigurationProperties(prefix = "application.sgo")
public record SgoProperties(String baseUrl, String username, String password,
                            Duration readTimeout, String projectId, String issueTypeId,
                            String gridId, ZoneId fuso, Boolean agendamento) {

    public SgoProperties {
        if (agendamento == null)  agendamento = Boolean.TRUE;
        if (readTimeout == null)  readTimeout = Duration.ofSeconds(90);
        if (fuso == null)         fuso = ZoneId.of("America/Sao_Paulo");
    }

    public boolean temCredencial() {
        return username != null && !username.isBlank()
            && password != null && !password.isBlank();
    }
}
```

**A separação de responsabilidade tem consequência de pacote.** Endereço, credencial e timeout
são "como alcançar o SGO" e ficam na infraestrutura. Insistir ou desistir é regra de negócio e
fica no módulo que envia — `RetryProperties` mora junto da saga, não junto do cliente.

## 4. A saga com estado por etapa

Um enum de etapa, persistido, é o que permite retomar em vez de recomeçar:

```java
public enum Etapa {
    PENDENTE,           // nada saiu ainda
    OCORRENCIA_CRIADA,  // a chave está guardada aqui; daqui em diante recomeçar é destrutivo
    HISTORICO_ENVIADO,
    CONCLUIDA,
    DESCARTADA;         // falha permanente; não se retenta, e o motivo fica guardado

    public boolean terminal() { return this == CONCLUIDA || this == DESCARTADA; }
}
```

O laço avança o quanto der numa passagem e **para na primeira falha** — insistir na mesma etapa
dentro da mesma passagem é retry sem espera, que é o que derruba um serviço que está voltando.

```java
private void processar(Envio inicial) {
    Envio envio = inicial;
    while (!envio.etapa().terminal()) {
        Envio depois;
        try {
            depois = executar(envio);
        } catch (RuntimeException e) {
            aplicarFalha(envio, classificacao.de(e));
            return;
        }
        if (depois.etapa() == Etapa.CONCLUIDA) { desfecho.concluir(depois); return; }
        repositorio.guardar(depois);
        envio = depois;
    }
}
```

Quatro detalhes que só aparecem quando isso roda de verdade:

- **`exigirSucesso(resposta)` depois de cada chamada.** O Jira responde `200` com corpo de erro;
  sem a conferência, uma recusa passa por sucesso.
- **A resposta da criação sem `key` ou sem `id` é falha alta.** Se a ocorrência foi criada assim
  mesmo, ela vira órfã — ninguém tem como retomá-la nem achá-la.
- **A escrita final e o aviso a quem chamou vão na mesma transação**, numa classe própria.
  Gravar `CONCLUIDA` e cair antes de avisar deixa um pedido em limbo. As chamadas HTTP ficam
  **fora** dessa transação: nada segura transação durante ida e volta de rede.
- **Lote por passagem** (algo como 20). Não é ajuste fino: é o que evita que a primeira passagem
  depois de uma indisponibilidade longa bata no SGO com a fila inteira de uma vez.

## 5. O agendador

```java
/// `fixedDelay` e não `fixedRate`: com taxa fixa, uma passagem que demore mais que o intervalo
/// -- porque o SGO está lento, que é justamente quando há fila -- teria a seguinte começando
/// por cima dela.
///
/// **O desligamento é checado em runtime, e não por `@ConditionalOnProperty`.** A condição do
/// Spring é avaliada uma vez só, e numa imagem nativa essa vez é o **build**.
@Component
class AgendamentoEnvio {

    private final boolean ligado;

    AgendamentoEnvio(EnvioSgoInterno envios, SgoProperties props) {
        this.envios = envios;
        this.ligado = props.agendamento();
        if (!ligado) log.info("Consumidor da fila de envio ao SGO: DESLIGADO por configuração");
    }

    @Scheduled(fixedDelayString = "${application.sgo.intervalo-da-fila:30s}")
    void processarFila() {
        if (!ligado) return;
        envios.processarFila();
    }
}
```

Separar o agendador da regra também serve ao teste: um agendador que fala com o SGO rodando no
meio de qualquer contexto que suba é ruído, e o teste da saga precisa acionar a rotina à mão.

## 6. Testes

**Nenhum teste automatizado toca o SGO.** WireMock para a saga e para a retomada a partir de
cada etapa; fixture versionada do `createmeta` para o catálogo; unitário para o mapeamento dos
campos, para a conversão de data e para a classificação de falha.

O teste que vale mais do que parece: o de integração que **lê a parte do multipart que chegou ao
servidor** e compara o hash dela com o registrado. Ele prova o que saiu pela rede, não o que o
código pretendia mandar.

A verificação de ponta a ponta contra o SGO de verdade é manual, atrás de um profile próprio, e
segue as regras da §9 da SKILL.
