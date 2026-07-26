# Formulários

Regra da casa: **alinhamento e espaçamento saem de utilitário Tailwind, nunca do acaso.** Campo solto direto no HTML produz label colado no input, campos de larguras diferentes e botão encostado no último campo — o defeito visual mais comum e o mais barato de evitar.

## Campo padrão

Cada campo é um bloco: rótulo, controle, e mensagem de ajuda/erro quando houver.

```html
<fieldset class="fieldset">
    <legend class="fieldset-legend font-bold" th:text="#{provider.contract.label}">Numero do contrato</legend>
    <input type="text" id="contractNumber" name="contractNumber"
           class="input w-full font-mono"
           th:field="*{contractNumber}"
           th:errorclass="input-error"
           placeholder="000157" required />
    <p class="label text-base-content/60" th:text="#{provider.contract.help}">Formato: 6 digitos.</p>
    <p class="text-error text-sm" th:if="${#fields.hasErrors('contractNumber')}"
       th:errors="*{contractNumber}">Erro</p>
</fieldset>
```

- `fieldset` + `fieldset-legend` é o agrupamento de campo do DaisyUI 5. `form-control` e `input-bordered` são da v4 e não fazem mais nada na v5 (o `input` já vem com borda) — dão a impressão de estar estilizando quando não estão
- `th:field` gera `id`, `name` e `value` a partir do objeto do formulário — usar sempre que houver `@ModelAttribute`
- `th:errorclass="input-error"` marca o controle em vermelho só quando aquele campo falhou
- **`w-full` em todo controle**: campo que dimensiona pelo conteúdo desalinha a coluna inteira
- **`font-mono`** em dado técnico (código, contrato, CNPJ, telefone, valor) — dígitos alinhados são conferíveis

## Espaçamento e grid

Espaçamento vive no contêiner (`gap-*`), não em `margin` por campo — assim adicionar ou remover um campo não exige reajustar margem.

```html
<form th:action="@{/configs/provider/save}" th:object="${config}" method="post"
      class="flex flex-col gap-4">

    <input type="hidden" th:field="*{id}" />

    <!-- Duas colunas em telas médias, uma em telas pequenas -->
    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <fieldset class="fieldset">…</fieldset>
        <fieldset class="fieldset">…</fieldset>

        <!-- Campo largo ocupa a linha inteira -->
        <fieldset class="fieldset md:col-span-2">
            <legend class="fieldset-legend font-bold" th:text="#{provider.obs.label}">Observacao</legend>
            <textarea class="textarea w-full" rows="3" th:field="*{observacao}"></textarea>
        </fieldset>
    </div>

    <div class="card-actions justify-end mt-4 pt-4 border-t border-base-200">
        <a th:href="@{/configs/provider}" class="btn btn-ghost" th:text="#{btn.cancel}">Cancelar</a>
        <button type="submit" class="btn btn-primary gap-2">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"
                 stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" />
            </svg>
            <span th:text="#{btn.save}">Salvar</span>
        </button>
    </div>
</form>
```

- `grid-cols-1 md:grid-cols-2` — nunca largura fixa em `px`
- `md:col-span-2` para textarea, endereço, qualquer campo que precise da linha
- Ações separadas do último campo (`mt-4 pt-4 border-t`) e alinhadas à direita: primária `btn-primary`, secundária `btn-ghost`, destrutiva `btn-error`
- Formulário dentro de `card`: `<div class="card bg-base-100 shadow-xl border border-base-300"><div class="card-body">…`

## Agrupamento por seção

Formulário longo se divide em seções com título, não em uma pilha de 20 campos:

```html
<div class="flex flex-col gap-6">
    <div>
        <h2 class="card-title text-primary" th:text="#{form.section.identificacao}">Identificacao</h2>
        <div class="divider my-2"></div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">…</div>
    </div>
    <div>
        <h2 class="card-title text-primary" th:text="#{form.section.contato}">Contato</h2>
        <div class="divider my-2"></div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">…</div>
    </div>
</div>
```

## Outros controles

