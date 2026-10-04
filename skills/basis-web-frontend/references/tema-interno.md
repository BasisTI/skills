# Tema interno — a identidade da Basis nos sistemas autenticados

Os sistemas internos seguem a mesma identidade do site institucional que as apps públicas
(navy, laranja, Carlito e Inter Tight), num tema próprio, `basis-interno`. Ele substitui o
`caramellatte` do DaisyUI: o tema embutido é genérico, pálido, e deixa o sistema sem cara de
Basis.

A diferença para o [`basis-publico`](tema-publico.md) é o uso, não a marca. Formulário
público tem uma ação repetida ("Continuar"), e ela pode ser laranja. Sistema interno é fila e
cadastro, com um "Ver detalhes" ou "Revisar" **por linha**; uma coluna de botões laranja
grita mais que os dados. Por isso, aqui:

- a **ação primária é navy**;
- o **laranja é marca**: item ativo do menu, anel de foco e indicador de espera;
- a **moldura carrega a cor** (menu lateral navy) e o conteúdo fica claro e frio, porque a
  tabela é lida o dia inteiro.

Primeiro sistema a usar: o Triagem.AI (TG-36, 2026-10). Lá o tema se chama `basis-triagem`;
o conteúdo é o deste arquivo.

## O tema DaisyUI

```css
/* `source(none)`: o Tailwind varre só o que o `@source` aponta, e não docs/, .agents/ e o resto
   do módulo -- classe citada num Markdown (`text-base-content/60` num plano ou numa skill) entraria
   no CSS. Caminho e motivo em frontend-build.md. */
@import "tailwindcss" source(none);
/* `themes: false` tira do bundle os temas embutidos (light, dark...) que ninguém usa. */
@plugin "daisyui" { themes: false; }

@source "../main/resources/templates/**/*.html";   /* relativo a este arquivo: confira */

@plugin "daisyui/theme" {
  name: "basis-interno";
  default: true;
  color-scheme: light;

  --color-base-100: #FFFFFF;   /* cartão, cabeçalho */
  --color-base-200: #EDF1F5;   /* fundo da página: cinza-frio, não creme */
  --color-base-300: #D3DAE2;   /* bordas e divisórias */
  --color-base-content: #1B2A38;

  --color-primary: #0A2E5C;    /* ação primária navy */
  --color-primary-content: #FFFFFF;
  --color-secondary: #071A2E;  /* títulos */
  --color-secondary-content: #FFFFFF;
  --color-accent: #F68B1F;     /* laranja da marca: preenchimento, nunca texto */
  --color-accent-content: #071A2E;
  --color-neutral: #071A2E;
  --color-neutral-content: #FFFFFF;

  --color-info:    #0A6E9E;  --color-info-content:    #FFFFFF;
  --color-success: #137547;  --color-success-content: #FFFFFF;
  --color-warning: #8F5A00;  --color-warning-content: #FFFFFF;   /* âmbar-escuro, ver abaixo */
  --color-error:   #B3261E;  --color-error-content:   #FFFFFF;

  --radius-selector: 0.25rem;
  --radius-field: 0.375rem;
  --radius-box: 0.5rem;
  --border: 1px;
  --depth: 0;
  --noise: 0;
}

/* Marca, não papel semântico. `basis-laranja-texto` é o laranja que passa em 3:1 sobre branco. */
@theme {
  --color-basis-navy: #071A2E;
  --color-basis-laranja: #F68B1F;
  --color-basis-laranja-texto: #B35A00;
  --font-sans: "Carlito", Calibri, ui-sans-serif, system-ui, sans-serif;
  --font-display: "Inter Tight", ui-sans-serif, system-ui, sans-serif;
}
```

`data-theme="basis-interno"` no `<html>` do layout, e `<meta name="theme-color"
content="#071a2e">`, o navy do menu, que pinta a barra do navegador no celular.

**`--color-warning` é âmbar-escuro (`#8F5A00`), e não amarelo nem laranja.** `text-warning`
aparece como texto corrido sobre branco, e o amarelo dos temas embutidos dá menos de 2:1 ali.
E não é o laranja da marca, para que "atenção" nunca se confunda com "Basis".

## Base: tipografia e superfícies do navegador

