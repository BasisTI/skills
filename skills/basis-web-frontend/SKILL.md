---
name: basis-web-frontend
description: >-
  Use when building or changing the web UI of a Basis application — Thymeleaf + HTMX +
  Tailwind v4 + DaisyUI, listing tables with pinned header/footer where only the rows
  scroll, forms aligned with Tailwind utilities, and a custom error page so the user never
  hits the Whitelabel Error Page. Covers both visual identities and which one applies —
  the `caramellatte` theme with sidebar layout for internal authenticated systems, and the
  `basis-publico` theme following the institutional site (navy, orange accent, single
  centred column, measured WCAG contrast) for public login-free applications such as
  candidacy or citizen-facing forms. Activate for new screens, templates and fragments,
  table/listing work, form layout, error pages, theme/branding/colour choices, accessibility
  and contrast questions, or the Tailwind/DaisyUI build.
---

# Basis Web Frontend

Padrões da Basis para a UI de apps web. Pareada com `basis-spring-app` (aquela cobre a app Spring; esta cobre tudo que vive em `templates/` e no build de CSS/JS).

## 1. Stack e princípios

- **Thymeleaf** para renderização server-side; **HTMX** para interatividade; **Tailwind v4** + **DaisyUI 5** para estilo; **List.js** quando a tabela precisa de ordenação/filtro client-side
- **HTML é gerado no servidor.** Fragmento Thymeleaf trocado por HTMX é o default; JS solto só quando não há alternativa
- **Nada de framework SPA** nesta stack (Angular é a alternativa quando o caso pede, e aí é outra decisão de projeto — ver `basis-spring-app`)
- **Componente DaisyUI antes de utilitário Tailwind, utilitário antes de CSS próprio.** `<style>` no template é última instância e precisa de motivo
- **Sem texto hardcoded**: todo rótulo vem de `#{chave}` (`messages.properties`), inclusive o que vive em atributo e dentro de `<script>` — convenção de nome e armadilhas em §6
- **JS de terceiro é vendored**, servido do próprio app (ver [`references/frontend-build.md`](references/frontend-build.md)) — nunca CDN: app interno roda em rede fechada, e CDN adiciona dependência externa no caminho de renderização

## 2. Tema e identidade — a primeira decisão da tela

**Antes de escolher qualquer cor, decida se a app é interna ou pública.** As duas seguem
identidades diferentes, e usar a errada não é questão de gosto: um formulário público com a
cara de sistema interno parece outro site para quem acabou de clicar no link da Basis.

| | **Interna** — funcionário autenticado | **Pública** — sem login |
|---|---|---|
| Tema | `caramellatte` (DaisyUI) | `basis-publico` (site institucional) |
| Layout | sidebar à esquerda + header (§3) | coluna única centrada, sem sidebar |
| Destaque | o do tema | laranja `#F68B1F` sobre navy `#071A2E` |

Critério prático: se o host resolve de fora e não exige credencial, é público.
A paleta pública inteira, com os números de contraste medidos, está em
[`references/tema-publico.md`](references/tema-publico.md) — **leia antes de escrever a
primeira tela**, porque o laranja da marca reprova em contraste no uso mais óbvio dele.

- **App interna — tema DaisyUI `caramellatte`**, declarado em `data-theme` no `<html>` do layout e habilitado no `input.css`:
  ```css
  @plugin "daisyui" {
    themes: light --default, dark --prefersdark, caramellatte;
  }
  ```
- **App pública — tema `basis-publico`**, definido no próprio `input.css` com
  `@plugin "daisyui/theme"`. As restrições de acessibilidade da marca ficam **dentro do
  tema** (`--color-primary-content` é navy, não branco), para que `btn-primary` já nasça
  acessível sem ninguém precisar lembrar da regra
- **Usar as cores semânticas do tema** (`bg-base-100`, `bg-base-200`, `text-base-content`, `text-primary`, `badge-error`, `alert-warning`), nunca cor crua (`bg-white`, `text-gray-700`, `#cc6d13`) — cor crua quebra ao trocar de tema e destoa do resto do sistema
- **Hierarquia de superfície**: fundo da página `base-200`, cartões/sidebar/navbar `base-100`, bordas `border-base-300`. Texto secundário por opacidade (`text-base-content/60`), não por cor fixa
- **Logo Basis** em `src/main/resources/static/images/` (único diretório versionado dentro de `static/`): assinatura completa na página de erro/login, reduzida no topo da sidebar, e a **marca quadrada** (`marca-b-500.png`) onde o espaço é redondo ou pequeno — loader, favicon. Assinatura horizontal não cabe em caixa quadrada: encolhe até ficar ilegível. Cópias em [`references/assets/`](references/assets/)
- **Favicon + `theme-color`** configurados no `<head>`, alinhados ao tema em uso:
  `#cc6d13` no `caramellatte`, `#071A2E` no `basis-publico`
