# TableGrid (plugin idalko iGrid)

Os campos de tabela do SGO — Histórico Profissional, quadro de vagas — não são campos do Jira.
São grids do plugin **idalko iGrid**, com árvore REST própria. Nada do que a documentação do
Jira diz sobre customfield se aplica a eles.

## 1. Os dois endpoints

```
GET  /rest/idalko-igrid/1.0/grid/{gridId}/issue/{issueId}
POST /rest/idalko-igrid/1.0/grid/{gridId}/issue/{issueId}
     {"rows": [ { "<coluna>": "<valor>", … } ]}
```

- **`gridId` é o id do customfield do grid.** Confirmado por chamada em 2026-08-19; antes disso
  era inferência.
- **`issueId` é o id numérico da ocorrência**, não a chave `PROJ-123`. É o `id` que o
  `POST /rest/api/2/issue` devolve ao lado de `key` — guarde os dois: a chave é o que uma pessoa
  procura, o id é o que o grid exige.
- As colunas se chamam pelo **nome interno** da configuração do grid.

## 2. A configuração do grid, e como lê-la

A definição fica na administração do Jira, em formato de propriedades:

```properties
gd.columns=empresa,funcao,cargo,entrada,saida,tempoMeses
gd.tablename=historico_profissional
gd.ds=jira

col.empresa=Empresa
col.empresa.type=string
col.empresa.required=true
col.empresa.maxLength=128

col.ati=ATI
col.ati.type=checkbox

col.entrada=Entrada
col.entrada.type=date
col.entrada.formatdate=dd/mm/yy
col.entrada.required=true

col.tempoMeses=Meses
col.tempoMeses.type=string
col.tempoMeses.hidden=true
```

Três leituras que importam:

- **`gd.columns` é a lista de colunas ativas.** `col.ati` existe na configuração e está **fora**
  de `gd.columns` — não é coluna ativa e não entra no payload. Definição não implica presença.
- **`maxLength` é cobrança do grid, não sua.** Valide antes de enviar. Estourar o limite falha na
  etapa do grid, com a ocorrência **já criada** — e uma ocorrência pela metade na fila é caro de
  desfazer.
- **`formatdate=dd/mm/yy` é como o servidor renderiza, não o que a API aceita.** Ver §4.

## 3. Escrita e leitura têm formas diferentes

Escreve-se escalar:

```json
{"rows": [
  {"empresa": "Basis", "funcao": "Desenvolvedor", "cargo": "Analista",
   "entrada": 478494000000, "saida": null, "tempoMeses": "92"}
]}
```

Lê-se objeto:

```json
{"values": [
  {"empresa": {"value": "Basis"}, "funcao": {"value": "Desenvolvedor"}, …}
]}
```

Código que roundtripa — grava e relê para conferir, ou lê linha para calcular — precisa saber
disso. Um `row.get("perfil")` que devolve `{"value": "…"}` e é usado como string produz o
comportamento mais irritante possível: funciona no teste com fixture escrita à mão, e falha no
servidor.

**E a chave do array varia.** Conforme a versão do plugin, a leitura vem em `values` ou em
`rows`. Leia os dois:

```java
JsonNode linhas = grid.has("values") ? grid.path("values") : grid.path("rows");
```

## 4. Datas: milissegundos de época, no fuso do servidor

O endpoint recusa `dd/mm/yy` **e** ISO, com
`The date and datetime column value has to be a number (milliseconds)`.

- Meia-noite da data **no fuso do servidor**, nunca em UTC — senão a data anda um dia para trás,
  em silêncio. Detalhe e código em [`campos-e-payload.md`](campos-e-payload.md) §6.
- **Célula vazia é `null` JSON**, não string vazia. Aceito; a linha volta sem data.
- Colunas calculadas (tipo `tempoMeses`) costumam ser `string` no grid mesmo guardando número.
  Calcule **na hora do envio**, não quando o rascunho foi salvo: um vínculo em curso tem de
  produzir o número de hoje, e congelá-lo no modelo faz o leitor ver menos experiência do que a
  real.

## 5. Idempotência

A guarda certa é grosseira: **"tem linha?", e não "tem estas linhas?"**.

```java
private boolean jaTemLinhas(String issueId) {
    JsonNode grid = sgo.listarLinhasGrid(gridId, issueId);
    JsonNode linhas = grid.has("values") ? grid.path("values") : grid.path("rows");
    return linhas.isArray() && !linhas.isEmpty();
}
```

O conjunto de linhas vai de uma vez, então comparar linha a linha resolveria um problema que não
existe. Isso vale enquanto o grid for escrito por um ator só; se dois escrevem, a guarda muda de
natureza e vira o caso do outbox (ver [`cliente-python.md`](cliente-python.md)).

## 6. Vazio não pode ser indistinguível de falha

O erro mais fácil de cometer aqui:

```python
def fetch_tablegrid_data(issue_id, jira_client):
    """Linhas do grid. Grid vazio devolve []; falha do Jira levanta.

    A distinção importa: [] no erro fazia uma queda do Jira ficar indistinguível de uma
    ocorrência sem linhas, e a requisição terminava como um "skipped" silencioso de sucesso.
    """
    response = jira_client._session.get(
        f"{jira_client.server_url}/rest/idalko-igrid/1.0/grid/{GRID_ID}/issue/{issue_id}"
    )
    response.raise_for_status()
    return response.json().get("values", [])
```

Um `except: return []` nessa função transforma indisponibilidade em ausência de dado, e o
chamador registra sucesso. É a mesma classe de erro do `total: 0` da busca anônima.