```css
@layer base {
  /* Carlito tem olho pequeno: a 14px ele lê como 13px de uma sans comum. */
  html { font-size: 106.25%; }
  h1, h2, h3 { font-family: var(--font-display); letter-spacing: -0.01em; color: var(--color-secondary); }
  td, th, .badge { font-variant-numeric: tabular-nums; }   /* score, data e contagem em coluna */
  .badge { white-space: nowrap; }   /* "Em revisão" quebrando dentro da pílula corta a 2ª palavra */
  ::selection { background: color-mix(in oklab, var(--color-basis-laranja) 35%, transparent); color: var(--color-basis-navy); }
  :focus-visible { outline: 2px solid var(--color-basis-laranja-texto); outline-offset: 2px; }
  a { text-underline-offset: 0.2em; }
  * { scrollbar-color: color-mix(in oklab, var(--color-base-content) 25%, transparent) transparent; }
}
```

O anel de foco é `#B35A00` e não `#F68B1F`: o laranja puro dá 2,4:1 sobre branco e reprova o
3:1 de elemento não textual (WCAG 1.4.11). Foco que só quem enxerga bem distingue não é foco
visível.

## Fontes servidas pelo app

Carlito (a Calibri livre, mesmas métricas dos documentos da Basis) no corpo e Inter Tight nos
títulos, como no site. Vêm do `@fontsource` e o build copia os `.woff2`, sem CDN:

```json
"devDependencies": { "@fontsource/carlito": "5.2.5", "@fontsource/inter-tight": "5.2.6" },
"scripts": {
  "build": "mkdir -p target/classes/static/css target/classes/static/js target/classes/static/fonts && tailwindcss -i src/frontend/input.css -o target/classes/static/css/style.css && cp node_modules/htmx.org/dist/htmx.min.js target/classes/static/js/ && cp node_modules/@fontsource/carlito/files/carlito-latin-400-normal.woff2 node_modules/@fontsource/carlito/files/carlito-latin-700-normal.woff2 node_modules/@fontsource/inter-tight/files/inter-tight-latin-600-normal.woff2 node_modules/@fontsource/inter-tight/files/inter-tight-latin-700-normal.woff2 target/classes/static/fonts/"
}
```

```css
@font-face { font-family: "Carlito"; font-weight: 400; font-display: swap;
  src: url("../fonts/carlito-latin-400-normal.woff2") format("woff2"); }
@font-face { font-family: "Carlito"; font-weight: 700; font-display: swap;
  src: url("../fonts/carlito-latin-700-normal.woff2") format("woff2"); }
@font-face { font-family: "Inter Tight"; font-weight: 600; font-display: swap;
  src: url("../fonts/inter-tight-latin-600-normal.woff2") format("woff2"); }
@font-face { font-family: "Inter Tight"; font-weight: 700; font-display: swap;
  src: url("../fonts/inter-tight-latin-700-normal.woff2") format("woff2"); }
```

**`/fonts/**` entra no `permitAll` do `SecurityFilterChain`, junto com `/css/**`.** As fontes
são pedidas pelo CSS; se caírem na regra geral (`anyRequest().hasAnyRole(...)`), o usuário que
tem um papel fora dessa lista (no Triagem, o de entrevistador) recebe 403 nelas e vê a tela na
fonte de sistema, sem erro nenhum.

## Contraste — medido, não estimado

| Combinação (fundo branco / cinza-frio `#EDF1F5`) | Razão | AA (4,5:1) |
|---|---|---|
| `base-content` `#1B2A38` | 14:1 / 12,6:1 | ✓ |
| `text-base-content/70` | **5,60:1 / 5,27:1** | ✓ |
| `text-base-content/60` | **4,06:1 / 3,88:1** | ✗ reprova |
| aba inativa do DaisyUI (50%) | 2,96:1 no cinza-frio | ✗ reprova |
| `text-warning` `#8F5A00` | 5,78:1 / 5,10:1 | ✓ |
| branco sobre `primary` `#0A2E5C` | 13,48:1 | ✓ AAA |
| título de grupo do menu (branco a 55% sobre navy) | ~5,9:1 | ✓ |

**O mínimo para texto esmaecido é 70%, não 60%.** `text-base-content/60` passava no fundo creme
do `caramellatte` e reprova nos dois fundos deste tema. Legenda, subtítulo e texto auxiliar
usam `text-base-content/70`.

### O DaisyUI esmaece texto por conta própria

Vários componentes do DaisyUI pintam o texto abaixo de 70% sem ninguém pedir, e cada um
reprovou numa rodada diferente da revisão do Triagem:

