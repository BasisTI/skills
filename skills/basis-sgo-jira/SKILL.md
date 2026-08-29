---
name: basis-sgo-jira
description: >-
  Integrar uma aplicação da Basis com o SGO — o Jira customizado da empresa (Jira Server
  6.3.13, REST v2, Basic Auth): criar e editar ocorrência, ler o catálogo de campos pelo
  `createmeta`, escrever linha de TableGrid do plugin iGrid, subir anexo, consultar por JQL e
  classificar o que volta. Use quando alguém disser "criar ocorrência no SGO", "integrar com o
  Jira", "customfield", "createmeta", "TableGrid", "iGrid", "JQL", "anexo no Jira", "webhook do
  Jira", "o Jira devolveu 400", "Field cannot be set", "a data do grid veio um dia antes", "o
  campo gravou vazio e ninguém viu", "a opção não existe no catálogo"; ao configurar credencial
  do SGO numa aplicação; e **antes de qualquer escrita a partir de dev ou de staging**, porque
  existe um SGO só e ele é o de produção. Vale para Java (Spring `@HttpExchange`) e para Python
  (`ks-jira` + biblioteca `jira`).
---

# Integração com o SGO

A ideia mais cara de trazer para este assunto é que o SGO "é um Jira, então vale a documentação
do Jira". Vale pouca coisa dela, e por três motivos que se acumulam.

**É Jira Server 6.3.13.** REST v2, Basic Auth, sem ADF, sem `/rest/api/3`, sem
`/rest/api/3/search/jql`, sem token de API. Tudo o que a documentação do Atlassian Cloud diz
sobre autenticação, sobre formato de descrição e sobre os endpoints novos de busca é sobre outro
produto. O que responde é `/rest/api/2/…` com `Authorization: Basic`.

**Boa parte do que uma integração da Basis toca não é Jira.** Os campos de tabela — Histórico
Profissional, vagas — são grids do plugin **idalko iGrid**, que tem árvore REST própria
(`/rest/idalko-igrid/1.0/…`) e formato próprio. Há campos nFeed que não têm `allowedValues`, há
`scripted-field` calculado que não aceita escrita, e há **post-function reescrevendo o que você
mandou** depois que o `POST` respondeu `201`.

**E existe um SGO só.** Não há instância de homologação. Desenvolvimento, staging e produção
apontam para `https://sgo.basis.com.br`, para os mesmos projetos e para a mesma fila do RH. Toda
escrita que sai de qualquer ambiente é registro de verdade sobre gente de verdade — e é por isso
que a §9 existe e não é opcional.

## Quando usar

Ative esta skill quando o assunto for **a conversa com o SGO**: montar payload de ocorrência,
resolver id de customfield e de opção, escrever no grid, subir anexo, buscar por JQL, receber
webhook, decidir se um erro se retenta, ou configurar a credencial numa aplicação nova.

**O que ela não cobre.** Como o app Spring é montado em volta disso — módulos, propriedades,
Flyway — é `basis-spring-app`; o equivalente em Python é `basis-python-app`; o texto de uma nota
de incidente em wiki markup do Jira é `basis-relatorio-incidente`. A fronteira é útil: aqui o
objeto é o **sistema do outro lado da rede**, não o seu.

## Os três hábitos que resolvem

1. **Pergunte ao SGO antes de supor.** `createmeta` diz quais campos existem, de que tipo, com
   que opções e quais são obrigatórios hoje. `editmeta` diz quais a tela de **edição** aceita, que
   não são os mesmos. `mypermissions` diz o que a sua credencial pode. As três respostas mudam sem
   aviso, porque quem mexe é o RH na administração do Jira.
2. **Trate `200` como opinião.** O Jira responde `200` com corpo de erro, e responde `400` tanto
   para regra de negócio dele quanto para defeito seu. Quem decide é o **corpo**.
3. **Escreva como se cada chamada pudesse ser a segunda.** Rede corta no meio de saga de três
   passos. Sem guarda de idempotência, retomar é duplicar — e desduplicar ocorrência na fila do
   RH é trabalho de gente.

