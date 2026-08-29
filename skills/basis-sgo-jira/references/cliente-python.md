# Cliente Python: `ks-jira`, a biblioteca `jira` e o que ela não alcança

No lado Python a casa usa a biblioteca `jira` do PyPI, embrulhada numa lib compartilhada
(`ks-jira`, no workspace do kaizenstat). É uma escolha diferente do Java — lá a interface é
declarativa e crua; aqui há um SDK — e a diferença tem consequências.

## 1. `ks-jira`

```python
# ks_jira/config.py
class JiraSettings(BaseSettings):
    sgo_server_url: str = "https://sgo.basis.com.br"
    sgo_user: Optional[str] = None
    sgo_password: Optional[str] = None

    model_config = SettingsConfigDict(env_prefix="KS_", env_file=".env", extra="ignore")
```

```python
# ks_jira/client.py
def get_jira_client():
    """Retorna uma instância autenticada do cliente JIRA (SGO)."""
    if not settings.sgo_user or not settings.sgo_password:
        logger.warning("Credenciais do SGO (Jira) não configuradas (KS_SGO_USER/KS_SGO_PASSWORD).")
        return None
    try:
        return JIRA(server=settings.sgo_server_url,
                    basic_auth=(settings.sgo_user, settings.sgo_password))
    except (JIRAError, RequestException) as e:
        logger.error(f"Erro ao conectar no SGO: {str(e)}")
        return None
```

**Devolve `None` em vez de estourar.** Isso é deliberado e é a parte que mais precisa de
atenção de quem chama: um `None` não tratado vira `AttributeError` três frames adiante, longe da
causa. O padrão certo é **adiar o trabalho, não segui-lo**:

```python
try:
    jira = jira_factory()
except Exception as exc:  # noqa: BLE001 -- credencial faltando adia, não falha
    logger.error("{} ação(ões) pendente(s) e o cliente não pôde ser construído ({}); "
                 "deixando na fila.", len(pendentes), exc)
    jira = None
if jira is None:
    report.deferred = len(pendentes)
    return report          # nada é perdido; a próxima execução tenta
```

O equivalente Java disso é o `log.warn` de arranque e o `temCredencial()` antes de perguntar.

## 2. O que o SDK cobre

```python
issue = jira.create_issue(fields={
    "project":   {"key": project_key},
    "summary":   summary,
    "description": body,
    "issuetype": {"name": issue_type},
})
issue.key                       # PROJ-123
jira.add_comment(issue_key, body)
jira.search_issues(jql, maxResults=1)
issue.update(fields={"customfield_57940": num_vagas})
```

Duas observações:

- **`search_issues` monta um `GET`.** A JQL vai na URL. Para JQL que carrega dado pessoal, isso é
  inaceitável — use `POST /rest/api/2/search` pela sessão (§3). Ver §11 da SKILL.
- **A JQL usa `cf[12259]`, e o catálogo devolve `customfield_12259`.** O número é o mesmo; a
  conversão fica num lugar só:

  ```python
  jql = f'cf[{re.sub(r"\D", "", customfield_id)}] ~ "{valor}"'
  ```

  E o `~` **é sensível à pontuação**: `123.456.789-00` e `12345678900` são buscas diferentes, e
  a base tem registros nas duas formas. Busque as duas com `OR` — tirar esse `OR` devolve "não
  existe" para metade dos casos, com a convicção de um `200`.

## 3. Quando descer para `_session`

`jira_client._session` é a sessão `requests` já autenticada da biblioteca. É privado, e é o
caminho aceito na casa para o que o SDK não expõe:

```python
async def update_jira_issue_fields(jira_client, issue_key, payload):
    response = jira_client._session.put(
        f"{jira_client.server_url}/rest/api/2/issue/{issue_key}",
        params={"notifyUsers": "false"},
        json={"fields": payload},
    )
    response.raise_for_status()
```

Três usos reais:

| Precisa de | Por quê o SDK não serve |
|---|---|
| `notifyUsers=false` num `PUT` | `issue.update()` não expõe o parâmetro |
| Endpoints do iGrid | Não são API do Jira; o SDK não os conhece |
| `expand=changelog` com paginação | O acesso pelo objeto não deixa controlar `startAt`/`maxResults` |

**Sobre `notifyUsers=false`:** sem ele, toda edição notifica quem observa a ocorrência — num
fluxo de atualização, é um e-mail por retomada. Desligar é privilégio de administrador no Jira
Server; este código roda em produção com o parâmetro, então o caminho é conhecido. Confirme na
sua própria conta antes de contar com ele: `GET /rest/api/2/mypermissions?issueKey=…`.

