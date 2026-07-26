# Layout padrão: sidebar + header

`templates/layout.html` — fragmento único que todas as páginas usam. Assinatura: `layout(content, activeMenu)`.

Cada página:

```html
<html xmlns:th="http://www.thymeleaf.org" th:replace="~{layout :: layout(~{::section}, 'allocations')}">
<body>
<section class="flex flex-col gap-6 h-full min-h-0 overflow-hidden">
    <!-- conteúdo da página -->
</section>
</body>
</html>
```

O `~{::section}` passa a `<section>` da página como `content`. O segundo argumento marca o item ativo no menu — em página fora do menu (erro, login), passar `''`.

## `layout.html`

```html
<!DOCTYPE html>
<html lang="pt-BR" data-theme="caramellatte"
      xmlns:th="http://www.thymeleaf.org"
      xmlns:sec="http://www.thymeleaf.org/extras/spring-security"
      th:fragment="layout(content, activeMenu)">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="_csrf" th:content="${_csrf?.token}">
    <meta name="_csrf_header" th:content="${_csrf?.headerName}">
    <title th:text="#{app.name}">&lt;app&gt; - Basis</title>

    <!-- Tailwind v4 + DaisyUI 5, gerado pelo build em target/classes/static -->
    <link rel="stylesheet" th:href="@{/css/style.css(v=${appVersion})}">
    <!-- JS vendored (nunca CDN) -->
    <script th:src="@{/js/htmx.min.js}"></script>
    <script th:src="@{/js/list.min.js}"></script>

    <link rel="icon" href="/favicons/favicon.ico" sizes="any">
    <link rel="icon" type="image/png" sizes="32x32" href="/favicons/favicon-32x32.png">
    <link rel="apple-touch-icon" sizes="180x180" href="/favicons/apple-touch-icon.png">
    <link rel="manifest" href="/site.webmanifest">
    <meta name="theme-color" content="#cc6d13">

    <style>
        #main-sidebar { transition: width 0.3s ease, border-width 0.3s ease; }
        #main-sidebar.collapsed { width: 0 !important; border-right-width: 0 !important; }
    </style>
</head>

<body class="bg-base-200 min-h-screen font-sans overflow-hidden flex">

    <!-- ============ Sidebar ============ -->
    <aside id="main-sidebar"
           class="w-64 h-screen bg-base-100 border-r border-base-300 flex flex-col shrink-0 z-20 overflow-hidden">
        <div class="p-6 pb-2 shrink-0">
            <img th:src="@{/images/logo-header.png}" alt="Basis Tecnologia" class="h-8 w-auto" />
            <div class="text-[10px] uppercase tracking-widest text-base-content/50 mt-2"
                 th:text="#{app.subtitle}">Subtitulo</div>
        </div>

        <ul class="menu menu-md flex-grow p-4 pt-2 overflow-y-auto">
            <li class="menu-title" th:text="#{menu.group.cadastros}">Cadastros</li>
            <li>
                <a th:href="@{/configs/allocations}"
                   th:classappend="${activeMenu == 'allocations' ? 'active' : ''}">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"
                         stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 21h16.5M4.5 3h15M5.25 3v18" />
                    </svg>
                    <span th:text="#{menu.allocations}">Alocacoes</span>
                </a>
            </li>
            <!-- demais itens/grupos -->
        </ul>

        <div class="mt-auto flex flex-col gap-2 p-4 shrink-0">
            <div class="p-4 bg-base-200 rounded-xl flex items-center gap-3">
                <div class="avatar placeholder">
                    <div class="bg-neutral text-neutral-content rounded-full w-10 shrink-0">
                        <span class="text-xs" th:text="${#strings.substring(currentUser, 0, 2)}">US</span>
                    </div>
                </div>
                <div class="flex-grow overflow-hidden">
                    <div class="text-sm font-bold truncate" th:text="${currentUser}">Usuario</div>
                    <div class="text-xs opacity-50 font-mono" th:text="#{app.user.role}">papel</div>
                </div>
            </div>
            <div class="text-[10px] text-center opacity-30 px-4" th:text="#{app.copyright}">
                Copyright © Basis Tecnologia
            </div>
        </div>
    </aside>

    <!-- ============ Coluna principal ============ -->
    <div class="flex-grow flex flex-col min-w-0 h-screen overflow-hidden">

        <header class="navbar bg-base-100 shadow-sm shrink-0 border-b border-base-300">
            <div class="flex-none">
                <button type="button" class="btn btn-square btn-ghost" onclick="toggleSidebar()"
                        th:title="#{menu.toggle}">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"
                         class="w-5 h-5 stroke-current">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                              d="M4 6h16M4 12h16M4 18h16"></path>
                    </svg>
                </button>
            </div>

            <div class="flex-1 px-2 mx-2 font-bold text-primary flex items-baseline gap-2">
                <span th:text="#{app.name}">Nome da aplicacao</span>
                <span class="text-[10px] font-mono opacity-40" th:text="'v' + ${appVersion}">v0.0.1</span>
            </div>

            <div class="flex-none gap-1">
                <div class="dropdown dropdown-end">
                    <div tabindex="0" role="button" class="btn btn-ghost btn-circle avatar placeholder">
                        <div class="bg-neutral text-neutral-content rounded-full w-8">
                            <span class="text-xs" th:text="${#strings.substring(currentUser, 0, 2)}">US</span>
                        </div>
                    </div>
                    <ul tabindex="0" class="menu dropdown-content bg-base-100 rounded-box z-50 mt-3 w-52 p-2 shadow">
                        <li class="menu-title text-xs" th:text="${currentUser}">Usuario</li>
                        <li sec:authorize="hasRole('<APP>_ADMIN')">
                            <a th:href="@{/admin}" th:text="#{menu.admin}">Administracao</a>
                        </li>
                        <li>
                            <form th:action="@{/logout}" method="post">
                                <button type="submit" class="w-full text-left" th:text="#{menu.logout}">Sair</button>
                            </form>
                        </li>
                    </ul>
                </div>
            </div>
        </header>

        <main class="p-4 flex-grow overflow-hidden flex flex-col min-h-0">
            <div id="error-alert" class="shrink-0"></div>
            <div class="flex-grow overflow-hidden flex flex-col min-h-0" th:insert="${content}">
                <!-- conteúdo da página -->
            </div>
        </main>
    </div>

    <!-- Container permanente para modais carregados por HTMX -->
    <div id="modal-root"></div>

    <script>
        function toggleSidebar() {
            document.getElementById('main-sidebar').classList.toggle('collapsed');
        }

        // Token CSRF em toda requisição HTMX (POST/PUT/DELETE falham com 403 sem isso)
        document.body.addEventListener('htmx:configRequest', evt => {
            const token = document.querySelector('meta[name="_csrf"]')?.content;
            const header = document.querySelector('meta[name="_csrf_header"]')?.content;
            if (token && header) {
                evt.detail.headers[header] = token;
            }
        });
    </script>
</body>
</html>
```

