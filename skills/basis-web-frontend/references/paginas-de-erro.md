# Páginas de erro

**Nenhuma app da Basis pode mostrar a Whitelabel Error Page.** Ela é o default do Spring Boot quando não existe `templates/error.html`: fundo branco, "There was an unexpected error (type=Internal Server Error, status=500)", sem identidade visual, sem caminho de volta e sem nada que o usuário possa passar para o suporte.

O padrão substitui isso por uma tela com a identidade Basis, mensagem em linguagem de usuário e **traceId visível**.

## `templates/error.html`

Resolvido automaticamente pelo `BasicErrorController` para qualquer status não tratado por um `@ExceptionHandler`. Usa o layout normal, com `activeMenu` vazio.

```html
<html xmlns:th="http://www.thymeleaf.org" th:replace="~{layout :: layout(~{::section}, '')}">
<body>
<section class="flex flex-col items-center justify-center h-full gap-6">
    <div class="card w-full max-w-md bg-base-100 shadow-xl border border-error">
        <div class="card-body items-center text-center p-10">

            <img th:src="@{/images/Logo-BASIS-300x130.png}" alt="Basis Tecnologia" class="h-20 w-auto mb-2" />

            <div class="badge badge-error badge-lg gap-2 py-3 px-4 text-base font-bold">
                <span th:text="#{error.status}">Status</span>
                <span th:text="${status}">500</span>
            </div>

            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"
                 stroke-width="1.5" stroke="currentColor" class="w-12 h-12 text-error mt-4">
                <path stroke-linecap="round" stroke-linejoin="round"
                      d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z" />
            </svg>

            <h2 class="card-title text-2xl font-black text-error" th:text="#{error.generic.title}">Erro</h2>
            <p class="text-base-content/70 mt-2" th:text="#{error.generic.message}">
                A operacao falhou. Tente novamente.
            </p>

            <a th:href="@{/}" class="btn btn-primary w-full gap-2 mt-6">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"
                     stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                    <path stroke-linecap="round" stroke-linejoin="round"
                          d="m2.25 12 8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12" />
                </svg>
                <span th:text="#{error.generic.return}">Voltar ao inicio</span>
            </a>

            <div class="divider my-4"></div>

            <div class="text-[10px] font-mono opacity-50 bg-base-200 p-2 rounded-lg w-full break-all text-left">
                <div th:if="${traceId != null and !#strings.isEmpty(traceId)}">
                    <span th:text="#{error.trace}">Trace ID</span>: <span th:text="${traceId}">N/A</span>
                </div>
                <div th:if="${path != null and !#strings.isEmpty(path)}">
                    <span th:text="#{error.path}">Caminho</span>: <span th:text="${path}">/path</span>
                </div>
            </div>
        </div>
    </div>
</section>
</body>
</html>
```

Elementos obrigatórios: logo, status, mensagem amigável, botão de volta, traceId e caminho em bloco discreto.

O **traceId é o ponto principal da tela**: é o que o usuário lê no telefone para o suporte e o que liga a tela ao log do servidor. Sem ele, "deu erro na tela de férias" vira uma busca cega no log.

## Configuração

```yaml
server:
  error:
    include-stacktrace: never     # stack trace nunca vai para o usuário
    include-message: never        # mensagem crua de exceção idem (pode vazar detalhe interno)
    include-exception: false
    whitelabel:
      enabled: false
```

Em `dev`, `include-message: always` ajuda; em prod, nunca. O detalhe completo vive no log, correlacionado pelo traceId.

## `traceId` no modelo

O `BasicErrorController` não popula `traceId`. Um `@ControllerAdvice` global resolve para as duas rotas (página de erro e handlers específicos):

```java
@ControllerAdvice
public class ErrorContextAdvice {

    private final Tracer tracer;   // io.micrometer.tracing.Tracer

    public ErrorContextAdvice(Tracer tracer) {
        this.tracer = tracer;
    }

    @ModelAttribute("traceId")
    public String traceId() {
        Span span = tracer.currentSpan();
        return span != null ? span.context().traceId() : "N/A";
    }
}
```

Sem `micrometer-tracing` no projeto, usar o id de correlação que a app já tiver no MDC — o requisito é haver **algum** identificador comum entre tela e log.

## Erros específicos

Casos frequentes merecem tela própria, com contexto útil (o que não foi encontrado, para onde voltar), em vez da genérica:

```java
@ControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger LOG = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(EntityNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ModelAndView entidadeNaoEncontrada(EntityNotFoundException ex) {
        LOG.warn("Entidade nao encontrada: {}", ex.getMessage());

        ModelAndView mav = new ModelAndView("error/entity-not-found");
        mav.addObject("message", ex.getMessage());
        mav.addObject("featureName", ex.getFeatureName());
        mav.addObject("returnUrl", ex.getReturnUrl());
        return mav;
    }
}
```

`templates/error/entity-not-found.html` segue o mesmo desenho da genérica, trocando o botão "voltar ao início" por "voltar para \<a lista de onde veio\>" (`returnUrl`).

Handler de fronteira é o caso em que capturar `Exception` é intencional — ver `basis-java-code-standards` §5. Logar lá com a exceção como último argumento; a tela mostra só a mensagem amigável.

## Erro em requisição HTMX

Uma resposta de erro para `hx-get`/`hx-post` **não pode** substituir um pedaço da tela pela página de erro inteira — o resultado é uma UI com sidebar dentro de um card. O layout intercepta e mostra um alerta:

```html
<script>
    document.body.addEventListener('htmx:responseError', function (evt) {
        const container = document.getElementById('error-alert');
        if (!container) {
            return;
        }
        const status = evt.detail.xhr.status;
        container.innerHTML = `
            <div class="alert alert-error shadow-lg mb-4">
                <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6"
                     fill="none" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                          d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <span>[[#{error.generic.title}]] (${status})</span>
                <button class="btn btn-sm btn-ghost" onclick="this.parentElement.remove()">✕</button>
            </div>`;
    });
</script>
```

Alternativa quando o erro é de negócio e pertence a um trecho específico da tela: o Controller devolve **200 com o fragmento em estado de erro** (alerta dentro do próprio card), em vez de status 4xx/5xx. Erro esperado de negócio não é falha HTTP.

## Chaves de mensagem

```properties
# messages_pt_BR.properties
error.status=Status
error.trace=Trace ID
error.path=Caminho
error.generic.title=Ocorreu um erro
error.generic.message=A operação não pôde ser concluída. Tente novamente ou informe o Trace ID ao suporte.
error.generic.return=Voltar ao início
error.notfound.title=Registro não encontrado
error.notfound.return=Voltar para
error.forbidden.title=Acesso negado
error.forbidden.message=Seu usuário não tem permissão para esta funcionalidade.
```

Mensagem de usuário diz **o que aconteceu e o que fazer**. Nada de "NullPointerException", nome de tabela, SQL ou classe Java na tela.

## Checklist

- [ ] `templates/error.html` existe e usa o layout da aplicação
- [ ] `whitelabel.enabled: false`, `include-stacktrace: never` em prod
- [ ] traceId visível na tela e presente no log do handler
- [ ] Botão de volta que não depende do histórico do navegador
- [ ] `htmx:responseError` tratado no layout
- [ ] Telas de 404/403 com contexto próprio
- [ ] Nenhuma mensagem técnica exposta ao usuário