## 0. Os identificadores, e de onde eles vêm

Nada disso se deduz, e nada disso se chumba no código de regra:

| O quê | Exemplo | De onde |
|---|---|---|
| `base-url` | `https://sgo.basis.com.br` | configuração |
| `project-id` | numérico, do projeto de destino | configuração |
| `issue-type-id` | `3` = Tarefa, no uso mais comum | configuração |
| `grid-id` do TableGrid | **é o próprio id do customfield** do grid | configuração |
| id de customfield | `customfield_12259` | catálogo lido do `createmeta` |
| id de opção de lista | `54646` | catálogo lido do `createmeta` |

As duas últimas linhas são as que mais custam quando erram, e são as únicas que **nunca** podem
morar em constante: as opções são editadas pelo RH sem release nenhum do seu lado.

O `gridId` ser o id do customfield foi inferência do judge-admin antes de ser fato: o spike de
2026-08-19 confirmou chamando. Anote como confirmado, não como óbvio.

## 1. O cliente

Java, Spring: interface `@HttpExchange` + `RestClient`, um bean só, sem SDK.

```java
@Bean
SgoClient sgoClient(SgoProperties props) {
    // HTTP/1.1 explícito: o cliente do JDK negocia HTTP/2 por padrão, e um Jira 6.3.13 é de
    // antes do HTTP/2 -- a negociação não compra nada e custa uma tentativa de upgrade por
    // conexão. Fixá-la também tira do caminho uma classe de falha de protocolo.
    var http = HttpClient.newBuilder().version(HttpClient.Version.HTTP_1_1).build();
    var factory = new JdkClientHttpRequestFactory(http);
    factory.setReadTimeout(props.readTimeout());          // 90s é o ponto de partida usado

    var builder = RestClient.builder()
            .baseUrl(props.baseUrl())
            .requestFactory(factory)
            // Exigido pelo Jira no envio de anexo; inócuo nas demais chamadas, então é default.
            .defaultHeader("X-Atlassian-Token", "no-check");

    if (props.temCredencial()) {
        var codificada = Base64.getEncoder().encodeToString(
                (props.username() + ":" + props.password()).getBytes(StandardCharsets.UTF_8));
        builder.defaultHeader(HttpHeaders.AUTHORIZATION, "Basic " + codificada);
    } else {
        // Diga isto no arranque. Ver §2: sem credencial, várias chamadas respondem 200 e mentem.
        log.warn("SgoClient sem credencial: só leitura anônima funciona");
    }
    ...
}
```

Python: `ks-jira` (`libs/ks-jira` do kaizenstat) devolve um `JIRA` autenticado a partir de
`KS_SGO_USER`/`KS_SGO_PASSWORD`, e **devolve `None` quando falta credencial** em vez de estourar
— quem chama precisa tratar isso, e o padrão é adiar o trabalho, não segui-lo em silêncio.

O que a biblioteca `jira` não expõe (`notifyUsers`, endpoints do iGrid) sai por
`jira_client._session`, que é a sessão `requests` autenticada dela. É privado e é o caminho
aceito na casa; ver [`references/cliente-python.md`](references/cliente-python.md).

Detalhe de configuração: no Spring, o prefixo `application.sgo.*` já ganha sobreposição por
`APPLICATION_SGO_*` via relaxed binding — não escreva `${VAR}` no yaml para isso.

## 2. Sem credencial, o SGO responde — e responde errado

Este é o achado que mais engana, e está medido:

| Chamada | Anônima | O que volta |
|---|---|---|
| `GET /rest/api/2/issue/createmeta` | responde | `200`, catálogo inteiro. Num projeto público de criação, funciona de verdade |
| `POST /rest/api/2/search` | responde | **`200` com `total: 0`** — não é "não existe", é "não tenho permissão de enxergar" |
| `POST /rest/api/2/issue` | recusa | erro de permissão |
| `GET /rest/api/2/issue/{k}/editmeta` | responde | a ocorrência **sem** `fields` |