| Regra do DaisyUI | Esmaecimento |
|---|---|
| `.label` | 60% |
| `.table` `thead` e `tfoot` | 60% |
| `.stat-title`, `.stat-desc` | 60% |
| `.tab` inativa | 50% |
| `.menu-title` | 40% |

Estado desabilitado e placeholder ficam abaixo de 70% de propósito, e estão certos: a WCAG
isenta componente inativo.

A sobrescrita repete o seletor da regra do DaisyUI e vai em `@layer utilities`, que é onde ele
mora. Em `components` ela perde, porque `utilities` vem depois na cascata. O seletor acompanha a
versão do DaisyUI: a 5.5.19 acrescentou `[aria-current="true"], [aria-current="page"]` ao
`:not(...)` da aba, e o teste abaixo é quem avisa quando ele muda de novo (colaboradados, TG-193).

```css
@layer utilities {
  .label { color: color-mix(in oklab, currentColor 70%, transparent); }
  .tab:not(:checked, label:has(:checked), :hover, .tab-active, [aria-selected="true"], [aria-current="true"], [aria-current="page"]) {
    color: color-mix(in oklab, var(--color-base-content) 70%, transparent);
  }
  .table :where(thead, tfoot) { color: color-mix(in oklab, var(--color-base-content) 70%, transparent); }
  .stat-title { color: color-mix(in oklab, var(--color-base-content) 70%, transparent); }
  .stat-desc { color: color-mix(in oklab, var(--color-base-content) 70%, transparent); }
  .menu-title { color: color-mix(in oklab, var(--color-base-content) 70%, transparent); }
}
```

**Esmaecer por cor, nunca por `opacity`.** `opacity-70` num texto que já herda os 70% de um
`.label` multiplica as duas: a skill ignorada dentro do rótulo caiu para 2,99:1. Cor explícita
(`text-base-content/70`) substitui a herdada em vez de somar a ela. Texto "apagado" (item
encerrado, skill ignorada, detalhe técnico) é `text-base-content/70`, com `line-through` quando
for o caso.

### O teste que impede a regressão

Uma atualização do DaisyUI pode trazer outra regra assim, e nada avisa. Um teste lê o CSS que
o build gera e falha se algum texto ativo ficar esmaecido abaixo de 70% sem sobrescrita
posterior com o mesmo seletor. Ele roda no classpath de teste porque o `npm run build` acontece
no `generate-resources`.

O código completo está em [`ContrasteDoTemaTest.java`](ContrasteDoTemaTest.java) (o mesmo do
Triagem): ajuste o pacote e copie para `src/test/java`. Quatro decisões dele que não se deduzem
lendo:

- **A chave é seletor + condição de `@media`/`@container`.** Uma sobrescrita que só vale numa
  largura não cobre as outras. `@layer` e `@supports` ficam de fora da chave: o DaisyUI embrulha
  o `color-mix` num `@supports`, e a sobrescrita do tema também.
- **`:not(...)` é removido antes de decidir se o estado é desabilitado.** `:not(:disabled)` é
  justamente o estado ativo.
- **O seletor aninhado é normalizado** (`.tab { &:not(...) }` → `.tab:not(...)`) para se
  comparar com a regra plana do tema, inclusive o espaço junto ao parêntese: o Tailwind imprime
  `:not( :checked, ... )` nas regras do DaisyUI e `:not(:checked, ...)` na do tema.
- **O teste só confronta o componente que o build gera.** O Tailwind trata como candidato a
  classe qualquer palavra dos arquivos varridos, **comentários inclusive**: no colaboradados, um
  comentário com "the new tab" no `layout.html` fez o DaisyUI passar a gerar `.tab`, e só então o
  teste teve a regra de 50% para comparar. App que não usa um componente não testa a sobrescrita
  dele; quando passar a usar, o teste passa a cobrir sozinho.
- **O teste se testa**: casos com CSS sintético (regra nova reprova; `:not(:disabled)` reprova;
  sobrescrita só num `@media` reprova; mesmo seletor depois aprova; desabilitado fica de fora).

Limites conhecidos, nenhum presente no CSS do DaisyUI hoje: `:not(:is(:disabled))`,
sobrescrita dentro de um `@supports` que não se aplica, e sobrescrita numa camada que perde
para a da regra original.

## Botão sem variante

O `.btn` sem variante do DaisyUI é pintado de `base-200`, que neste tema é o mesmo cinza do
fundo e da linha zebrada. O botão some em metade das linhas da tabela, e o grupo de ordenação
vira texto solto. Branco com contorno o desenha sobre qualquer fundo:

