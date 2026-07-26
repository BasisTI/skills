---
name: basis-web-frontend
description: Use when building or changing the web UI of a Basis application — Thymeleaf + HTMX + Tailwind v4 + DaisyUI with the `caramellatte` theme, standard layout with left sidebar and header, listing tables with pinned header/footer where only the rows scroll, forms aligned with Tailwind utilities, and a custom error page so the user never hits the Whitelabel Error Page. Activate for new screens, templates and fragments, table/listing work, form layout, error pages, theme/branding, or the Tailwind/DaisyUI build.
---

# Basis Web Frontend

Padrões da Basis para a UI de apps web. Pareada com `basis-spring-app` (aquela cobre a app Spring; esta cobre tudo que vive em `templates/` e no build de CSS/JS).

## 1. Stack e princípios

- **Thymeleaf** para renderização server-side; **HTMX** para interatividade; **Tailwind v4** + **DaisyUI 5** para estilo; **List.js** quando a tabela precisa de ordenação/filtro client-side
- **HTML é gerado no servidor.** Fragmento Thymeleaf trocado por HTMX é o default; JS solto só quando não há alternativa
- **Nada de framework SPA** nesta stack (Angular é a alternativa quando o caso pede, e aí é outra decisão de projeto — ver `basis-spring-app`)
- **Componente DaisyUI antes de utilitário Tailwind, utilitário antes de CSS próprio.** `<style>` no template é última instância e precisa de motivo
- **Sem texto hardcoded**: todo rótulo vem de `#{chave}` (`messages.properties`) — é o que permite trocar termo de negócio sem caçar string em template
- **JS de terceiro é vendored**, servido do próprio app (ver [`references/frontend-build.md`](references/frontend-build.md)) — nunca CDN: app interno roda em rede fechada, e CDN adiciona dependência externa no caminho de renderização

## 2. Tema e identidade

- **Tema DaisyUI: `caramellatte`**, declarado em `data-theme` no `<html>` do layout e habilitado no `input.css`:
  ```css
  @plugin "daisyui" {
    themes: light --default, dark --prefersdark, caramellatte;
  }
  ```
- **Usar as cores semânticas do tema** (`bg-base-100`, `bg-base-200`, `text-base-content`, `text-primary`, `badge-error`, `alert-warning`), nunca cor crua (`bg-white`, `text-gray-700`, `#cc6d13`) — cor crua quebra ao trocar de tema e destoa do resto do sistema
- **Hierarquia de superfície**: fundo da página `base-200`, cartões/sidebar/navbar `base-100`, bordas `border-base-300`. Texto secundário por opacidade (`text-base-content/60`), não por cor fixa
- **Logo Basis** em `src/main/resources/static/images/` (único diretório versionado dentro de `static/`): versão completa na página de erro/login, versão reduzida no topo da sidebar. Cópias em [`references/assets/`](references/assets/)
- **Favicon + `theme-color`** configurados no `<head>` — `<meta name="theme-color" content="#cc6d13">` alinhado ao `caramellatte`
- Cor de marca que não existe no tema entra como token, não como valor espalhado:
  ```css
  @theme { --color-basis-blue: #003366; }
  ```

## 3. Layout padrão: sidebar à esquerda + header

Todo app usa o mesmo esqueleto — `templates/layout.html` com `th:fragment="layout(content, activeMenu)"`, e cada página faz `th:replace="~{layout :: layout(~{::section}, 'chave-do-menu')}"`.

- **Sidebar à esquerda** (`w-64`, `bg-base-100`, borda à direita): logo no topo, `ul.menu` com `li.menu-title` agrupando por área, item ativo por `th:classappend="${activeMenu == 'x' ? 'active' : ''}"`, ícone SVG inline em cada item
- **Rodapé da sidebar**: bloco do usuário logado (avatar + nome + papel) e copyright. Logout e ações de perfil ficam aqui ou no canto direito do header — um lugar só, o mesmo em todas as apps
- **Header (`navbar`)**: botão de recolher a sidebar, título da aplicação e versão (`appVersion`); à direita, ícones de perfil/ações globais
- **A sidebar recolhe** (`w-0` + `border-r-0` com `transition-[width]`) — em tela pequena o conteúdo precisa da largura inteira
- **`activeMenu`** é sempre passado, mesmo vazio (`''`) em páginas fora do menu, como a de erro
- **Contêineres fixos no layout**: `<div id="error-alert">` (alvo dos erros de HTMX) e `<div id="modal-root">` (alvo dos modais) — evita que cada tela invente o seu
- **`appVersion` e `currentUser`** vêm de um `@ControllerAdvice` com `@ModelAttribute`, não de cada controller

