# Tabelas e listagens

Regra da casa: **cabeçalho e rodapé fixos, sempre visíveis; só as linhas de conteúdo rolam.**

Motivo: a listagem é a primeira tela de praticamente todo cadastro. Tabela cujo `thead` some ao rolar obriga o usuário a voltar ao topo para lembrar qual coluna é qual; total que fica no fim de 500 linhas é o número que ninguém encontra.

## Estrutura completa

```html
<section class="flex flex-col gap-6 h-full min-h-0 overflow-hidden">

    <!-- Cabeçalho da página: não rola -->
    <div class="shrink-0 flex items-center justify-between">
        <div>
            <h1 class="text-3xl font-black" th:text="#{alloc.title}">Alocacoes</h1>
            <p class="text-base-content/60" th:text="#{alloc.subtitle}">Descricao curta da tela.</p>
        </div>
        <div class="flex items-center gap-2">
            <input type="search" class="input input-bordered input-sm search"
                   th:placeholder="#{table.search}" />
            <a th:href="@{/configs/allocations/new}" class="btn btn-primary btn-sm"
               th:text="#{btn.new}">Novo</a>
        </div>
    </div>

    <!-- Cartão da tabela: ocupa o resto da altura -->
    <div id="allocation-list-container"
         class="card bg-base-100 shadow-xl border border-base-300 flex-grow min-h-0 overflow-hidden flex flex-col">
        <div class="card-body p-0 flex-grow min-h-0 flex flex-col">

            <!-- ESTE div é quem rola -->
            <div class="flex-grow overflow-y-auto min-h-0">
                <table class="table table-zebra table-pin-rows w-full border-separate border-spacing-0">

                    <thead>
                        <tr class="text-[10px] uppercase opacity-70">
                            <th class="sort cursor-pointer hover:bg-base-300 bg-base-200 py-3 px-4 border-b border-base-300"
                                data-sort="name" th:text="#{alloc.label.contract}">Contrato</th>
                            <th class="sort cursor-pointer hover:bg-base-300 bg-base-200 py-3 px-4 border-b border-base-300 text-right"
                                data-sort="value" th:text="#{alloc.label.dailyValue}">Valor diario</th>
                            <th class="bg-base-200 py-3 px-4 border-b border-base-300 text-right"
                                th:text="#{alloc.label.actions}">Acoes</th>
                        </tr>
                    </thead>

                    <tbody class="listjs-container">
                        <tr th:each="alloc : ${allocations}" class="hover">
                            <td class="py-2 px-4">
                                <div class="font-bold name" th:text="${alloc.contractName}">Nome</div>
                                <div class="text-xs opacity-50" th:text="'ID: ' + ${alloc.contractId}">ID</div>
                            </td>
                            <td class="py-2 px-4 text-right font-mono font-bold value"
                                th:text="${#numbers.formatDecimal(alloc.dailyValue, 1, 'POINT', 2, 'COMMA')}">0,00</td>
                            <td class="py-2 px-4 text-right">
                                <button class="btn btn-ghost btn-sm btn-square"
                                        th:title="#{btn.edit}"
                                        th:hx-get="|/configs/allocations/edit/${alloc.contractId}|"
                                        hx-target="#modal-root">
                                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"
                                         stroke-width="1.5" stroke="currentColor" class="w-4 h-4 text-primary">
                                        <path stroke-linecap="round" stroke-linejoin="round"
                                              d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Z" />
                                    </svg>
                                </button>
                            </td>
                        </tr>

                        <tr th:if="${#lists.isEmpty(allocations)}">
                            <td colspan="3" class="py-12 text-center opacity-50" th:text="#{table.empty}">
                                Nenhum registro encontrado.
                            </td>
                        </tr>
                    </tbody>

                    <tfoot>
                        <tr class="font-bold">
                            <td class="bg-base-200 py-3 px-4 border-t border-base-300"
                                th:text="#{table.total.records(${#lists.size(allocations)})}">3 registros</td>
                            <td class="bg-base-200 py-3 px-4 border-t border-base-300 text-right font-mono"
                                th:text="${#numbers.formatDecimal(totalDiario, 1, 'POINT', 2, 'COMMA')}">0,00</td>
                            <td class="bg-base-200 py-3 px-4 border-t border-base-300"></td>
                        </tr>
                    </tfoot>
                </table>
            </div>
        </div>
    </div>
</section>
```

