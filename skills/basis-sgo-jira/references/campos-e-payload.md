# Campos do SGO e a forma do valor

O que o `createmeta` responde, o que ele **não** responde, e como um valor precisa estar
formatado para o Jira aceitá-lo.

## 1. A chamada

```
GET /rest/api/2/issue/createmeta
      ?projectIds=<projeto>
      &issuetypeIds=<tipo>
      &expand=projects.issuetypes.fields
```

Sem o `expand`, vem a lista de campos sem as opções — inútil para montar formulário. Com ele, a
resposta de um projeto de RH da Basis passa de 130 KB e traz ~58 campos.

Responde **sem autenticação** quando o projeto permite criação anônima. Isso é conveniente e é
armadilha: ver §2 da SKILL.

## 2. O que vem por campo

```json
{
  "id": "customfield_12743",
  "name": "Escolaridade",
  "required": true,
  "schema": { "type": "option-with-child", "custom": "…:cascadingselect" },
  "allowedValues": [
    { "id": "12832", "value": "Superior",
      "children": [ { "id": "12837", "value": "Completo" },
                    { "id": "15230", "value": "Em andamento" } ] }
  ]
}
```

- **`required` é a autoridade sobre obrigatoriedade.** Mais confiável que procurar "Obrigatório"
  no HTML da tela, e é o que muda quando o RH resolve aliviar o formulário.
- **As cascatas vêm inteiras e aninhadas**, pai e filhos numa árvore só. Não há segunda chamada.
- **A opção traz só `id`, `self` e `value`.** Nada mais. E
  `GET /rest/api/2/customFieldOption/{id}` devolve o mesmo trio.

## 3. Quatro coisas que o `createmeta` não diz

### Não diz quais opções estão desabilitadas

Verificado em 2026-08-19: não existe campo `disabled`, e **nenhum endpoint da API expõe esse
estado**. Um formulário construído a partir do `createmeta` oferece as opções desativadas junto
com as ativas.

A única saída é uma lista de exclusão em configuração:

```yaml
application:
  catalogo:
    # Opções desabilitadas no Jira que o createmeta continua devolvendo -- não há campo
    # `disabled` na API, então esconder é decisão nossa e precisa estar escrita.
    opcoes-ocultas: [12030]
```

É dívida assumida, não solução: quando o RH desabilitar a próxima, o formulário volta a
oferecê-la até alguém comparar as duas fontes. Um teste fixa a lista atual, para que a próxima
divergência apareça como falha e não como surpresa em produção.

**A técnica de detecção tem limite.** Comparar `createmeta` com o HTML renderizado acusa tanto
opção desabilitada quanto opção **criada depois** do último HTML baixado — uma opção nova
apareceu como fantasma numa varredura e, na seguinte com o HTML atualizado, mostrou-se ativa. A
comparação só conclui alguma coisa com as duas fontes lidas **no mesmo momento**.

E não tente medir uso por JQL anônima: ela devolve `total: 0` até para opção em uso, porque a
busca é filtrada por permissão.

### Não diz quais campos a tela de **edição** aceita

Outra lista, outro endpoint: `GET /rest/api/2/issue/{chave}/editmeta`. O Jira recusa `PUT` de
campo fora da tela de edição com a **mesma** `400 "Field cannot be set. It is not on the
appropriate screen, or unknown."` que dá para campo apagado — perguntar antes é a diferença
entre saber o alcance de um update e descobri-lo campo a campo, em requisições recusadas.

De lambuja: sem permissão de edição, o `editmeta` devolve a ocorrência **sem** `fields`.

### Não diz que uma post-function vai reescrever o que você mandou

Campo obrigatório na criação pode ser sobrescrito logo depois por post-function de transição —
o caso comum é o `summary`. Mande algo válido e **não dependa do que fica lá**. Quem vir a
divergência numa conferência não está diante de um defeito.

Medido em 2026-08-22: a post-function é de **transição** e **não roda no `edit`**.

### Não diz que os rótulos têm lixo

Rótulos vindos da administração do Jira carregam espaço não-quebrável (`U+00A0`) no lugar de
espaço normal, hífen fora do padrão (`MG- Minas Gerais`), acentuação inconsistente.

Duas consequências, e as duas são regra:

1. **Persista o `id` da opção, nunca o rótulo.** Rascunho salvo com rótulo normalizado pela tela
   não volta a casar com o rótulo da origem, e a tradução falha em silêncio num campo obrigatório.
2. **Normalize com tolerância, não com contrato implícito.** Se a sigla da UF vem no rótulo, leia
   os **dois primeiros caracteres em maiúsculas**, não o que vem antes de ` - `. Assim
   `MG- Minas Gerais` resolve igual a `MG - Minas Gerais`, e o cadastro pode ser corrigido sem
   mexer no código.

## 4. O catálogo envelhece — e é para isso que serve a contagem

Entre duas capturas do mesmo `createmeta` com três dias de diferença, mudaram: contagem de opções
em três listas, obrigatoriedade de **treze** campos, dois campos saíram da tela de criação, e uma
cascata ganhou duas filhas novas.

**Ninguém mencionou o último par.** Ele apareceu porque o teste cobra o total de filhas: 396
virou 398, o teste ficou vermelho e obrigou a olhar.

Portanto:

- Versione a fixture com **a data da captura no nome** (`createmeta-<projeto>-YYYY-MM-DD.json`).
- Fixe nos testes as contagens **daquela captura** — para que a diferença apareça numa revisão,
  não para congelar o catálogo.