O listener de `htmx:responseError` (alerta em `#error-alert`) está em [`paginas-de-erro.md`](paginas-de-erro.md).

## Cadeia de altura

O que faz "só o conteúdo rolar":

| Elemento | Classes que importam | Papel |
|---|---|---|
| `body` | `overflow-hidden flex` | a janela nunca rola |
| `aside` | `h-screen shrink-0` | altura cheia, não encolhe |
| coluna principal | `flex-grow flex flex-col min-w-0 h-screen overflow-hidden` | ocupa o resto |
| `header` | `shrink-0` | altura natural, fixa |
| `main` | `flex-grow overflow-hidden flex flex-col min-h-0` | recebe a sobra |
| slot do conteúdo | `flex-grow overflow-hidden flex flex-col min-h-0` | repassa a altura para a página |

**`min-h-0` é obrigatório** em cada nível: flex item tem `min-height: auto` por padrão e por isso se recusa a encolher abaixo do conteúdo. Sem ele, a tabela empurra o layout e o scroll acaba na janela — o cabeçalho fixo some junto.

A página continua a cadeia: `<section class="flex flex-col gap-6 h-full min-h-0 overflow-hidden">`, e o bloco rolável (a tabela) leva `flex-grow min-h-0 overflow-y-auto`.

## `@ControllerAdvice` para `appVersion` e `currentUser`

O layout referencia as duas variáveis em toda página; populá-las em cada controller é repetição garantida de esquecer.

```java
@ControllerAdvice
public class GlobalControllerAdvice {

    private final Optional<BuildProperties> buildProperties;

    public GlobalControllerAdvice(@Autowired(required = false) BuildProperties buildProperties) {
        this.buildProperties = Optional.ofNullable(buildProperties);
    }

    @ModelAttribute("appVersion")
    public String appVersion() {
        return buildProperties.map(BuildProperties::getVersion).orElse("0.0.1-DEV");
    }

    @ModelAttribute("currentUser")
    public String currentUser() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth != null && auth.getPrincipal() instanceof OidcUser oidcUser) {
            return oidcUser.getFullName();
        }
        return auth != null ? auth.getName() : "Anonymous";
    }
}
```

`appVersion` vem do `build-info` (goal `build-info` do `spring-boot-maven-plugin`) e serve para duas coisas: aparecer no header e ser o cache-buster do CSS (`/css/style.css?v=...`).

## Regras

- **Um layout só por app.** Variação de tela é composição dentro do `content`, não um segundo `layout-*.html`
- **`activeMenu` sempre passado**, inclusive `''` — omitir quebra o `th:classappend`
- **Menu com ícone SVG inline** (`w-5 h-5`, `stroke-currentColor`) — herda a cor do tema e não depende de fonte de ícone externa
- **Logout por `POST`** (`/logout` do Spring Security com CSRF), nunca link `GET`
- **Item de menu por role**: `sec:authorize="hasRole('<APP>_ADMIN')"` (requer `thymeleaf-extras-springsecurity6`) — esconder no menu não substitui a proteção no `SecurityFilterChain`
- **`#modal-root` e `#error-alert` vivem no layout** — fragmento carregado por HTMX assume que eles existem