## 4. Reconstruir dado a partir do changelog

Campo que ficou vazio por bug pode ser recuperado do histórico da ocorrência: a transição que
deveria tê-lo preenchido está lá.

```python
response = jira_client._session.get(
    f"{jira_client.server_url}/rest/api/2/issue/{issue_key}",
    params={"expand": "changelog", "startAt": 0, "maxResults": 200},
)
```

```python
def extract_transition_timestamp(changelog, from_status, to_status):
    for history in changelog.get("changelog", {}).get("histories", []):
        for item in history.get("items", []):
            if (item.get("field") == "status"
                    and item.get("from") == from_status
                    and item.get("to") == to_status):
                return parse_jira_created(history["created"])
    return None
```

- Os status no changelog são **ids**, não nomes.
- O `created` vem em dois formatos (`…%S.%f%z` e `…%S%z`). Tente os dois; não presuma.
- Uma rotina de reparo **precisa de `--dry-run`**, e o `dry_run` tem de percorrer o caminho
  inteiro e só não escrever. Um dry-run que decide antes de calcular não prova nada.
- Só escreva o campo que está vazio: `if atual is None and recuperado is not None`. Reparo que
  sobrescreve valor existente é perda de dado com cara de conserto.

## 5. Webhooks do Jira

Recebendo transição por webhook, o payload é do Jira e não do seu domínio:

```python
class JiraIssueFields(BaseModel):
    customfield_11945: Optional[Dict[str, Any]] = None   # objeto com `value`
    customfield_26140: Optional[Any] = None              # às vezes objeto, às vezes string

class JiraIssue(BaseModel):
    id: str
    key: str
    fields: JiraIssueFields

class WebhookPayload(BaseModel):
    transition: Optional[Dict[str, Any]] = None
    issue: JiraIssue
```

**O mesmo customfield chega ora como string, ora como objeto de opção**, dependendo da transição.
Normalize num lugar só, e trate ausência como **categoria conhecida**, não como valor faltante:

```python
def normalize_alocacao(raw) -> str:
    value = raw.get("value") if isinstance(raw, dict) else raw
    if not isinstance(value, str):
        return UNKNOWN          # sentinela; é uma categoria real, não um vazio
    return value.strip() or UNKNOWN
```

Modele com `Optional` e `extra` tolerante: o RH acrescenta campo na tela sem avisar ninguém, e um
modelo estrito transforma isso em `422` no seu endpoint.

E não devolva a exceção ao chamador: o texto dela pode carregar string de conexão, JQL ou pedaço
de payload. Traceback no log e na linha de auditoria; na resposta HTTP, a chave da ocorrência e
"veja os logs".

## 6. O outbox transacional

O padrão que o lado Python trouxe, e que o Java resolve com saga: **grave a intenção antes de
tentar**.

A falha que ele existe para evitar foi medida, não imaginada. A rotina persistiu a linha de
controle, chamou o Jira, uma indisponibilidade estourou, a exceção foi registrada e engolida, e a
execução terminou reportando sucesso. A execução seguinte viu o período já registrado, pulou —
corretamente, para não duplicar a série — e **nunca retentou**.

As três propriedades que são o desenho inteiro:

- **`dedupe_key` é identidade de negócio**, não hash do corpo: este contrato, este mês, este tipo
  de nota. Enfileirar vira idempotente, e é o que permite enfileirar a cada execução sem
  verificar nada antes.
- **Dependência entre duas escritas é dado, não ordem de código.** Um comentário que precisa da
  chave de uma ocorrência criada por outra entrada **declara** essa dependência: duas chamadas ao
  Jira não compartilham transação.
- **A entrega reivindica a linha antes de chamar** (`sending`, tentativa contada, commitada). Uma
  queda no meio deixa reivindicação visível, retentada após carência. Pode repetir um envio que
  deu certo pouco antes da queda, e isso é aceito: *at-most-once não existe sobre HTTP*.

Estados: `pending` → `sending` → `sent` | `failed`, mais **`suppressed`** — a linha que uma
execução de ensaio gravou e que nenhuma rotina de entrega seleciona. Inerte por construção; só
um ato deliberado (`release_suppressed`) a devolve para `pending`. É assim que se ensaia contra
um SGO que é o de produção (§9 da SKILL).

Teto de tentativas generoso e explícito: o Jira recusa corpo malformado (projeto inexistente,
tipo inválido) de forma idêntica para sempre, e retentar isso a cada execução soterra as entradas
que ainda passariam.