A linha do meio é a perigosa. Uma verificação de duplicidade que pergunta ao SGO sem credencial
recebe "está livre" com a convicção de um `200`, e o usuário só descobre a duplicidade na recusa
do envio. **Se a sua consulta depende de permissão, cheque `temCredencial()` antes de perguntar,
e registre no arranque se a verificação está ativa ou desligada** — uma senha rotacionada vira
uma verificação que parou de verificar, e nada na tela muda.

## 3. O catálogo: id de opção nunca no código

O SGO grava **id numérico** (`54646`), não rótulo (`Access/Libreoffice Base`). A tradução
rótulo→id é de um módulo só, alimentado pelo `createmeta` em runtime.

```
GET /rest/api/2/issue/createmeta
      ?projectIds=<projeto>&issuetypeIds=<tipo>&expand=projects.issuetypes.fields
```

Quatro coisas que só se descobrem lendo essa resposta de verdade — todas em
[`references/campos-e-payload.md`](references/campos-e-payload.md):

- **As cascatas vêm inteiras e aninhadas**: cada pai traz `children` com id e rótulo.
- **`required` por campo é a autoridade sobre obrigatoriedade** — mais confiável que procurar
  "Obrigatório" no HTML da tela.
- **Não existe `disabled`.** Opção que o RH desabilitou continua no `createmeta`, e nenhum
  endpoint da API expõe esse estado. Um formulário construído a partir dele oferece opções
  desativadas junto com as ativas, e a única saída é uma lista de exclusão em configuração —
  dívida assumida, com teste que fixa a lista para a próxima divergência aparecer.
- **Rótulo tem lixo de digitação**, inclusive espaço não-quebrável (`U+00A0`) no meio. Daí a
  regra: **persista o `id` da opção, nunca o rótulo.** Rascunho salvo com rótulo normalizado pela
  tela não volta a casar com a origem, e a tradução falha em silêncio num campo obrigatório.

E o catálogo **envelhece**: entre duas capturas do mesmo `createmeta` em três dias já mudaram
contagem de opções, obrigatoriedade de treze campos e a lista de filhas de uma cascata. Versione
a fixture com a data da captura no nome e deixe o teste cobrar as **contagens daquela captura**:
o teste vermelho é o aviso de que o RH mexeu.

## 4. A forma do valor no payload

O tipo do campo no Jira decide a forma, e errar a forma é `400` na cara — ou, pior, campo
gravado vazio.

| Tipo no Jira | Forma no `fields` |
|---|---|
| `textfield`, `textarea` | `"texto"` |
| `datepicker` | `"yyyy-MM-dd"` |
| `float` | `1234.56` — número, nunca `"R$ 1.234,56"` |
| `select`, `radiobuttons` | `{"id": "…"}` |
| `multiselect`, `multicheckboxes` | `[{"id": "…"}]` — array **mesmo com uma opção só** |
| `cascadingselect` | `{"id": "pai", "child": {"id": "filho"}}` — a cascata inteira num campo só |
| `tableGridCFType` | não vai no `fields`: tem endpoint próprio (§6) |
| `scripted-field`, `message` | **não graváveis**; nunca entram no payload |

**Campo nulo não entra no payload.** A obrigatoriedade já foi cobrada na submissão, com a lista
que veio do próprio Jira; repetir a cobrança na montagem cria uma segunda verdade que diverge da
primeira na próxima mudança do RH.

## 5. As três formas de data, no mesmo sistema

| Onde | Formato | Exemplo |
|---|---|---|
| customfield `datepicker` | ISO local | `1985-03-01` |
| customfield de data-hora | ISO com milissegundos e offset **sem dois-pontos** | `2026-04-07T14:58:24.000-0300` |
| coluna de data do **TableGrid** | milissegundos de época | `478494000000` |

As duas primeiras convivem no mesmo `PUT`; a primeira e a terceira convivem no mesmo envio.
Trocá-las de lugar é `400` — e o `400` é o desfecho bom.