- Recapture de propósito antes de release, e leia o diff.

## 5. Tipo do campo → forma no `fields`

| Tipo no Jira | Forma | Erro típico |
|---|---|---|
| `textfield`, `textarea` | `"texto"` | — |
| `datepicker` | `"1985-03-01"` | mandar `dd/MM/yyyy` |
| campo de data-hora | `"2026-04-07T14:58:24.000-0300"` | offset com dois-pontos, ou sem milissegundos |
| `float` | `1234.56` | mandar `"R$ 1.234,56"` ou `"1234,56"` |
| `select`, `radiobuttons` | `{"id": "…"}` | mandar o rótulo em `value` |
| `multiselect`, `multicheckboxes` | `[{"id": "…"}]` | mandar objeto quando só há uma opção |
| `cascadingselect` | `{"id": "pai", "child": {"id": "filho"}}` | tratar como dois campos |
| `tableGridCFType` | não vai no `fields` | tentar mandar junto no `POST /issue` |
| `scripted-field` | **não gravável** | — |
| `message` | **não gravável** (é texto de instrução na tela) | — |
| campo nFeed | sem `allowedValues`; costuma estar quebrado | assumir que é `select` |

**Campo nulo simplesmente não entra no payload.** Se um obrigatório faltar, o SGO responde `400`
com `errors`, que é defeito seu — e é assim que você quer descobrir, não com o campo gravado
vazio.

Um exemplo de payload, com as três formas difíceis lado a lado. Projeto e tipo vêm da configuração (§0 da SKILL); os ids de campo e de opção, do `createmeta`:

```json
{
  "fields": {
    "project":   { "id": "<projectId>" },
    "issuetype": { "id": "<issueTypeId>" },
    "summary": "Texto provisório -- a post-function reescreve",

    "customfield_12257": "1985-03-01",
    "customfield_12242": 5000.00,
    "customfield_12744": { "id": "12831" },
    "customfield_13757": [ { "id": "13802" } ],
    "customfield_12743": { "id": "12832", "child": { "id": "12837" } }
  }
}
```

## 6. Os três formatos de data

| Onde | Formato | Exemplo |
|---|---|---|
| customfield `datepicker` | ISO local | `1985-03-01` |
| customfield de data-hora | `yyyy-MM-dd'T'HH:mm:ss.SSSZ` | `2026-04-07T14:58:24.000-0300` |
| coluna de data do **TableGrid** | milissegundos de época | `478494000000` |

O terceiro é imposto, não escolhido: o endpoint do grid recusa `dd/mm/yy` **e** ISO com
`The date and datetime column value has to be a number (milliseconds)`.

Isso mata o risco de pivô de século e cria outro no lugar: **o fuso**. O servidor renderiza o
número no fuso dele. Meia-noite calculada em UTC vira 21h do dia anterior, e a data anda um dia
para trás sem erro nenhum.

```java
static long emMilissegundos(LocalDate data, ZoneId fuso) {
    return data.atStartOfDay(fuso).toInstant().toEpochMilli();
}
```

`fuso` é **parâmetro de configuração**, nunca `ZoneId.systemDefault()`: a máquina onde a
aplicação roda não tem nada a ver com o fuso do Jira. Confirme o do servidor pelo offset em
`GET /rest/api/2/serverInfo`.

Escreva também o caminho de volta (`deMilissegundos`). Serve para o teste fechar o círculo e para
o log dizer a data em vez do número — `entrada=478494000000` num diagnóstico não ajuda ninguém.

E o formato de data-hora tem uma pegadinha própria em Python: `strftime("%z")` já produz
`-0300` sem dois-pontos, mas os milissegundos precisam ser montados à mão a partir de
`microsecond // 1000` — `%f` daria seis dígitos, que o Jira Server não aceita.

## 7. O de-para com o banco do SGO não é atalho

Existe um PostgREST na frente do banco do SGO (autenticação OIDC pelo Keycloak). Ele é útil para
leitura analítica, e é **má fonte para uma carga de referência**. Medido no caso de municípios:

| Resultado da correspondência por nome + UF | Registros |
|---|---|
| Correspondência única | 5.546 (99,6%) |
| **Sem correspondência** | **25 (0,4%)** |
| Ambígua | 0 |

Os 25 são divergência de grafia ou renomeação, e não são vilarejos — um deles tem ~57 mil
habitantes. Um usuário de lá encontraria um **campo obrigatório impossível de preencher**, e a
falha só apareceria em produção, com gente real.

Além disso, a "lista de municípios" do SGO tem 10.683 linhas, das quais ~5.000 são distritos, e
a de UFs traz 28 siglas incluindo uma que é país.

**Regra:** quando existe uma fonte oficial (IBGE, ViaCEP), carregue dela, gere migration
revisável e trate o SGO como destino, não como dicionário.

## 8. O inventário de campos não mora aqui

Esta reference é sobre **como** ler e escrever campo. Qual campo existe em qual tipo de
ocorrência — id, tipo, obrigatoriedade, forma — é outro assunto e está fora do escopo: o SGO tem
dezenas de tipos de ocorrência, cada um com sua tela e suas listas, e um inventário transcrito
para cá envelheceria em silêncio na primeira mudança do administrador.

A resposta de quem integra é sempre a mesma: **leia do `createmeta`, em runtime**. Ele é a fonte
que não desatualiza.