- Cor de marca que não existe no tema entra como token, não como valor espalhado:
  ```css
  @theme { --color-basis-blue: #0A2E5C; }   /* azul institucional */
  ```

## 3. Layout padrão: sidebar à esquerda + header

**Este é o esqueleto das apps internas.** App pública não leva sidebar — quem preenche um
formulário não navega entre cadastros; ver [`references/tema-publico.md`](references/tema-publico.md).
A cadeia de altura descrita no fim desta seção continua valendo nos dois casos.

Todo app interno usa o mesmo esqueleto — `templates/layout.html` com `th:fragment="layout(content, activeMenu)"`, e cada página faz `th:replace="~{layout :: layout(~{::section}, 'chave-do-menu')}"`.

**O que estiver fora do `<section>` da página não é renderizado, e nada avisa.** O layout
recebe `~{::section}` e insere só isso: qualquer irmão da `<section>` — tipicamente o
`<script>` que o hábito de HTML manda pôr no fim do arquivo — é descartado em silêncio, sem
erro, sem log e sem marca no HTML. `<script>` de página vai **dentro** da `<section>`, ou o
layout precisa de um segundo parâmetro de fragmento para recebê-lo. Já custou duas telas num
projeto nosso, com o gráfico e o relógio simplesmente não aparecendo.

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

    <div class="flex-grow overflow-y-auto min-h-0">   <!-- o ÚNICO filho que rola -->
      <table class="table table-zebra table-pin-rows w-full border-separate border-spacing-0">
        <thead>…</thead>   <!-- fixo no topo -->
        <tbody>…</tbody>   <!-- rola -->
        <tfoot>…</tfoot>   <!-- fixo embaixo: valor agregado alinhado às colunas -->
      </table>
    </div>

    <!-- barra de paginação: IRMÃ do que rola, nunca dentro dele -->
    <div class="shrink-0 border-t border-base-300 bg-base-100 p-3 flex items-center justify-between gap-3">
      …contagem…                          …botões Anterior/Próxima…
    </div>

  </div>