O ruim é o fuso. **O servidor renderiza os milissegundos do grid no fuso dele.** Meia-noite
calculada em UTC aparece como 21h do dia anterior: a data anda um dia para trás, em silêncio, sem
erro em lugar nenhum, num campo que alguém vai usar para contar tempo. Por isso o fuso é
**parâmetro de configuração** (`America/Sao_Paulo`, confirmado pelo offset do `serverInfo`) e
nunca `ZoneId.systemDefault()`: a máquina onde a sua aplicação roda não tem nada a ver com o fuso
do Jira.

## 6. TableGrid (plugin iGrid)

```
GET  /rest/idalko-igrid/1.0/grid/{gridId}/issue/{issueId}
POST /rest/idalko-igrid/1.0/grid/{gridId}/issue/{issueId}
     {"rows": [{"<coluna>": "<valor>", …}]}
```

O `issueId` é o **id numérico** da ocorrência, não a chave `PROJ-123`. As colunas se chamam pelo
nome da configuração do grid (`gd.columns=empresa,funcao,cargo,entrada,saida,tempoMeses`), e
coluna definida mas fora de `gd.columns` não é coluna ativa: não entra no payload.

Duas assimetrias que custam tempo:

- **A resposta de leitura vem ora em `values`, ora em `rows`**, conforme a versão do plugin. Leia
  os dois.
- **O que se escreve é escalar; o que volta é objeto.** Você manda `{"perfil": "Desenvolvedor"}`
  e relê `{"perfil": {"value": "Desenvolvedor"}}`. Código que roundtripa precisa saber disso.

Vazio na leitura tem de ser distinguível de falha: devolver `[]` num erro de rede faz uma queda
do Jira parecer "ocorrência sem linhas", e a rotina termina como sucesso silencioso.

## 7. Anexos

`POST /rest/api/2/issue/{chave}/attachments`, multipart, campo `file`, **um arquivo por
chamada**, com `X-Atlassian-Token: no-check`.

- **`200` com array vazio existe e significa que nada chegou.** Dar isso por enviado conclui a
  saga com a ocorrência sem os arquivos, e ninguém descobre até alguém abrir a ocorrência.
- O nome do arquivo atravessa um **cabeçalho** de multipart. Ele é entrada de usuário: higienize
  antes, ou um caractere de controle quebra o parser do Jira. Nome com acento em servidor dessa
  idade é o ponto em que a codificação costuma discordar — vale conferência manual.
- **O Jira 6 não devolve hash de anexo.** Se você precisa provar integridade, confira o SHA-256
  **antes de subir**, contra o hash registrado no recebimento. Depois não dá.
- Para saber o que já está lá sem trazer a ocorrência inteira de volta pela rede:
  `GET /rest/api/2/issue/{chave}?fields=attachment`. Numa ocorrência que guarda dado pessoal,
  isso não é economia de banda, é §11.

## 8. Sucesso não é `200`

A classificação é **pelo corpo**, nunca pelo código HTTP sozinho:

| Resposta | Classe | O que fazer |
|---|---|---|
| `400` com `errorMessages` | permanente | Regra de negócio do Jira, dirigida a quem usa. **A mensagem dele é melhor que qualquer texto seu** — preserve e mostre |
| `400` com `errors` por campo | permanente **+ alerta** | Defeito seu de mapeamento: nenhuma chamada seguinte vai passar. Registre em nível de erro, nomeando **os campos, nunca os valores** |
| `401` / `403` | **transitório** + alerta | A credencial quebrou; alguém vai renovar. Descartar aqui perde trabalho por problema de operação |
| `404` | permanente + alerta | Projeto ou ocorrência sumiu — é sobre todas as chamadas, não sobre esta |
| `429` | transitório | Diminua o ritmo |
| `5xx`, timeout, conexão | transitório | Backoff exponencial |
| `200` **com corpo de erro** | permanente | O Jira faz isso. Sem conferir, um envio recusado passa por bem-sucedido |
| corpo que não é JSON | permanente + alerta | HTML de proxy ou página de erro. Quem classifica falha não pode falhar: engula a exceção do parse e classifique |