```css
@layer utilities {
  .btn:where(:not(.btn-primary, .btn-secondary, .btn-accent, .btn-neutral, .btn-info, .btn-success,
      .btn-warning, .btn-error, .btn-ghost, .btn-link, .btn-outline, .btn-soft, .btn-dash, .btn-active)) {
    --btn-color: var(--color-base-100);
    --btn-border: var(--color-base-300);
  }
}
```

Só no botão sem variante: `--btn-color` é exatamente a variável que as variantes definem, e
mexer nela no `.btn` todo trocaria a cor do `btn-primary`.

## Menu lateral navy

O esqueleto é o do §3 da skill ([`layout.md`](layout.md)); muda o vestido:

```html
<aside id="main-sidebar" class="flex w-64 shrink-0 flex-col overflow-hidden bg-basis-navy text-white">
  <div class="shrink-0 px-6 pt-6 pb-5">
    <img class="h-12 w-auto" th:src="@{/images/logo-basis-branco.png}" alt="Basis Tecnologia">
    <p class="mt-3 font-display text-sm font-semibold tracking-wide text-white/70"
       th:text="#{app.marca.subtitulo}">Subtítulo</p>
  </div>
  <ul class="menu menu-lateral w-full min-h-0 flex-1 overflow-y-auto px-4">
    <li><a th:href="@{/x}" th:aria-current="${activeMenu == 'x'} ? 'page'" th:text="#{app.menu.x}">X</a></li>
    <li class="menu-title mt-3" th:text="#{app.grupo.cadastros}">Cadastros</li>
  </ul>
</aside>
```

```css
/* Fora de @layer de propósito: o .menu do DaisyUI mora em `utilities`, e só regra sem camada
   ganha dele sem !important. */
.menu-lateral { --menu-active-bg: transparent; }
.menu-lateral a { color: color-mix(in oklab, white 72%, transparent); position: relative; }
.menu-lateral a:hover { color: white; background: color-mix(in oklab, white 8%, transparent); }
.menu-lateral a[aria-current="page"] { color: white; font-weight: 700; background: color-mix(in oklab, white 6%, transparent); }
.menu-lateral a[aria-current="page"]::before {
  content: ""; position: absolute; left: -0.5rem; top: 50%; translate: 0 -50%;
  width: 0.375rem; height: 1rem; border-radius: 9999px;
  background: linear-gradient(to bottom, #F26B22, #FBB117);   /* a cápsula do logo */
}
.menu-lateral li.menu-title { color: color-mix(in oklab, white 55%, transparent); }
.menu-lateral :focus-visible { outline-color: var(--color-basis-laranja); }
```

- **O item ativo é marcado pela cápsula laranja do logo**, em miniatura à esquerda do rótulo.
  Fundo forte no item, num menu escuro, lê como botão pressionado.
- **O estado vem de `aria-current="page"`, e não de classe.** É o que o leitor de tela anuncia,
  e o CSS desenha a partir dele, então os dois nunca divergem. Com `th:aria-current` e valor
  nulo, o Thymeleaf omite o atributo. A classe `active` do DaisyUI 4 não pinta nada no
  DaisyUI 5 (lá é `menu-active`): no Triagem, nenhum item aparecia ativo antes do tema.
- **Logo branco**: [`assets/logo-basis-branco.png`](assets/logo-basis-branco.png) (letras
  brancas, cápsula laranja, fundo transparente). O `logo-header.png` é preto e some no navy.
- **Avatar do usuário** em `bg-white/15 text-white`. Laranja ali seria a cor mais forte da tela
  depois do logo, e o laranja é reservado à marca, ao foco e à espera.

## Espera de tela nas ações lentas

