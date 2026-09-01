# Tema público — identidade do site institucional

O `caramellatte` é o tema dos **sistemas internos**. Aplicação que um cidadão ou candidato
acessa sem login não usa esse tema: ela é a continuação do site institucional de onde a
pessoa acabou de clicar, e trocar de identidade no meio do caminho parece outro site — ou
pior, parece phishing.

Paleta extraída do site institucional em **2026-08-19**.

## Quando aplicar

| Pergunta | Interno (`caramellatte`) | Público (`basis-publico`) |
|---|---|---|
| Quem acessa? | funcionário autenticado | qualquer pessoa, sem login |
| De onde vem? | do menu do sistema | de um link do site da Basis |
| Navega ou preenche? | navega entre cadastros | preenche uma coisa só |
| Layout | sidebar + header | coluna única centrada |

Na dúvida, decida pelo **endereço**: se o host resolve de fora e não exige credencial,
é público.

## Tokens da marca

```css
@theme {
  --color-basis-navy:        #071A2E;  /* fundo do cabeçalho e do hero */
  --color-basis-blue:        #0A2E5C;  /* azul institucional, superfícies secundárias */
  --color-basis-orange:      #F68B1F;  /* destaque: traço, preenchimento, foco */
  --color-basis-orange-dark: #B35A00;  /* o laranja que pode virar TEXTO sobre branco */
  --color-basis-ink:         #2B3944;  /* texto principal */
  --color-basis-ink-muted:   #616C74;  /* texto secundário */
}
```

Tipografia: **Inter Tight**, a do site, com `sans-serif` de fallback. Servida pelo próprio
app — fonte de CDN num formulário público é uma requisição a terceiro carregando o IP de
quem preenche, e é a primeira coisa que uma avaliação de LGPD pergunta.

## O tema DaisyUI

Declare o tema, não as cores. A regra do §2 da skill — semântica em vez de cor crua — vale
igual aqui; o que muda é o conteúdo do tema, não o hábito.

```css
@import "tailwindcss";
@plugin "daisyui";
@plugin "daisyui/theme" {
  name: "basis-publico";
  default: true;
  color-scheme: light;

  --color-base-100: #FFFFFF;   /* cartão do formulário */
  --color-base-200: #F7F9FA;   /* fundo da página — ver a derivação abaixo */
  --color-base-300: #8A96A3;   /* contorno de campo: 3,01:1 sobre branco */
  --color-base-content: #2B3944;

  --color-primary: #F68B1F;
  --color-primary-content: #071A2E;   /* navy sobre laranja, NÃO branco */

  --color-secondary: #0A2E5C;
  --color-secondary-content: #FFFFFF;

  --color-accent: #B35A00;
  --color-accent-content: #FFFFFF;

  --color-neutral: #071A2E;
  --color-neutral-content: #FFFFFF;

  --color-info:    #0A6E9E;  --color-info-content:    #FFFFFF;
  --color-success: #137547;  --color-success-content: #FFFFFF;
  --color-warning: #F68B1F;  --color-warning-content: #071A2E;
  --color-error:   #B3261E;  --color-error-content:   #FFFFFF;

  --radius-field: 0.25rem;
  --radius-box: 0.5rem;
  --border: 1px;
}
```

`--color-primary-content: #071A2E` é a peça central: com ela, `btn-primary` já nasce
acessível e ninguém precisa lembrar da regra ao escrever a tela. **Codifique a restrição no
tema, não no checklist** — checklist é revisado por humano cansado, tema é aplicado pelo
compilador.

`default: true` porque a app tem um tema só. Sem `prefersdark`: não existe variante escura
da identidade institucional, e inventar uma é decisão de marca, não de frontend.

## Contraste — medido, não estimado

| Combinação | Razão | AA (4,5:1) |
|---|---|---|
| `#F68B1F` sobre branco | **2,43:1** | ✗ reprova |
| Branco sobre `#F68B1F` | **2,43:1** | ✗ reprova |
| `#F68B1F` sobre `#071A2E` | **7,22:1** | ✓ AAA |
| `#071A2E` sobre `#F68B1F` | **7,22:1** | ✓ AAA |
| `#B35A00` sobre branco | **4,80:1** | ✓ passa |
| `#2B3944` sobre branco | **11,85:1** | ✓ AAA |
| `#616C74` sobre branco | **5,38:1** | ✓ passa |
| Branco sobre `#0A2E5C` | **13,48:1** | ✓ AAA |

Três consequências que não se deduzem olhando a tabela de longe.

**1. O botão do site reprova, e a divergência é deliberada.** O site institucional usa
laranja com texto branco: 2,43:1, contra os 4,5:1 exigidos. Num site de marketing é um
detalhe; num formulário público de 51 campos, onde "Continuar" é a ação mais repetida da
tela, é barreira real. Por isso `primary-content` é navy. Se marketing exigir fidelidade
exata, isso vira decisão consciente de aceitar a reprovação — não um detalhe que passou
batido.

**2. `#B35A00` só passa sobre branco, e por pouco.** São 4,80:1 — margem de 0,3. Sobre um
fundo de página cinza-claro comum (`#F1F5F9`) cai para **4,38:1 e reprova**. Daí
`--color-base-200: #F7F9FA`: é o fundo mais escuro em que o laranja-texto ainda passa
(4,54:1). Escurecer o fundo da página "só um tom" quebra o texto laranja em outro lugar da
tela, e nada avisa.