`401` como transitório é deliberado e contraintuitivo — está aqui porque a alternativa perde
dado. E `permanente` e `alertar` são **eixos diferentes**: um `401` é transitório e merece
alerta; um `400` com `errorMessages` é permanente e não merece nenhum.

## 9. Escrever num SGO que todos os ambientes compartilham

Não existe SGO de homologação. Duas aplicações da Basis chegaram à mesma necessidade por
caminhos diferentes, e as duas soluções valem:

**A chave que desliga a escrita — checada em runtime, nunca por `@ConditionalOnProperty`.** A
condição do Spring é avaliada uma vez só e, em imagem nativa, essa vez é o **build**: o
`process-aot` roda sem perfil e sem variável de ambiente, o `matchIfMissing` vale, o bean entra
congelado na imagem e a chave deixa de ter efeito em runtime. Medido em 2026-08-21 numa imagem
nativa: com a chave em `false`, o agendador rodou assim mesmo — e na JVM não rodava. **Uma
proteção que some conforme o formato do artefato é pior que proteção nenhuma**, porque ninguém
desconfia dela. O bean sempre sobe; quem decide é o método.

**O ensaio que grava tudo menos no Jira.** No lado Python, a rotina persiste o que faria com
status `suppressed` — corpo, chave de deduplicação, tudo revisável em tabela, e inerte por
construção: nenhuma rotina de entrega o seleciona. Publicar o que foi ensaiado é um ato
deliberado com log próprio, não um `UPDATE` à mão. Duas marcas distintas nos logs (`[DRY RUN]` e
`[JIRA DRY RUN]`) porque os dois modos deixam estados muito diferentes para trás.

**E, quando é inevitável escrever de verdade:**

- Combine antes com quem é dono da fila, e avise no fim.
- Marque de forma inconfundível (`[TESTE — IGNORAR]`) **num campo que a post-function não
  reescreva** — se você marcar o `summary` e uma post-function o substituir, a ocorrência de
  teste fica indistinguível de uma real. Aconteceu: uma ficou três dias na fila do RH assim.
- Procure a marca **em qualquer posição** do campo ao decidir se pode editar, não só no começo.
- Prefira **reusar uma ocorrência de teste** a criar outra: a fila não ganha linha nova.
- Ponha a trava no código, não no procedimento: leia o campo antes de escrever e **recuse-se a
  editar** ocorrência sem a marca. Um `PUT` na ocorrência errada mexe no cadastro de uma pessoa
  real, e esse erro não tem desfazer.
- Se um profile hospeda mais de um roteiro, **nenhum é o padrão**. Exija o argumento; sem
  argumento reconhecido, não faça nada e diga o que digitar.

## 10. Retomar sem duplicar

Criar a ocorrência, escrever o grid e subir os anexos são **chamadas que falham de forma
independente**. Sem estado por etapa, retomar é recomeçar, e recomeçar depois da primeira é criar
a segunda ocorrência.

A guarda certa depende da etapa, e não é a mesma em todas:

| Etapa | Guarda | Por quê |
|---|---|---|
| criar a ocorrência | **a chave persistida do seu lado** | Nunca pergunte ao SGO "já existe um registro dessa pessoa": quem responde isso é a regra de unicidade dele |
| escrever o grid | "tem linha?", e não "tem estas linhas?" | O conjunto vai de uma vez; comparar linha a linha resolve um problema que não existe |
| subir anexos | **pergunte ao SGO o que já está lá** | São N chamadas: uma queda no meio deixa parte no destino, e estado próprio não basta |

A comparação de anexos é **contagem** por nome e tamanho, não conjunto: dois arquivos de mesmo
nome e mesmo tamanho dariam os dois por presentes depois de subir o primeiro.