O indicador é o mesmo do site e da app pública, um fragmento só (`fragmentos/carregando.html`,
ver [`tema-publico.md`](tema-publico.md#indicador-de-espera)) em duas medidas: 96 px na espera
de tela e 40 px ao lado de um botão. Ação de IA, sincronização e envio a sistema externo são
POST comum, não HTMX. Para eles, o layout tem uma camada que cobre **só a coluna do conteúdo**
(o menu continua legível) e um formulário entra nela declarando a mensagem:

```html
<form method="post" th:action="@{/x/gerar}" th:data-carregando="#{espera.gerando}">
```

```html
<!-- no layout, dentro do contêiner do conteúdo, que é `relative` -->
<div id="espera-de-tela" class="espera-de-tela" hidden>
  <div th:replace="~{fragmentos/carregando :: carregando(#{espera.padrao}, false)}"></div>
</div>
```

```css
.espera-de-tela { position: absolute; inset: 0; z-index: 30; display: grid; place-items: center;
  background: color-mix(in oklab, var(--color-base-200) 82%, transparent); backdrop-filter: blur(2px); }
.espera-de-tela[hidden] { display: none; }
```

O script é curto, mas cada linha veio de um defeito que uma revisão adversarial achou:

```js
// Envio para OUTRA aba (Ctrl/Cmd/Shift + clique ou Enter, botão do meio): a resposta chega
// na aba nova e esta aba, que nunca navega, ficaria com a camada para sempre. O submit não
// traz as teclas; elas vêm do clique ou da tecla que o disparou, lidos em captura.
let enviaEmOutraAba = false;
const lembrarTeclas = e => { enviaEmOutraAba = e.ctrlKey || e.metaKey || e.shiftKey || e.button === 1; };
document.addEventListener('click', lembrarTeclas, true);
document.addEventListener('auxclick', lembrarTeclas, true);
document.addEventListener('keydown', lembrarTeclas, true);

document.addEventListener('submit', evento => {
  const formulario = evento.target;
  if (evento.defaultPrevented || !formulario.matches('form[data-carregando]')) return;
  const espera = document.getElementById('espera-de-tela');
  // Já enviado e esperando: a camada cobre os cliques, mas Enter no botão com foco reenviaria.
  if (!espera.hidden) { evento.preventDefault(); return; }
  const alvo = (evento.submitter?.getAttribute('formtarget') ?? formulario.getAttribute('target') ?? '')
      .trim().toLowerCase();
  if (enviaEmOutraAba || (alvo !== '' && alvo !== '_self')) return;
  espera.querySelector('[data-mensagem]').textContent = formulario.dataset.carregando;
  espera.hidden = false;
});

// A camada sai quando esta página continua de pé: Voltar (cache) e navegação interrompida
// (botão parar, Esc do navegador, falha de rede).
const liberarEspera = () => { document.getElementById('espera-de-tela').hidden = true; };
window.addEventListener('pageshow', liberarEspera);
window.navigation?.addEventListener('navigateerror', liberarEspera);
```

- **`evento.defaultPrevented` primeiro.** Validação HTML inválida e `onsubmit` que devolve
  `false` (um `confirm()` cancelado) não podem deixar a camada aberta.
- **O Esc não libera a camada por conta própria.** Parece a saída óbvia, e foi a regressão: o
  Chromium nem sempre interrompe a navegação com o Esc, a camada saía com o POST ainda em curso
  e o próximo clique gerava um segundo POST, depois um terceiro. Quando o navegador interrompe
  de fato, o `navigateerror` avisa.
- **Navegador sem Navigation API** fica sem a liberação por interrupção: a camada some ao
  recarregar ou voltar. Os navegadores atuais têm a API.
- **`alt=""` na marca do loader** é decorativo e correto. Teste que proíbe texto cravado em
  `alt`/`title`/`aria-label` precisa aceitar o valor vazio, senão reprova justamente o caso
  certo.
- **Não use a camada na navegação comum.** Ela existe para a ação que demora; em troca de tela
  ela só atrasa a fila.

## Checklist

- [ ] `data-theme="basis-interno"` no `<html>`; `themes: false` no `@plugin "daisyui"`; tema em `@plugin "daisyui/theme"`
- [ ] `theme-color` `#071a2e`
- [ ] Fontes copiadas no build, `@font-face` no `input.css`, `/fonts/**` no `permitAll`
- [ ] Nenhum `text-base-content/60` (ou menos) em texto ativo; esmaecido por cor, nunca por `opacity`
- [ ] Sobrescritas do DaisyUI em `@layer utilities` e teste de contraste no CSS gerado
- [ ] Botão sem variante visível sobre `base-200` e sobre a linha zebrada
- [ ] Menu navy com logo branco; item ativo por `aria-current="page"`
- [ ] Laranja só em marca, foco e espera, nunca como texto (texto laranja é `#B35A00`)
- [ ] Ações lentas com `data-carregando`; Ctrl+clique, Enter duplo, Voltar e parar testados
- [ ] `prefers-reduced-motion` desliga o giro do loader