</div>
```

- **`table-pin-rows`** (DaisyUI) fixa as linhas de `<thead>` e `<tfoot>` dentro do contêiner rolável. Equivalente explícito, quando precisar de controle fino: `sticky top-0 z-10 bg-base-200` nas `th` e `sticky bottom-0 z-10 bg-base-200` nas `td` do `tfoot`
- **`border-separate border-spacing-0`** é obrigatório: com `border-collapse` (default do DaisyUI) a borda das células fixadas some ao rolar. A borda vai na célula (`border-b border-base-300`), não na linha
- **Fundo opaco** nas células fixadas (`bg-base-200`) — sem isso o conteúdo rola por baixo e aparece através
- **Quem rola é o `div` intermediário** (`overflow-y-auto min-h-0`), nunca a página. O `<table>` não recebe `overflow`
- **`<tfoot>` sempre presente quando há valor agregado** (total, soma, contagem de registros) — é a informação que o usuário mais procura e a que fica mais longe do olho numa lista longa
- **Barra de paginação não é `<tfoot>`.** `<tfoot>` é para número que pertence a uma coluna e se alinha com ela; barra de paginação é controle — texto de posição e botões, que não se alinham a coluna nenhuma. Espremê-la num `<td colspan>` mente sobre o que ela é, e ainda faz o botão herdar o estilo de célula. Ela vai como **`div` irmã da área rolável, com `shrink-0`**, e fica presa embaixo pelo mesmo motivo que o `<tfoot>`: não está dentro do que rola. As duas podem coexistir — `<tfoot>` com o total das colunas, barra embaixo com "Página 2 de 7"
- **Ordenação/filtro client-side** com List.js: `data-sort` nas `th`, `valueNames` no init, e `htmx.process(list.list)` no evento `updated` — sem isso os `hx-*` das linhas reordenadas param de funcionar
- **Volume grande é paginação server-side**, não `overflow` com 10 mil linhas no DOM. Sob paginação, `ORDER BY` precisa de **ordem total**: ordenar só por um campo que admite empate faz o banco não prometer ordem entre as linhas empatadas, e a mesma linha aparece em duas páginas ou em nenhuma. Desempate pela chave (`ORDER BY nome, id`)
- **Ação por linha** com ícone `btn-ghost btn-sm btn-square` na última coluna, alinhada à direita, com `th:title` explicando

Ver [`references/tabelas.md`](references/tabelas.md) — tabela completa com `tfoot` fixo, barra de paginação, List.js e variantes.

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

## 6. Textos e i18n

**Todo texto que o usuário lê é chave em `messages.properties`.** Não é preparação para um
dia traduzir — é o que permite trocar termo de negócio (de "Função" para "Cargo") sem caçar
string em template.

### Convenção de nome de chave

`<entidade>.<elemento>.<propriedade>`:

| Prefixo | Quando | Exemplo |
|---|---|---|
| `<entidade>.*` | rótulo que pertence a uma tela ou entidade | `funcao.campo.descricao`, `funcao.tabela.descricao` |
| `comum.*` | rótulo que repete **idêntico** entre entidades, confirmado no código e não suposto | `comum.acao.editar`, `comum.paginacao.registros` |
| `app.*` | rótulo sem entidade: menu, rodapé, banner global | `app.menu.funcionario`, `app.rodape.copyright` |

- **Cada elemento tem chave própria, mesmo com o texto igual hoje.** `funcao.campo.descricao`
  e `funcao.tabela.descricao` valem "Descrição" os dois; separadas, o label do formulário pode
  virar "Descrição do cargo" sem arrastar o cabeçalho da tabela junto.
- **Nunca o idioma no nome da chave** — `funcao.botao.criar.pt` não. É o que permite
  acrescentar `messages_en.properties` depois sem renomear nada.
- **Ficam fora do arquivo, de propósito**: nome do produto e marca ("Basis Ponto"), que não se
  traduzem; e mensagem vinda do Java (`${erro}`, `${sucesso}`, exceção de negócio), que é outra
  camada e não se resolve em template.

### Texto em atributo também é texto

`th:title`, `th:placeholder`, `th:alt`, `th:hx-confirm`. É onde mais escapa, porque a tela
fica visualmente correta com o texto ainda cravado no HTML.

```html
<button th:hx-confirm="#{funcao.excluir.confirmacao}"
        th:text="#{comum.acao.excluir}">Excluir</button>
```

### Dentro de `<script>`: `th:inline="javascript"` é obrigatório

O que muda com o atributo é o **modo**, não o fato de substituir. Sem ele o valor é injetado
assim mesmo — com escape de HTML e sem aspas, que é o pior dos dois mundos:

| No template | `<script>` | `<script th:inline="javascript">` |
|---|---|---|
| `var x = [[${v}]];` | `var x = a &quot;b&quot; &lt;c&gt;` — entidade HTML dentro do JS, e a linha nem fecha | `var x = "a \"b\" <c>";` — literal JS válido e escapado |
| `/*[[#{k}]]*/ 'padrão'` | `/*Excluir*/ 'padrão'` — **o código continua usando `'padrão'`** | `"Excluir"` — comentário e literal substituídos de uma vez |

A segunda linha é a que engana: a tela continua funcionando, em português, e o defeito só
apareceria no dia em que existisse `messages_en.properties` e nada fosse traduzido. Não
aparece em teste de navegador nem em revisão apressada — já passou pelas duas num projeto
nosso, em três templates de uma vez.

```html
<script th:inline="javascript">
    const msgSemPermissao = /*[[#{app.erro.semPermissao}]]*/ 'Você não tem permissão para esta ação.';
</script>
```

O literal depois do comentário é o fallback e documenta o texto esperado. Use `[( )]` no
lugar de `[[ ]]` quando o valor cai dentro de uma string (crase inclusive): `[[ ]]` devolve o
literal já entre aspas, e as aspas apareceriam na tela.

E lembre do §3: `<script>` fora do `<section>` não renderiza. `th:inline` correto num bloco
descartado não adianta nada.

### Configuração

```yaml
spring:
  messages:
    basename: messages
    encoding: UTF-8              # sem isto, acento vira caractere estranho na tela
    fallback-to-system-locale: false