Do lado Python o mesmo problema tem outra forma — **outbox**: grave a intenção antes de tentar,
reivindique a linha (`sending`, tentativa contada, commitada) **antes** da chamada, e registre o
desfecho depois. Uma queda no meio deixa reivindicação visível, retentada após carência. Pode
duplicar um envio, e isso é aceito: *at-most-once não existe sobre HTTP*. A chave de deduplicação
é **identidade de negócio**, não hash do corpo.

Duas escritas no Jira não compartilham transação. Se um comentário precisa da chave de uma
ocorrência criada por outra ação, isso é **dependência declarada em dado**, não duas chamadas na
mesma respiração.

E teto de tentativas: **parar de tentar não é descartar.** Descartar diz ao usuário que o pedido
dele foi recusado quando ele está na fila. Pare, alerte, e deixe alguém mandar tentar de novo —
"está tentando sozinho" e "parou e espera alguém" pedem ações opostas de quem olha o painel.

## 11. O dado que passa por aqui é pessoal

Ocorrência de RH tem CPF, RG, endereço e telefone dentro. Isso não é observação genérica de LGPD;
é uma lista de coisas que já quase deram errado:

- **Nenhum log imprime corpo de requisição.** Um `log.debug("payload: {}", …)` escrito com pressa
  vaza o cadastro inteiro para onde muito mais gente lê do que o banco.
- **Busca com dado pessoal vai por `POST`, nunca `GET`.** A JQL num `GET` põe o CPF na URL — log
  de acesso do Jira, histórico do navegador, qualquer proxy no caminho.
- **Não registre a mensagem da exceção de uma busca**: um `400` por JQL malformada **devolve a
  JQL no corpo**, e a JQL tem o CPF dentro. Este é o caminho que ninguém pensa em conferir.
- Ao classificar `errors` por campo, nomeie **os campos**, nunca os valores recusados.
- `maxResults: 0` quando a pergunta é "existe?": trazer a ocorrência traz dado de outra pessoa.
- **Mascarar não é anonimizar.** Devolver `j***@gmail.com` para quem digitou um CPF confirma a
  inicial e o provedor de alguém a quem essa pessoa pode não ter acesso. Use como destino, não
  renderize.
- A credencial fica em arquivo **fora do versionado** (no Spring, `./config/`, com `/config/` no
  `.gitignore`) — e confira com `git check-ignore` antes do primeiro commit, não depois.
- Confira o que a conta de serviço pode: `GET /rest/api/2/mypermissions?issueKey=…`. Uma conta
  que só precisa criar ocorrência e anexar arquivo não precisa de `ADMINISTER` nem de
  `DELETE_ISSUE`, e credencial de aplicação exposta na internet é onde isso importa.

## 12. Assinatura — sintoma e causa

| Sintoma | Causa provável | Onde |
|---|---|---|
| `400 Field cannot be set. It is not on the appropriate screen, or unknown.` | Campo válido, mas fora da tela **de edição** — ou apagado. A mesma mensagem para os dois casos | §3, `editmeta` |
| `400 The date and datetime column value has to be a number (milliseconds)` | Mandou ISO ou `dd/mm/yy` numa coluna de data do TableGrid | §5 |
| A data do grid aparece um dia antes | Milissegundos calculados em UTC, renderizados no fuso do servidor | §5 |
| `200`, mas nada foi criado | Corpo de erro num `200` | §8 |
| `POST` de anexo passa e o arquivo não está lá | Resposta `200` com array vazio | §7 |
| A busca diz que não existe, e existe | Consulta sem credencial: `200` com `total: 0` | §2 |
| A busca não acha o registro que você acabou de gravar | O `~` da JQL é sensível à pontuação: `123.456.789-00` e `12345678900` são buscas diferentes. Busque as duas formas com `OR` | §11 |
| Campo obrigatório gravou vazio, sem erro nenhum | Rótulo que não resolveu para id e foi omitido em silêncio | §3 |
| O `summary` da ocorrência não é o que você mandou | Post-function de transição reescreve. **Não roda no `edit`** | §9 |
| Ocorrência duplicada na fila | Retomada sem guarda de idempotência na etapa 1 | §10 |
| Opção desativada aparecendo no formulário | O `createmeta` não expõe `disabled` | §3 |
| A chave de desligar escrita não faz efeito na imagem nativa | `@ConditionalOnProperty` avaliado no `process-aot` | §9 |
| Ocorrência de teste indistinguível das reais | Marca posta num campo que a post-function reescreve | §9 |
| Um `SELECT` no PostgREST do SGO devolve município que não existe na sua carga | A lista do SGO não é lista de municípios: mistura distritos, e traz erro de cadastro | `references/campos-e-payload.md` |