## Por que cada classe está ali

| Classe | Onde | Papel |
|---|---|---|
| `flex-grow min-h-0 overflow-hidden flex flex-col` | card e card-body | repassa a altura disponível até o div rolável |
| `flex-grow overflow-y-auto min-h-0` | div interno | **este** é o scroll; nunca o `<table>`, nunca a página |
| `table-pin-rows` | `<table>` | DaisyUI: fixa as linhas de `thead` e `tfoot` |
| `border-separate border-spacing-0` | `<table>` | sem isso as bordas das células fixadas somem ao rolar (`border-collapse` não convive com `position: sticky`) |
| `bg-base-200` | `th` e `td` do `tfoot` | fundo opaco — senão as linhas passam por baixo e aparecem através |
| `border-b` / `border-t` | células fixadas | a borda vai na **célula**; em `<tr>`/`<thead>` ela não acompanha o sticky |

Equivalente explícito ao `table-pin-rows`, quando precisar de `z-index`/offset diferente:

```html
<thead><tr><th class="sticky top-0 z-10 bg-base-200 …">…</th></tr></thead>
<tfoot><tr><td class="sticky bottom-0 z-10 bg-base-200 …">…</td></tr></tfoot>
```

## `<tfoot>`: quando e o quê

Sempre que a listagem tem valor agregado — soma, média, contagem, quantidade selecionada. Se não houver agregado, ao menos a contagem de registros (`table.total.records`), que também confirma para o usuário que ele chegou ao fim da lista.

O total é calculado **no servidor**, sobre o conjunto completo, e passado no model. Somar no cliente sobre as linhas renderizadas dá número errado assim que houver paginação ou filtro.

## Barra de paginação: irmã da área rolável, não `<tfoot>`

`<tfoot>` é para número que **pertence a uma coluna** e se alinha embaixo dela — soma, média, contagem. A barra de paginação não é isso: é controle. Tem texto de posição de um lado, botões do outro, e não se alinha a coluna nenhuma. Enfiá-la num `<td colspan="7">` mente sobre o que ela é, faz o botão herdar padding e borda de célula, e ainda deixa a barra à mercê do `border-separate` da tabela.

Ela vai como **`div` irmã do contêiner que rola**, com `shrink-0`. Fica presa embaixo pelo mesmo motivo que o `<tfoot>` fica: **não está dentro do que rola.**

```html
<div class="card … flex-grow min-h-0 overflow-hidden flex flex-col">
  <div class="card-body p-0 flex-grow min-h-0 flex flex-col">

    <div class="flex-grow min-h-0 overflow-y-auto">     <!-- só ISTO rola -->
      <table class="table table-pin-rows …">…</table>
    </div>

    <div class="shrink-0 border-t border-base-300 bg-base-100 p-3 flex items-center justify-between gap-3">
      <div class="text-xs text-base-content/60">
        <span th:text="#{paginacao.posicao(${pagina.pagina()}, ${pagina.totalPaginas()})}">Página 1 de 1</span>
        <span class="mx-2 opacity-30">|</span>
        <span th:if="${pagina.vazia()}" th:text="#{paginacao.vazio}">nenhum registro</span>
        <span th:unless="${pagina.vazia()}"
              th:text="#{paginacao.intervalo(${pagina.primeiroElemento()}, ${pagina.ultimoElemento()}, ${pagina.totalElementos()})}">1–10 de 0 registros</span>
      </div>

      <div class="join">
        <button type="button" class="btn btn-xs btn-outline join-item"
                th:disabled="${!pagina.temAnterior()}"
                th:hx-get="@{/funcoes/painel(pagina=${pagina.pagina() - 1})}"
                hx-target="#funcao-painel" hx-swap="outerHTML"
                th:text="#{paginacao.anterior}">Anterior</button>
        <button type="button" class="btn btn-xs btn-outline join-item"
                th:disabled="${!pagina.temProxima()}"
                th:hx-get="@{/funcoes/painel(pagina=${pagina.pagina() + 1})}"
                hx-target="#funcao-painel" hx-swap="outerHTML"
                th:text="#{paginacao.proxima}">Próxima</button>
      </div>
    </div>

  </div>
</div>
```

As duas coisas convivem: `<tfoot>` com o total das colunas **e** barra embaixo com "Página 2 de 7". Não são alternativas.