```html
<!-- Select -->
<fieldset class="fieldset">
    <legend class="fieldset-legend font-bold" th:text="#{alloc.label.ruleType}">Tipo de regra</legend>
    <select class="select w-full" th:field="*{ruleType}">
        <option th:each="tipo : ${T(br.com.basis.app.RuleType).values()}"
                th:value="${tipo}" th:text="#{'RuleType.' + ${tipo.name()}}">Tipo</option>
    </select>
</fieldset>

<!-- Checkbox / toggle: rótulo à esquerda, controle à direita, com gap -->
<label class="label cursor-pointer justify-start gap-3">
    <input type="checkbox" class="toggle toggle-primary" th:field="*{deduzirFerias}" />
    <span class="label-text font-bold" th:text="#{alloc.deduct.vacation}">Deduzir ferias</span>
</label>

<!-- Upload -->
<fieldset class="fieldset">
    <legend class="fieldset-legend font-bold" th:text="#{upload.file.label}">Arquivo</legend>
    <input type="file" name="file" class="file-input w-full" accept=".csv,.xlsx" required />
    <p class="label text-base-content/60" th:text="#{upload.file.help}">CSV ou XLSX, ate 10 MB.</p>
</fieldset>
```

`gap-3` no `label` do checkbox/toggle é o que evita o rótulo colado no controle.

## Validação

A regra real está no servidor (Bean Validation). `required`/`maxlength` no HTML são conveniência de UX e não substituem nada.

```java
@PostMapping("/configs/provider/save")
public String salvar(@Valid @ModelAttribute("config") ProviderForm form,
                     BindingResult binding, Model model) {
    if (binding.hasErrors()) {
        return "configs/provider";   // volta com os erros preenchidos por th:errors
    }
    service.salvar(form);
    return "redirect:/configs/provider?salvo";
}
```

- Erro **abaixo do campo** (`th:errors` + `text-error text-sm`) e `input-error` no controle — resumo genérico no topo não diz o que corrigir
- Erro global (regra que cruza campos): `th:errors="*{global}"` num `alert alert-error` acima do formulário
- Sucesso: `redirect:` com flash attribute e `alert alert-success` — nunca reexibir o POST (evita reenvio ao atualizar)

## Formulário em modal com HTMX

```html
<!-- fragmento devolvido pelo Controller, alvo #modal-root -->
<dialog id="edit-modal" class="modal modal-open">
    <div class="modal-box max-w-2xl">
        <h3 class="text-lg font-bold" th:text="#{alloc.edit.title}">Editar</h3>
        <form th:action="@{/configs/allocations/save}" th:object="${form}" method="post"
              hx-post="/configs/allocations/save"
              hx-target="#allocation-list-container"
              hx-swap="outerHTML"
              class="flex flex-col gap-4 mt-4">
            …
            <div class="modal-action">
                <button type="button" class="btn btn-ghost"
                        onclick="document.getElementById('edit-modal').remove()"
                        th:text="#{btn.cancel}">Cancelar</button>
                <button type="submit" class="btn btn-primary" th:text="#{btn.save}">Salvar</button>
            </div>
        </form>
    </div>
    <div class="modal-backdrop" onclick="this.parentElement.remove()"></div>
</dialog>
```

O Controller devolve, no sucesso, o fragmento da lista atualizada; em erro de validação, o próprio modal com os erros. O CSRF vai no header pelo listener global do layout.

## Anti-padrões

- `<input>` sem `<label>` associado — quebra acessibilidade e clique no rótulo
- Rótulo como texto solto acima do campo, sem `gap`/`label` — é o "label colado no campo"
- `margin` campo a campo em vez de `gap` no contêiner
- Largura fixa (`w-64`, `style="width: 300px"`) em vez de `w-full` dentro de grid
- Placeholder no lugar do rótulo — some ao digitar e não é lido por leitor de tela
- `<br>` ou `<table>` para alinhar campos
- Validação só no cliente
- Formulário sem `th:object`/`th:field`, montando `name` na mão — perde binding e repopulação de erro