## O que engana

- **"O `createmeta` é a verdade sobre o que dá para gravar."** É a verdade sobre a tela de
  **criação**. A tela de edição é outra lista, e só o `editmeta` responde por ela.
- **"Se `createmeta` respondeu, a credencial está boa."** Ele responde anônimo. §2.
- **"O `400` é do usuário."** Metade é sua. Só o corpo separa.
- **"Retentar é inofensivo."** Depois que a ocorrência existe, retentar do zero é destrutivo.
- **"Grid é campo."** Tem endpoint próprio, plugin próprio, formato de data próprio e forma de
  leitura diferente da de escrita.
- **"`notifyUsers=false` resolve o e-mail."** É privilégio de administrador no Jira Server. O
  lado Python usa esse parâmetro em produção nos `PUT` de correção — trate como caminho conhecido,
  e confirme na sua conta antes de contar com ele. Sem ele, **toda edição notifica quem observa a
  ocorrência**: um fluxo de atualização manda e-mail a cada retomada.
- **"Staging escreve em staging."** Não existe staging. §9.

## Checklist

**Antes da primeira escrita de uma aplicação nova**

- [ ] `project-id`, `issue-type-id` e `grid-id` em configuração, não em constante
- [ ] Credencial fora do versionado, e `git check-ignore` conferido
- [ ] `mypermissions` lido: a conta pode o que precisa, e não muito mais
- [ ] Catálogo lido do `createmeta` em runtime; nenhum id de opção no código
- [ ] Fixture do `createmeta` versionada com a data no nome, e teste cobrando as contagens
- [ ] A chave que desliga a escrita é checada **em runtime**, e testada no artefato que vai rodar
- [ ] Nenhum log imprime payload, JQL nem mensagem de exceção de busca

**Antes de rodar contra o SGO de verdade**

- [ ] Combinado com quem é dono da fila
- [ ] Marca de teste num campo que a post-function não reescreve
- [ ] Ocorrência de teste reusada, não criada
- [ ] O roteiro exige argumento explícito; sem ele, não faz nada

**Ao revisar uma integração existente**

- [ ] `200` é conferido pelo corpo antes de contar como sucesso
- [ ] Cada etapa tem guarda de idempotência, e a guarda certa para aquela etapa
- [ ] Esgotar tentativas alerta e **não** descarta
- [ ] Datas: os três formatos no lugar certo, e o fuso vindo de configuração

## References

- [`references/campos-e-payload.md`](references/campos-e-payload.md) — `createmeta` na prática:
  cascatas, obrigatoriedade, opções desabilitadas, rótulos com lixo, a tabela tipo→forma, os três
  formatos de data e por que o PostgREST do SGO não substitui uma carga própria.
- [`references/tablegrid-igrid.md`](references/tablegrid-igrid.md) — o plugin iGrid: formato da
  configuração do grid, leitura vs escrita, `values`/`rows`, e as guardas de idempotência.
- [`references/cliente-java.md`](references/cliente-java.md) — a interface `@HttpExchange`
  anotada, o `RestClient`, `@ConfigurationProperties`, e a saga com estado por etapa.
- [`references/cliente-python.md`](references/cliente-python.md) — `ks-jira`, o que a biblioteca
  `jira` cobre, quando descer para `_session`, webhooks do Jira e o outbox transacional.
- [`references/falhas-e-retry.md`](references/falhas-e-retry.md) — a classificação linha a linha,
  backoff, o que alertar, e o que "parar sem descartar" quer dizer no estado.