### Cadeia de altura — o detalhe que faz o resto funcionar

Para que só o conteúdo role (e a tabela role dentro dele), a cadeia inteira precisa declarar altura e permitir encolher:

```html
<body class="min-h-screen overflow-hidden flex">
  <aside class="h-screen shrink-0 …">…</aside>
  <div class="flex-grow flex flex-col min-w-0 h-screen overflow-hidden">
    <header class="shrink-0 …">…</header>
    <main class="p-4 flex-grow overflow-hidden flex flex-col min-h-0">
      <div id="error-alert" class="shrink-0"></div>
      <div class="flex-grow overflow-hidden flex flex-col min-h-0" th:insert="${content}"></div>
    </main>
  </div>
</body>
```

`min-h-0` em todo elemento flex que contém área rolável: sem ele o filho estoura o pai (o default `min-height: auto` do flex item impede o encolhimento) e o scroll vai parar na janela inteira. É a causa de quase todo "a tabela empurrou o rodapé para fora da tela".

Ver [`references/layout.md`](references/layout.md) — template completo comentado.

## 4. Tabelas e listagens

**Regra: cabeçalho e rodapé sempre visíveis; só as linhas de conteúdo rolam.** Vale para toda listagem — a primeira tela de um cadastro é quase sempre uma tabela, e tabela cujo cabeçalho some ao rolar obriga o usuário a subir para lembrar o que é cada coluna.

```html
<div class="card bg-base-100 shadow-xl border border-base-300 flex-grow min-h-0 overflow-hidden flex flex-col">
  <div class="card-body p-0 flex-grow min-h-0 flex flex-col">
    <div class="flex-grow overflow-y-auto min-h-0">
      <table class="table table-zebra table-pin-rows w-full border-separate border-spacing-0">
        <thead>…</thead>   <!-- fixo no topo -->
        <tbody>…</tbody>   <!-- rola -->
        <tfoot>…</tfoot>   <!-- fixo embaixo: totais, contagem -->
      </table>
    </div>
  </div>
</div>
```

- **`table-pin-rows`** (DaisyUI) fixa as linhas de `<thead>` e `<tfoot>` dentro do contêiner rolável. Equivalente explícito, quando precisar de controle fino: `sticky top-0 z-10 bg-base-200` nas `th` e `sticky bottom-0 z-10 bg-base-200` nas `td` do `tfoot`
- **`border-separate border-spacing-0`** é obrigatório: com `border-collapse` (default do DaisyUI) a borda das células fixadas some ao rolar. A borda vai na célula (`border-b border-base-300`), não na linha
- **Fundo opaco** nas células fixadas (`bg-base-200`) — sem isso o conteúdo rola por baixo e aparece através
- **Quem rola é o `div` intermediário** (`overflow-y-auto min-h-0`), nunca a página. O `<table>` não recebe `overflow`
- **`<tfoot>` sempre presente quando há valor agregado** (total, soma, contagem de registros) — é a informação que o usuário mais procura e a que fica mais longe do olho numa lista longa
- **Ordenação/filtro client-side** com List.js: `data-sort` nas `th`, `valueNames` no init, e `htmx.process(list.list)` no evento `updated` — sem isso os `hx-*` das linhas reordenadas param de funcionar
- **Volume grande é paginação server-side**, não `overflow` com 10 mil linhas no DOM
- **Ação por linha** com ícone `btn-ghost btn-sm btn-square` na última coluna, alinhada à direita, com `th:title` explicando

Ver [`references/tabelas.md`](references/tabelas.md) — tabela completa com `tfoot` fixo, List.js e variantes.

## 5. Formulários

**Regra: alinhamento e espaçamento vêm de utilitário Tailwind — nunca campo solto no HTML.** Formulário sem estrutura (label colado no input, campos de larguras diferentes, botão encostado no último campo) é o defeito visual mais comum e o mais fácil de evitar.

- **Cada campo** é um bloco `fieldset`/`form-control` com label, controle e (quando houver) mensagem de erro/ajuda — nunca `<input>` sem `<label>` associado
- **Espaçamento vertical no contêiner**, não `margin` por campo: `<form class="flex flex-col gap-4">`
- **Grid responsivo** para agrupar: `grid grid-cols-1 md:grid-cols-2 gap-4`; campo largo ocupa `md:col-span-2`. Nunca depender de largura fixa em `px`
- **Larguras uniformes**: `input input-bordered w-full`, `select select-bordered w-full` — campo que "encolhe sozinho" desalinha a coluna inteira
- **`font-mono`** em campo de dado técnico (código, contrato, CNPJ, telefone) — alinha dígito e facilita conferência
- **Ações no fim**, separadas do último campo e alinhadas à direita: `<div class="card-actions justify-end mt-4">`; primária `btn-primary`, secundária `btn-ghost`
- **Erro de validação** abaixo do campo (`text-error text-sm`) + `input-error` no controle — mensagem genérica no topo não diz qual campo corrigir
- **Bean Validation manda**: o `required`/`maxlength` no HTML é conveniência de UX, a regra real está no servidor e a mensagem de erro volta dele