### O que costuma dar errado

- **Barra dentro do `div` que rola.** Rola junto e some — é o erro que a regra existe para evitar. Confira a indentação: a barra tem de fechar *depois* do `</div>` do scroll, não antes.
- **Botão apontando para a rota da página inteira.** Numa tela HTMX, o `hx-get` da paginação tem de ir para o endpoint do **fragmento**. Se for para a rota que devolve a página com `<html>` e as tags de script, o HTMX injeta um documento dentro de uma `div`, os scripts do layout rodam de novo e a aba trava. Nenhum teste de controller pega isso — o método devolve a view certa, o erro está na string do template; vale um teste que leia o arquivo e proíba a rota inteira.
- **Numeração 0-based vazando para a tela.** O número aparece no rodapé e na URL: se a paginação for 0-based internamente, alguém vai converter na borda da view e é ali que nasce o erro de um a menos. Numere a partir de 1 e faça a conta de `OFFSET` num lugar só, no servidor.
- **Página fora do intervalo tratada como erro.** Excluir o último registro da última página deixa a tela pedindo uma página que acabou de sumir. Corrija para a última válida em vez de recusar — o usuário não fez nada de errado.
- **Contagem "de 0".** Lista vazia é "Página 1 de 1", nunca "de 0": com zero, o rodapé mostra um intervalo impossível e o botão "próxima" fica habilitado apontando para o nada.

## Ordenação e filtro client-side (List.js)

Serve para listas que cabem inteiras no DOM (até ~1.000 linhas). Acima disso, paginação/ordenação no servidor.

```html
<script th:inline="javascript">
    (function () {
        var lista = new List('allocation-list-container', {
            valueNames: ['name', 'value', 'state'],
            listClass: 'listjs-container'
        });

        // Obrigatório: List.js recria nós; sem isso os hx-* das linhas param de funcionar
        lista.on('updated', function (l) {
            if (window.htmx) {
                htmx.process(l.list);
            }
        });
    })();
</script>
```

- `valueNames` casa com as classes nas células (`class="name"`, `class="value"`)
- Valor usado só para ordenar/buscar e que não deve aparecer vai num `<span class="chave hidden">`
- `data-sort="chave"` + classe `sort` no `th` habilitam o clique de ordenação
- Filtro por `toggle`/`select` chama `lista.filter(fn)`

## Ações por linha

- Ícone `btn-ghost btn-sm btn-square` na última coluna, alinhada à direita, com `th:title` — sem tooltip, ícone sozinho é adivinhação
- Editar abre modal via HTMX (`hx-target="#modal-root"`); o Controller devolve o fragmento do `<dialog>` inteiro
- Ação destrutiva pede confirmação (`hx-confirm`) e usa `btn-error`
- Menos de 3 ações: ícones diretos. 3 ou mais: `dropdown dropdown-end`

## Coluna e formato

- Número e valor monetário: `text-right font-mono`, formatados no template (`#numbers.formatDecimal(v, 1, 'POINT', 2, 'COMMA')`) ou já formatados no DTO
- Data: `#temporals.format(data, 'dd/MM/yyyy')`, `text-center`
- Estado/categoria: `badge` com cor semântica (`badge-success`, `badge-warning`), não texto solto
- Coluna que só faz sentido em tela larga: `hidden lg:table-cell`
- Texto longo: `truncate` + `th:title` com o valor completo

## Anti-padrões

- **`overflow-auto` no `<table>`** — não funciona; o scroll tem que estar num `div` em volta
- **Página inteira rolando** (`body` sem `overflow-hidden`) — o cabeçalho fixo perde o sentido, porque o contêiner de referência passa a ser a janela
- **Esquecer `min-h-0`** em algum nível da cadeia — sintoma clássico: o rodapé da tabela some abaixo da dobra
- **`sticky` sem fundo opaco** — linhas aparecem através do cabeçalho ao rolar
- **Milhares de linhas no DOM** "porque tem scroll" — paginar no servidor
- **Total somado no cliente** — erra com filtro/paginação
- **Tabela para layout** (formulário, cartões) — isso é `grid`
- **Barra de paginação dentro do `<tfoot>`** ou dentro do `div` que rola — no primeiro caso o botão vira conteúdo de célula, no segundo a barra rola junto e some