```

`fallback-to-system-locale: false` é o que impede que, no dia em que existir
`messages_en.properties`, um pod com locale inglês passe a responder em inglês para todo
mundo — o locale do contêiner é o que o cluster deu, não uma decisão da aplicação.

### Mensagem com parâmetro passa por `MessageFormat`

`#{comum.paginacao.registros(${a}, ${b}, ${total})}` para `{0}–{1} de {2} registros`. Duas
consequências que só aparecem nas mensagens **com** parâmetro:

- **Número é formatado no locale**: `1234` sai `1.234`. Bom para contagem, errado para ano ou
  identificador — passe esses já como texto (`#calendars.format(..., 'yyyy')`).
- **Aspa simples é caractere de escape.** `'` solto some ou muda o sentido; para uma aspa
  literal, dobre (`''`). Mensagem sem parâmetro não passa por `MessageFormat` e não sofre isso.

Ver [`references/i18n.md`](references/i18n.md) — convenção completa, os quatro comportamentos
de inlining medidos e o checklist de revisão.

## 7. Página de erro padrão — obrigatória

**Nenhuma app da Basis pode mostrar a Whitelabel Error Page.** É o default do Spring Boot quando não existe `error.html`: tela branca, stack trace ou "There was an unexpected error", sem identidade, sem caminho de volta e sem nada que o suporte possa usar.

- **`templates/error.html`** resolvido pelo `BasicErrorController` para qualquer status não tratado. Usa o mesmo layout (com `activeMenu` vazio) e mostra: logo Basis, badge com o status, título e mensagem amigáveis (via `#{}`), botão "voltar ao início" e, em bloco discreto `font-mono`, o **traceId** e o caminho
- **traceId visível é o ponto principal**: é o que o usuário informa ao suporte e o que liga a tela ao log do servidor. Vem do `Tracer` (Micrometer) no handler
- **Mensagem para o usuário, detalhe para o log**: nunca exibir stack trace nem mensagem crua de exceção. `server.error.include-stacktrace: never` e `include-message: never` fora de dev
- **Páginas específicas** para os casos frequentes (`error/entity-not-found.html`, 403) via `@ExceptionHandler` retornando `ModelAndView` com contexto útil — o que não foi encontrado e para onde voltar
- **Erro em requisição HTMX não pode cair na página inteira**: um listener de `htmx:responseError` no layout renderiza um `alert alert-error` em `#error-alert`. Fragmento que substitui um pedaço da tela por uma página de erro completa deixa a UI inconsistente
- **Erro de negócio esperado não é página de erro** — é mensagem no formulário/lista (ver §5)

Ver [`references/paginas-de-erro.md`](references/paginas-de-erro.md) — `error.html`, handler com traceId, chaves de mensagem, tratamento HTMX.

## 8. HTMX

- Fragmento Thymeleaf servido por Controller dedicado, retornando **só o pedaço** (`~{::fragmento}`), com `hx-target` apontando para o id do contêiner
- `hx-target="#modal-root"` para modal; o fragmento traz o `<dialog>`/`modal` inteiro
- Indicador de carregamento com `.htmx-indicator` (regras no `input.css`) em toda ação que chama o servidor
- Depois de qualquer manipulação de DOM feita por JS (List.js, por exemplo), chamar `htmx.process(elemento)`
- Com Spring Security, o token CSRF precisa acompanhar as requisições HTMX (meta tag + `hx-headers`, ou `hx-vals`) — POST de HTMX falhando com 403 é quase sempre isso

## 9. Estrutura de arquivos

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
- [`references/i18n.md`](references/i18n.md) — convenção de nome de chave, texto em atributo, os quatro comportamentos de inlining em `<script>` medidos, `spring.messages`, `MessageFormat`, checklist
- [`references/paginas-de-erro.md`](references/paginas-de-erro.md) — `error.html`, `@ExceptionHandler` com traceId, erros de HTMX
- [`references/frontend-build.md`](references/frontend-build.md) — `input.css`, `package.json`, `frontend-maven-plugin`, `.gitignore`, watch mode
- [`references/tema-publico.md`](references/tema-publico.md) — identidade das apps públicas: tema DaisyUI `basis-publico`, paleta do site institucional, contrastes medidos, layout sem sidebar, indicador de espera
- [`references/assets/`](references/assets/) — logo Basis para `static/images/`: assinatura completa (`Logo-BASIS-300x130.png`), reduzida (`logo-header.png`) e marca quadrada (`marca-b-500.png`, usada no loader e no favicon)