Ver [`references/formularios.md`](references/formularios.md) — campo padrão, grid, validação, upload, formulário em modal com HTMX.

## 6. Página de erro padrão — obrigatória

**Nenhuma app da Basis pode mostrar a Whitelabel Error Page.** É o default do Spring Boot quando não existe `error.html`: tela branca, stack trace ou "There was an unexpected error", sem identidade, sem caminho de volta e sem nada que o suporte possa usar.

- **`templates/error.html`** resolvido pelo `BasicErrorController` para qualquer status não tratado. Usa o mesmo layout (com `activeMenu` vazio) e mostra: logo Basis, badge com o status, título e mensagem amigáveis (via `#{}`), botão "voltar ao início" e, em bloco discreto `font-mono`, o **traceId** e o caminho
- **traceId visível é o ponto principal**: é o que o usuário informa ao suporte e o que liga a tela ao log do servidor. Vem do `Tracer` (Micrometer) no handler
- **Mensagem para o usuário, detalhe para o log**: nunca exibir stack trace nem mensagem crua de exceção. `server.error.include-stacktrace: never` e `include-message: never` fora de dev
- **Páginas específicas** para os casos frequentes (`error/entity-not-found.html`, 403) via `@ExceptionHandler` retornando `ModelAndView` com contexto útil — o que não foi encontrado e para onde voltar
- **Erro em requisição HTMX não pode cair na página inteira**: um listener de `htmx:responseError` no layout renderiza um `alert alert-error` em `#error-alert`. Fragmento que substitui um pedaço da tela por uma página de erro completa deixa a UI inconsistente
- **Erro de negócio esperado não é página de erro** — é mensagem no formulário/lista (ver §5)

Ver [`references/paginas-de-erro.md`](references/paginas-de-erro.md) — `error.html`, handler com traceId, chaves de mensagem, tratamento HTMX.

## 7. HTMX

- Fragmento Thymeleaf servido por Controller dedicado, retornando **só o pedaço** (`~{::fragmento}`), com `hx-target` apontando para o id do contêiner
- `hx-target="#modal-root"` para modal; o fragmento traz o `<dialog>`/`modal` inteiro
- Indicador de carregamento com `.htmx-indicator` (regras no `input.css`) em toda ação que chama o servidor
- Depois de qualquer manipulação de DOM feita por JS (List.js, por exemplo), chamar `htmx.process(elemento)`
- Com Spring Security, o token CSRF precisa acompanhar as requisições HTMX (meta tag + `hx-headers`, ou `hx-vals`) — POST de HTMX falhando com 403 é quase sempre isso

## 8. Estrutura de arquivos

```
src/main/resources/templates/
├── layout.html                  # fragmento layout(content, activeMenu)
├── error.html                   # página de erro genérica
├── error/entity-not-found.html  # erros específicos
└── <area>/
    ├── <pagina>.html            # página completa (usa o layout)
    └── <algo>-fragment.html     # fragmento HTMX (sem layout)
```

- Fragmento HTMX **não** usa o layout — devolve só o trecho
- Sufixo `-fragment` / `-modal` no nome deixa óbvio o que é página e o que é pedaço
- CSS/JS gerados vão para `target/classes/static/`, nunca para `src/` (ver [`references/frontend-build.md`](references/frontend-build.md))

## References disponíveis

- [`references/layout.md`](references/layout.md) — `layout.html` completo: sidebar, navbar, cadeia de altura, `@ControllerAdvice` de `appVersion`/`currentUser`, sidebar retrátil
- [`references/tabelas.md`](references/tabelas.md) — listagem com `thead`/`tfoot` fixos, List.js, ações por linha, paginação
- [`references/formularios.md`](references/formularios.md) — campo padrão, grid responsivo, erros de validação, upload, formulário em modal
- [`references/paginas-de-erro.md`](references/paginas-de-erro.md) — `error.html`, `@ExceptionHandler` com traceId, erros de HTMX, chaves i18n
- [`references/frontend-build.md`](references/frontend-build.md) — `input.css`, `package.json`, `frontend-maven-plugin`, `.gitignore`, watch mode
- [`references/assets/`](references/assets/) — logo Basis (completa e reduzida) para `static/images/`