**3. Laranja puro nunca é texto.** Fica para traço do cabeçalho, preenchimento de botão,
anel de foco, ícone e barra de progresso — onde vale o limite de 3:1 de elemento não
textual, não o de 4,5:1 de texto.

Contorno de campo também é elemento não textual e precisa de **3:1** contra o fundo
(WCAG 1.4.11). O cinza-clarinho habitual de borda (`#E2E8EC`, 1,24:1) reprova — daí
`base-300` em `#8A96A3`. Num formulário longo é o que separa "campo" de "espaço em branco".

## Layout de página pública

**Sem sidebar.** Quem preenche não navega. A tela é uma coluna centrada com o formulário em
cartão branco sobre `base-200`.

```
┌────────────────────────────────────────────────────────┐
│  ███ fundo navy · logo Basis · título                  │  ← cabeçalho
│════════════════════════════════════════════════════════│  ← traço laranja, 3px
│                                                        │
│   [1]━━━[2]━━━[3]───[4]───[5]───[6]                    │  ← passo ativo laranja,
│                                                        │     concluído navy
│   ┌──────────────────────────────────────────────┐     │
│   │  cartão base-100, borda sutil, sombra leve    │     │
│   │              [ ← Voltar ]  [ Continuar → ]    │     │  ← btn-primary
│   └──────────────────────────────────────────────┘     │
│   rascunho salvo há 2 min                              │
└────────────────────────────────────────────────────────┘
```

- O traço laranja de 3px sob o cabeçalho é a assinatura visual do site — é ele que faz a
  página ser reconhecida como Basis mesmo sem o logo aparecer na dobra
- **Mobile primeiro**: um campo por linha abaixo de `sm`, dois acima. O stepper vira
  "3 de 6" com barra, não seis bolinhas espremidas
- Passo concluído é **link de verdade**; passo futuro não é. Stepper decorativo engana quem
  navega por teclado
- `templates/error.html` na mesma identidade, obrigatório — endereço público não pode cair
  na Whitelabel Error Page (ver [`paginas-de-erro.md`](paginas-de-erro.md))

## Indicador de espera

Reaproveita o loader do site institucional. Estrutura medida no site em 2026-08-19: um
`div` de **100×100 px** com borda de **3 px `#F68B1F`** e `border-radius: 50%`, e dentro
dele **uma imagem de 80 px de largura** — o "b" da marca.

```html
<div class="basis-loader" role="status">
  <div class="basis-loader__anel"></div>
  <img th:src="@{/images/marca-b.png}" alt="" width="80" height="80">
  <span th:text="#{app.espera.enviando}">Enviando sua candidatura…</span>
</div>
```

**Sim, precisa de asset.** O miolo do loader é imagem, não CSS, e é a **marca quadrada** —
não serve nenhum dos dois logos que a skill já traz: `Logo-BASIS-300x130.png` e
`logo-header.png` são a assinatura horizontal (`basis` por extenso com o slogan), e deitar
uma assinatura de 300×130 numa caixa redonda de 80 px distorce ou fica ilegível.

Use [`assets/marca-b-500.png`](assets/marca-b-500.png) — 500×500, o mesmo arquivo que o site
serve —, copiado para `static/images/`. Serve também de base para o favicon.

Duas coisas que a inspeção mostrou e que mudam o que copiar:

- **A borda do site é laranja nos quatro lados** e o elemento estava com
  `animation-name: none` no momento da captura. Ou seja: o anel completo girando seria
  invisível de qualquer forma, e a rotação abaixo é **prescrição nossa, não cópia**. Deixe um
  trecho transparente (`border-top-color: transparent`), senão o anel gira parecendo parado
- **A marca é a variante preta** (`favicon-preto` na origem). Funciona no miolo branco do
  loader; **não** use a mesma sobre o cabeçalho navy, onde ela some

```css
.basis-loader__anel {
  width: 100px; height: 100px;
  border: 3px solid #F68B1F;
  border-top-color: transparent;      /* o trecho que torna o giro visível */
  border-radius: 50%;
  animation: spin 1s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

@media (prefers-reduced-motion: reduce) {
  .basis-loader__anel { animation: none; }
}
```

- Um componente só (`fragments/carregando.html`), não uma variação por tela
- **A marca fica parada no centro; quem gira é o anel.** Logo girando junto embaralha a
  leitura da marca
- `alt=""` na imagem: ela é decorativa, quem anuncia é o `role="status"` com o texto ao lado.
  `alt="Basis"` faz o leitor de tela dizer "Basis" a cada espera, sem informar nada
- **`prefers-reduced-motion` desliga o giro** e mantém o anel estático com o texto. Movimento
  perpétuo causa mal-estar em quem tem sensibilidade vestibular, e a informação está no texto

## Checklist

- [ ] `data-theme="basis-publico"` no `<html>`, tema declarado no `input.css`
- [ ] Nenhuma cor crua no template — só classe semântica do tema
- [ ] Nenhum texto laranja fora de `#B35A00`, e só sobre `base-100`/`base-200`
- [ ] `btn-primary` com texto navy (vem do tema; confira se alguém sobrescreveu)
- [ ] Contorno de campo visível: `base-300` ≥ 3:1 contra o fundo do cartão
- [ ] Foco visível em todo controle, com anel de 3:1 contra o vizinho
- [ ] Fonte, CSS, JS e imagens servidos pelo app — zero requisição a terceiro
- [ ] `error.html` na identidade pública
- [ ] `marca-b.png` copiada para `static/images/`; loader com anel + marca parada
- [ ] `prefers-reduced-motion` respeitado no loader
- [ ] Zoom 200% sem rolagem horizontal
