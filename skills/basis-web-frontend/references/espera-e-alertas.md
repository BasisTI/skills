# Espera e alertas — o que a tela mostra enquanto o servidor trabalha e depois que ele responde

Dois padrões do layout, um de cada lado da resposta: **a camada de espera** cobre toda
operação que demora (POST, GET pesado e download) e **os alertas de erro e de sucesso** fecham
sozinhos em 15 s, sempre com o botão X. Os dois vieram do colaboradados (Beneficios, tela
Folha, TG-297, 2026-10); os alertas, também do portal-liven (TG-226, 2026-10), com outro tema
e o mesmo comportamento.

## Espera em toda operação que demora

A camada `#espera-de-tela`, o fragmento do indicador e o script do POST estão em
[`tema-interno.md`](tema-interno.md#espera-de-tela-nas-ações-lentas). Aqui entram as outras
duas formas de esperar, com as mesmas guardas:

| Operação | Marcação | A camada sai quando |
|---|---|---|
| POST lento (IA, sincronização, envio externo) | `form[data-carregando="msg"]` | a página seguinte substitui esta |
| GET pesado: item de menu, Pesquisar, paginação, Voltar para uma lista pesada | `a[data-carregando="msg"]`, ou `form method="get"` com `data-carregando` (o mesmo script do POST, que não olha o método) | a página seguinte substitui esta |
| Download (Excel, arquivo de integração) | `a[data-baixar="msg"]` | chega o cookie do arquivo, ou uma página de erro navega; limite de 10 min |

**Marque só o que demora, medido.** Em troca de tela rápida a camada só pisca e atrasa a fila.
A mensagem é chave de `messages.properties`, como todo texto (`th:data-carregando="#{espera.folha.pesquisando}"`).

```html
<a th:href="@{/folha(mes=${mes}, pagina=${pagina + 1})}" class="btn btn-xs"
   th:data-carregando="#{espera.folha.pagina}" th:text="#{comum.paginacao.proxima}">Próxima</a>
<a th:href="@{/folha/exportar(mes=${mes})}" class="btn btn-sm"
   th:data-baixar="#{espera.folha.excel}" th:text="#{folha.botao.excel}">Exportar Excel</a>
```

### Por que o download precisa de cookie

Download não troca a página: o navegador recebe o arquivo e a página atual continua de pé. A
saída da camada não pode ser a descarga do documento, como no POST. O clique põe um token
aleatório na URL; o servidor devolve o arquivo com um cookie **cujo nome carrega o token**; a
página vê o cookie, apaga e libera. Resposta de erro é um documento (a `error.html`): a
navegação troca a página e a camada vai embora junto, sem cookie de erro.

**O token vai no nome do cookie, não no valor** (`download-concluido-<token>=1`). Com nome
fixo (`download-concluido=<token>`), duas abas que baixam ao mesmo tempo se atropelam: a
segunda resposta sobrescreve o cookie e a primeira aba fica com a camada até o limite de
10 min. A revisão da TG-297 reproduziu isso contra o controller real, em 2 de 3 tentativas. O
Beneficios ainda usa o nome fixo (correção na TG-299); não copie de lá.

### O script, no layout

Junta-se ao script do POST de [`tema-interno.md`](tema-interno.md#espera-de-tela-nas-ações-lentas)
e **substitui** o `liberarEspera` e o listener de `navigateerror` de lá:

```js
const liberarEspera = () => {
  clearInterval(window.esperaDeDownload);
  document.getElementById('espera-de-tela').hidden = true;
};
window.addEventListener('pageshow', liberarEspera);
// O download nunca "commita": a Navigation API o deixa pendente até a navegação seguinte e então
// dispara navigateerror por ele. Esse erro não é interrupção da navegação NOVA: engole uma vez.
// Parar e falha de rede da navegação nova disparam um segundo navigateerror, que libera.
let downloadPendente = false;
window.navigation?.addEventListener('navigateerror', () => {
  if (downloadPendente) { downloadPendente = false; return; }
  liberarEspera();
});

document.addEventListener('click', evento => {
  const link = evento.target.closest?.('a[data-carregando], a[data-baixar]');
  // Modificador ou botão do meio: a resposta vai para outra aba e esta nunca navega.
  if (!link || evento.defaultPrevented || evento.button !== 0
      || evento.ctrlKey || evento.metaKey || evento.shiftKey || evento.altKey) return;
  const alvo = (link.getAttribute('target') ?? '').trim().toLowerCase();
  if (alvo !== '' && alvo !== '_self') return;
  const espera = document.getElementById('espera-de-tela');
  if (!espera.hidden) { evento.preventDefault(); return; }   // 2º clique engolido
  const baixar = link.hasAttribute('data-baixar');
  const mostrar = () => {
    espera.querySelector('[data-mensagem]').textContent = baixar ? link.dataset.baixar : link.dataset.carregando;
    espera.hidden = false;
  };
  if (!baixar) { mostrar(); return; }

  evento.preventDefault();
  const token = (crypto.randomUUID?.() ?? Date.now() + '-' + Math.random().toString(36).slice(2))
      .replace(/[^A-Za-z0-9_-]/g, '');
  const url = new URL(link.href, location.href);
  url.searchParams.set('tokenDownload', token);
  location.assign(url);      // ANTES de mostrar a camada: ver armadilhas
  downloadPendente = true;
  mostrar();
  const cookie = 'download-concluido-' + token;
  const limite = Date.now() + 600000;
  window.esperaDeDownload = setInterval(() => {
    if (document.cookie.split('; ').some(c => c.startsWith(cookie + '=')) || Date.now() > limite) {
      document.cookie = cookie + '=; Max-Age=0; Path=/';
      liberarEspera();
    }
  }, 250);
});
```

### O servidor

```java
/** Avisa a página que o arquivo chegou (ver espera-e-alertas.md da basis-web-frontend). */
final class DownloadConcluido {

    static final String PARAM = "tokenDownload";
    static final String PREFIXO_COOKIE = "download-concluido-";
    private static final Pattern TOKEN_SEGURO = Pattern.compile("[A-Za-z0-9_-]{8,64}");

    private DownloadConcluido() {
    }

    static ResponseEntity.BodyBuilder marcar(ResponseEntity.BodyBuilder resposta, String token) {
        if (token == null || !TOKEN_SEGURO.matcher(token).matches()) {
            return resposta;     // arquivo sem cookie; a página segura a camada até o limite
        }
        ResponseCookie cookie = ResponseCookie.from(PREFIXO_COOKIE + token, "1")
                .path("/").maxAge(Duration.ofMinutes(2)).sameSite("Strict").httpOnly(false).build();
        return resposta.header(HttpHeaders.SET_COOKIE, cookie.toString());
    }
}
```

```java
@GetMapping("/exportar")
ResponseEntity<byte[]> exportar(@RequestParam String mes,
        @RequestParam(name = DownloadConcluido.PARAM, required = false) String token) {
    byte[] conteudo = servico.gerarExcel(YearMonth.parse(mes));
    return DownloadConcluido.marcar(ResponseEntity.ok(), token)
            .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=Folha.xlsx")
            .contentType(MediaType.APPLICATION_OCTET_STREAM)
            .body(conteudo);
}
```

- **Valide o token antes de ecoar.** Ele vai para um cabeçalho `Set-Cookie`; `;`, `=` ou quebra
  de linha ali injetariam atributo de cookie ou cabeçalho. Fora de `[A-Za-z0-9_-]{8,64}`, o
  arquivo sai sem cookie, igual.
- **`SameSite=Strict` e vida curta** (2 min): o cookie só precisa sobreviver até o próximo
  ciclo de 250 ms da página.
- **`Path` igual dos dois lados.** O JS apaga com `Path=/`; com a app sob context path, use o
  mesmo caminho no `ResponseCookie` e no `document.cookie`, senão o cookie não sai.
- **Sem `HttpOnly`, de propósito.** O Sonar marca `java:S3330` (cookie sem HttpOnly) como
  security hotspot, e hotspot não revisado reprova a condição *Security Hotspots Reviewed* do
  quality gate. Revise como **Safe**: o JS precisa ler o cookie, e nada nele é segredo. O token
  é gerado pela própria página, aleatório e sem valor de sessão, e nunca volta ao HTML (não há
  XSS refletido); quem forçar `tokenDownload` num link só faz a vítima receber um cookie inócuo.
- **O corpo do arquivo é idêntico com e sem token.** Vale um teste de controller que compare os
  dois: o token só acrescenta um cabeçalho.
- **`fetch` + blob é a alternativa** (a página baixa o arquivo, monta a URL do blob e sabe quando
  terminou, sem cookie). É válida no projeto que permite `fetch` nos templates. Projeto com teste
  de CSRF que proíbe `fetch`/XHR nos templates (no Beneficios, `CsrfTemplatesTest`) fica com o
  cookie.

### Armadilhas

- **Navegue antes de mostrar a camada, e engula uma vez o `navigateerror` do download.** O
  download fica pendente na Navigation API até a navegação seguinte, e o `navigateerror` dele
  dispara **de forma síncrona dentro do `location.assign`** dessa navegação. Com a camada já
  à mostra, o segundo download da página (ou o Pesquisar logo depois de um download) a esconde
  na hora. Daí a ordem `location.assign` → `downloadPendente = true` → `mostrar()`.
- **O Esc não libera a camada**, e a regra do POST vale aqui: ver
  [`tema-interno.md`](tema-interno.md#espera-de-tela-nas-ações-lentas).
- **Teste de navegador contra o servidor real.** O primeiro roteiro da TG-297 servia páginas
  pré-renderizadas e escrevia o cookie à mão: passou, e não exercitava o `DownloadConcluido`.
  Foi o roteiro da revisão, com o controller real num Tomcat local, que achou a colisão entre
  abas. Os casos que contam: Ctrl, Shift e botão do meio não armam; duplo clique mais um
  terceiro dão 1 pedido e 1 download; segundo download na mesma página e GET logo depois de
  download mantêm a camada; 500 no download leva à página de erro sem camada, e o Voltar devolve
  uma tela utilizável; duas abas baixando ao mesmo tempo liberam as duas; `window.stop()` libera.
  Nenhuma verificação termina em `|| true`: a da densidade lembrada terminava, e nunca falhava.
- **No Playwright, `page.click` espera a navegação e `page.evaluate` bloqueia enquanto há
  navegação pendente**, e o download deixa uma pendente. Observe a camada de dentro da página:
  um `MutationObserver` em `#espera-de-tela` que avisa o roteiro por `page.exposeBinding`.
- **Teste que lê o template** (o `layout.html` tem o seletor, o `PARAM` tem tal nome) é guarda
  contra remoção acidental, não prova de comportamento. O comportamento só se prova no navegador.

## Alertas que fecham sozinhos

**Todo alerta de erro e de sucesso tem o botão X e fecha sozinho 15 s depois de aparecer.**
Alerta que fica para sempre se acumula a cada ação e empurra a tela para baixo; alerta que
some rápido demais não dá tempo de ler. O mouse sobre o alerta, o foco do teclado nele ou texto
selecionado dentro dele seguram o fechamento, e ao sair a contagem recomeça dos 15 s: é o que
dá tempo de copiar um traceId.

O mecanismo é um só, por atributo: `data-alerta` no elemento. Vale para o alerta que o servidor
renderiza (flash de `sucesso`/`erro`), para o que o HTMX troca depois, para o que outro script
cria (o `htmx:responseError` de [`paginas-de-erro.md`](paginas-de-erro.md#erro-em-requisição-htmx))
e para resultado de upload ou anexo. Ninguém precisa avisar o script: um `MutationObserver`
olha a página inteira.

```html
<div th:if="${sucesso}" role="status" data-alerta class="alert alert-success">
  <span th:text="${sucesso}">Salvo.</span>
</div>
```

**Não leva `data-alerta`:**

- **aviso que explica o estado da tela** — folha de outro mês, cadastro bloqueado, nota
  informativa. Ele vale enquanto o estado vale; se sumir, a tela fica sem explicação;
- **destino reutilizável escondido por `hidden`** (um `[data-erro-envio]` que um script preenche
  e mostra a cada falha): o alerta se remove ao fechar, e a mensagem seguinte não tem para onde
  ir. Se o destino precisar fechar sozinho, marque-o também com `data-alerta-destino`: o script
  abaixo o esconde e esvazia em vez de remover.

### `static/js/alertas.js`

Carregado com `defer` no layout. O rótulo do botão vem do layout
(`<body th:data-rotulo-fechar="#{comum.acao.fechar}">`), porque texto em JS também é chave (§6).

```js
(() => {
  const PRAZO_EM_MS = 15000;
  const X = '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" '
      + 'stroke="currentColor" class="w-4 h-4" aria-hidden="true"><path d="M6 18 18 6M6 6l12 12"/></svg>';
  const estados = new WeakMap();   // fora do HTML: o que o HTMX restaura do histórico nasce sem estado
  let ultimaPosicao = null;
  for (const tipo of ['pointerdown', 'pointermove', 'pointerup']) {
    document.addEventListener(tipo, e => {
      if (e.pointerType === 'mouse') ultimaPosicao = { x: e.clientX, y: e.clientY };
    }, true);
  }

  const visivel = no => { for (let n = no; n?.nodeType === 1; n = n.parentNode) if (n.hidden) return false; return true; };
  const selecionado = a => { const s = window.getSelection?.(); return !!s && !s.isCollapsed && s.containsNode(a, true); };
  const parar = estado => { clearTimeout(estado.temporizador); estado.temporizador = null; };

  function encerrar(alerta) {
    const estado = estados.get(alerta);
    if (estado) parar(estado);
    if (alerta.hasAttribute('data-alerta-destino')) { alerta.hidden = true; alerta.replaceChildren(); }
    else alerta.remove();
  }
  function iniciar(estado, alerta) {
    parar(estado);
    estado.temporizador = setTimeout(() => {
      estado.temporizador = null;
      if (selecionado(alerta)) iniciar(estado, alerta); else encerrar(alerta);
    }, PRAZO_EM_MS);
  }
  const reavaliar = (estado, alerta) => (estado.mouse || estado.foco ? parar(estado) : iniciar(estado, alerta));

  function estadoDe(alerta) {
    let estado = estados.get(alerta);
    if (estado) return estado;
    estado = { temporizador: null, mouse: false, foco: false, origem: ultimaPosicao };
    estados.set(alerta, estado);
    alerta.addEventListener('pointermove', e => {
      if (e.pointerType !== 'mouse' || estado.mouse) return;
      if (estado.origem?.x === e.clientX && estado.origem?.y === e.clientY) return;   // ver armadilhas
      estado.mouse = true; reavaliar(estado, alerta);
    });
    alerta.addEventListener('pointerleave', e => {
      if (e.pointerType !== 'mouse') return;
      estado.mouse = false; estado.origem = null; reavaliar(estado, alerta);
    });
    alerta.addEventListener('focusin', () => { estado.foco = true; reavaliar(estado, alerta); });
    alerta.addEventListener('focusout', () => { estado.foco = false; reavaliar(estado, alerta); });
    return estado;
  }

  // Pode ser chamada quantas vezes for: quem decide é o estado do nó, não uma marca no HTML.
  function preparar(alerta) {
    const estado = estadoDe(alerta);
    if (!visivel(alerta)) { parar(estado); return; }
    const semBotao = !alerta.querySelector('[data-alerta-fechar]');
    if (semBotao) {   // sem botão = conteúdo novo (texto trocado): prazo inteiro
      const botao = document.createElement('button');
      botao.type = 'button';
      botao.className = 'alerta-fechar btn btn-ghost btn-xs btn-circle';
      botao.setAttribute('data-alerta-fechar', '');
      botao.setAttribute('aria-label', document.body.dataset.rotuloFechar);
      botao.innerHTML = X;
      alerta.appendChild(botao);
    }
    if (semBotao || (estado.temporizador === null && !estado.mouse && !estado.foco)) reavaliar(estado, alerta);
  }
  function varrer(no) {
    if (no?.nodeType !== 1) return;
    if (no.hasAttribute('data-alerta')) preparar(no);
    no.querySelectorAll('[data-alerta]').forEach(preparar);
  }

  document.addEventListener('click', e => {
    const alerta = e.target.closest?.('[data-alerta-fechar]')?.closest('[data-alerta]');
    if (alerta) encerrar(alerta);
  });
  new MutationObserver(mudancas => mudancas.forEach(m => {
    if (m.type === 'attributes') { varrer(m.target); return; }
    m.addedNodes.forEach(varrer);
    const dono = m.target.nodeType === 1 ? m.target.closest('[data-alerta]') : null;
    if (dono) preparar(dono);   // textContent trocado levou o botão: recoloca e recomeça
  })).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['hidden'] });
  document.addEventListener('htmx:historyRestore', () => varrer(document.documentElement));
  varrer(document.documentElement);
})();
```

```css
/* Fora de @layer: o padding precisa vencer o px-* que cada alerta já traz. O X fica no canto,
   fora da grade do .alert, e o texto reserva o espaço dele. */
[data-alerta] { position: relative; padding-inline-end: 2.5rem; }
.alerta-fechar { position: absolute; top: 0.25rem; inset-inline-end: 0.375rem; }
```

### Armadilhas

- **Mouse por eventos de ponteiro, não `mouseenter`/`mouseleave`.** O toque emite eventos de
  mouse de compatibilidade sem o `mouseleave` correspondente, e o alerta ficaria segurado para
  sempre no celular. Só `pointerType === 'mouse'` segura.
- **O `pointermove` falso.** O alerta costuma nascer no lugar do botão que a pessoa acabou de
  clicar, com o ponteiro parado ali, e o navegador entrega um `pointermove` nas mesmas
  coordenadas quando o layout muda debaixo dele. Contado como hover, o alerta não fechava nunca
  (portal-liven, segunda rodada da TG-226). Só conta o movimento que sai da posição de origem.
- **Quem cria alerta não traz botão próprio.** O `htmx:responseError` do layout e os fragmentos
  de flash põem `data-alerta` e deixam o X com o script. Nos dois projetos, o alerta de erro do
  HTMX e o aviso de sucesso tinham, cada um, botão e regra próprios; viraram um mecanismo só.
- **Contagem só com o alerta visível.** Alerta dentro de um ancestral `hidden` (aba fechada,
  destino esperando mensagem) não conta tempo; o observador de `hidden` retoma quando ele aparece.
