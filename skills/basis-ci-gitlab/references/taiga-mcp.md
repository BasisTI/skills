# O Taiga pelo servidor MCP

O servidor MCP `taiga` dá ao agente acesso aos boards. O uso principal no fluxo é **ler a
user story antes de nomear a branch e escrever o commit** — em vez de pedir o número a quem
já está com o card aberto.

As ferramentas aparecem como `mcp__taiga__*`. Se não estiverem disponíveis, o servidor não
está configurado nesta máquina: **pergunte, não contorne**. Não invente id de story nem de
projeto.

## Estados da User Story

### Nomes vêm do board

Cada projeto define os seus status. Leia `taiga_projects_get` → `us_statuses` e use o
`name` e o `id` que estão lá. O board do Ponto (id 35), por exemplo, grafa `In progress` e
`Ready for test`; um nome escrito de memória com outra caixa não casa. Nesta página, os
nomes designam **etapas**; a grafia vale a do board — é ela que se usa nos exemplos.

### Onde ficam os registros

Dois momentos da story precisam deixar rastro verificável, porque o git não os prova: o
**registro de início** (alguém começou de fato) e o **registro de teste** (alguém testou em
staging). O lugar certo para eles são **campos customizados da User Story**, definidos por
projeto no Taiga, que guardam dado estruturado em vez de texto solto:

| Campo customizado | Tipo | Quem grava |
|---|---|---|
| `Início da implementação` | data | executor, ao começar |
| `Executor` | texto (agente + modelo, ou pessoa) | executor, ao começar |
| `Worktree` | texto (branch e caminho) | executor, ao começar |
| `Testado em staging` | sim/não | quem testou (ou quem orquestra, a pedido explícito dessa pessoa) |
| `Testado por` | texto | quem testou |
| `Data do teste` | data | quem testou |

Bloqueio usa o campo nativo da story, `is_blocked` + `blocked_note`. O registro de início
também **acrescenta** o executor em `assigned_users`, a lista de responsáveis, mantendo quem
já estava. Não use o `assigned_to` do `taiga_stories_update` para isso: ele troca o
responsável principal, e na US #14 do `plataforma-iac` a pessoa dona do card saiu dele sem
aviso (`[6]` virou `[166]`).

A mudança de status acompanha o registro, mas **o status nunca é evidência do registro**:
uma story arrastada de volta para `Ready` com `Início da implementação` preenchido continua
com início registrado. O resto desta página diz "registro de início" e "registro de teste".

**Registros valem para uma versão.** O registro de teste se refere à versão testada; quando
a story é reaberta depois de uma entrega, quem reabre volta `Testado em staging` para "não",
porque a próxima versão ainda não foi testada. O bloqueio de uma story interrompida se desfaz
ao retomá-la ([abaixo](#retomar-story-bloqueada)).

### Gravar e ler os registros pela API do Taiga

**O MCP ainda não cobre isso**: não lê os valores dos campos, o `custom_attributes` do
`taiga_stories_update` vai no `PATCH` da story (e não no recurso de valores), e `is_blocked`
não é exposto. Enquanto for assim, os registros vão direto pela API REST do Taiga, com a
mesma conta de serviço do servidor MCP (as variáveis `TAIGA_BASE_URL`, `TAIGA_USERNAME` e
`TAIGA_PASSWORD` da configuração dele). Onde essa configuração fica na máquina vem do
`AGENTS.md` ou de quem pediu — pergunte. O valor da senha e o token não vão para log,
comentário, commit nem relatório.

Carregue a credencial com `source scripts/taiga-env.sh <arquivo>`: ele lê tanto a lista de
ambiente de um `compose.yaml` (`- TAIGA_USERNAME=...`) quanto um `.env`, exporta as três
variáveis e lista só os nomes. Não escreva um parser na hora, e não use `cat`, `grep` ou
`env` para conferir — isso imprime a senha.

```bash
source scripts/taiga-env.sh <arquivo>      # caminho da skill; o arquivo vem do AGENTS.md
API="${TAIGA_BASE_URL%/}/api/v1"
TOKEN=$(jq -n --arg u "$TAIGA_USERNAME" --arg p "$TAIGA_PASSWORD" '{type:"normal",username:$u,password:$p}' \
  | curl -s -X POST -H 'Content-Type: application/json' -d @- "$API/auth" | jq -r .auth_token)
H=(-H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json')

# definições do projeto: id, nome e tipo de cada campo
curl -s "${H[@]}" "$API/userstory-custom-attributes?project=<project_id>" | jq '.[] | {id, name, type}'

# valores da story: {"attributes_values": {"<id do campo>": valor}, "version": n}
curl -s "${H[@]}" "$API/userstories/custom-attributes-values/<story_id>"

# gravar: o dicionário inteiro, com o version que acabou de ler
curl -s -X PATCH "${H[@]}" "$API/userstories/custom-attributes-values/<story_id>" \
  -d '{"attributes_values": {"<id>": "<valor>", ...}, "version": <n>}'

# responsáveis: a lista atual mais o executor (version da story)
curl -s "${H[@]}" "$API/userstories/<story_id>" | jq '{assigned_users, version}'
curl -s -X PATCH "${H[@]}" "$API/userstories/<story_id>" \
  -d '{"assigned_users": [<atuais>, <executor>], "version": <n>}'

# bloqueio, na própria story (version da story, não o dos valores)
curl -s -X PATCH "${H[@]}" "$API/userstories/<story_id>" \
  -d '{"is_blocked": true, "blocked_note": "<causa>", "version": <n>}'
```

Tudo acima foi exercitado na instância da Basis: as leituras (projeto 35, story 1063) e a
gravação dos valores (`plataforma-iac`, US #14, 2026-09-27: `version` 1→2, dicionário relido
igual); o `PATCH` de `assigned_users` e o de bloqueio (`plataforma-iac`, US #15, 2026-09-28).
A API devolve `assigned_users` em outra ordem (`[6, 166]` gravado, `[166, 6]` relido) e não
mexe no `assigned_to`: o que se confere é quem está na lista, não a ordem. A mudança de
status pelo MCP também sobe o `version` da story — leia de novo antes do `PATCH` seguinte.
Duas regras valem para todas as escritas:

- **Leia antes de gravar, e grave o dicionário inteiro.** O `version` é controle de
  concorrência: com o valor velho, a API recusa, e a resposta certa é ler de novo, não
  forçar. Mandar só a chave alterada arrisca apagar os outros campos.
- **Confira depois.** Releia os valores e confirme que o campo gravado está lá.

**Projeto sem os campos definidos** — o caso do Sistema de Ponto em 2026-09-27
(`userstory_custom_attributes: null`) — não tem onde registrar. Isso não autoriza trocar o
registro por tag ou por texto na descrição: reporte e pergunte.

### Preparar o board de um projeto

`scripts/configurar-taiga-projeto.sh <project_id>` cria o que o fluxo espera: os status
opcionais `In revision` (depois de `In progress`) e `Waiting for deployment` (depois de
`Ready for test`), pelo `userstory-statuses`, e os seis campos da tabela acima, pelo
`userstory-custom-attributes`. Sem `--apply` ele só mostra o plano; com `--apply` grava,
reordena os status e relê o resultado da API. É idempotente: o que já existe com o mesmo
nome fica como está. Aplicado primeiro no `plataforma-iac` (id 90) em 2026-09-27: status 657
e 658, campos 27 a 32; a segunda execução respondeu "nada a fazer".

Configurar o board é mudança visível para o time inteiro: rode o plano, mostre-o a quem
pediu e só então aplique. Exige `admin_project_values` no projeto, que a conta de serviço
do MCP normalmente não tem — o script confere antes de gravar e recusa (saída 3); nesse
caso quem aplica é um admin do projeto, com a própria credencial em `TAIGA_TOKEN` ou
`TAIGA_USERNAME`/`TAIGA_PASSWORD`. Board sem os status âncora (`in-progress`,
`ready-for-test`) é board fora do padrão: o script para (saída 4) em vez de adivinhar onde
encaixar. Os tipos dos campos são os do Taiga (`text`, `date`, `checkbox`); a hora exata do
início fica no histórico da story.

### Critérios de transição (quando mover)

| Para | Quando |
|---|---|
| `New` | A ideia existe; a especificação ainda precisa ser fechada |
| `Ready` | Especificação concluída: critérios de aceitação presentes |
| `In progress` | O executor começou de fato: registro de início feito. Commits não são exigidos |
| `In revision` *(opcional)* | MR devolvida para revisão ([`ciclo-da-mr.md`](ciclo-da-mr.md)); volta a `In progress` se a revisão tiver achados ([`revisao-da-mr.md`](revisao-da-mr.md)) |
| `Ready for test` | Staging roda a versão |
| `Waiting for deployment` *(opcional)* | Staging roda a versão **e** registro de teste presente; produção ainda não roda a versão |
| `Done` | Registro de teste presente **e** produção roda a versão |

"A versão", em todos os critérios, é a da MR `TG-xx` mais recente. Com uma MR aberta, a story
tem trabalho em andamento, e uma entrega anterior da mesma story não satisfaz `Ready for
test` nem os seguintes.

"Roda a versão" é a cadeia de entrega completa no ambiente — commit do merge, pipeline,
tag, overlay e pods —, descrita em [`cadeia-de-entrega.md`](cadeia-de-entrega.md). Tag
publicada no registry não basta.

**Projeto sem staging.** Há projeto que não tem ambiente de teste da própria aplicação — o
`plataforma-iac` roda só no cluster `infra`, com as tags de produção. O `AGENTS.md` do
projeto diz qual ambiente faz papel de staging (linha `Staging` da tabela de identidade, §0
do `SKILL.md`) ou que não há. Sem staging, "staging roda a versão" não se verifica e não se
presume: `Ready for test` e `Waiting for deployment` usam o critério de produção — a story
vai a `Ready for test` quando produção roda a versão, e a `Done` com o registro de teste.
`AGENTS.md` sem a linha `Staging` não diz nem uma coisa nem outra: pergunte, e aponte no
relatório a linha que falta.

**Sem os opcionais.** Boards que não têm `In revision` nem `Waiting for deployment` — é o
caso comum hoje — caem nos status existentes: `In progress` vai até staging rodar a versão,
e `Ready for test` vai até `Done`. Todo critério tem para onde ir.

**Transição pendente.** Entre o merge e staging rodar a versão, a story fica no status
anterior (`In revision`, ou `In progress` sem ele). Não é um estado novo; a auditoria reporta
"transição pendente: aguardando staging".

**`Done`, fechado e arquivado são coisas diferentes, e o board decide duas delas.** Cada
status em `us_statuses` traz `is_closed` e `is_archived`. No Sistema de Ponto, `Done` tem
`is_closed: true` — mover para `Done` já fecha a story, por configuração do board — e há um
status `Archived` com `is_archived: true`. O que esta página controla é só o critério para
mover para `Done`; mover para um status arquivado, ou usar `taiga_stories_archive_or_close`,
é só a pedido.

### Mudança de configuração (tag `config`)

Story com a tag `config` é mudança **sem efeito no comportamento da aplicação**, e por isso
não passa pelo teste em staging. Exemplos:

- versão do template de CI ou do orchestrator, e o `ci/pipeline.toml`;
- skills versionadas no repositório, `AGENTS.md` e documentação;
- arquivos do fluxo de trabalho local, como `.worktreeinclude` e `.config/wt.toml`;
- segredos locais fora do Git: a TG-31 do `plataforma-iac` trocou o `.env.example` por
  `config/application-gitlab.yml` ignorado pelo Git, com `.gitignore`, README e só
  comentários nos `application*.yml`.

**Não é `config`** tudo o que mexe em código da aplicação — inclusive uma classe
`@Configuration` do Spring —, um **valor** num `application*.yml` empacotado com a
aplicação, ou uma dependência no `pom.xml`: isso muda o comportamento e segue o fluxo
completo. Na dúvida, não é `config`. A tag é classificação posta por quem escreve a story; o executor que discordar
reporta, em vez de trocar a tag.

O que muda no fluxo:

| Etapa | Com a tag `config` |
|---|---|
| Worktree, branch `TG-xx`, MR com squash para `develop` | Igual: o arquivo continua no repositório |
| Registro de início, ciclo da MR até a devolução | Igual |
| Registro de teste, `Ready for test`, `Waiting for deployment` | Não se aplicam |
| `Done` | MR mergeada **e** a primeira pipeline de `develop` que contém o merge terminou verde — a prova de que a configuração nova não quebrou a pipeline |

### Revisão global (tag `review`)

Story com a tag `review` pede uma revisão com o `qa-adversarial` sobre código **já
mergeado** — um módulo, um período, MRs que entraram sem a
[revisão da MR](revisao-da-mr.md). O entregável é o relatório de achados, não código: sem
branch `TG-xx` para escrever, sem commits e sem MR.

- **Escopo** vem da descrição da story: o que revisar (módulo, MRs, intervalo de commits).
  O revisor lê um worktree próprio no SHA de `origin/develop` que revisa (`git worktree add
  --detach ../<repo>.TG-xx <sha>`) e registra esse SHA no relatório.
- **Harness, modelo e esforço** se escolhem como na revisão da MR: vêm de quem pediu, ou se
  pergunta.
- **O relatório vai num comentário da story**, pela API (campo `comment` no `PATCH` da
  story, com o `version` relido — ainda não exercitado: confira relendo a story). Achados
  numerados (`R1`, `R2`, …) no formato do `qa-adversarial`, do mais grave ao menos, com o SHA
  revisado e a seção `O que tentei e não quebrou`.
- **A triagem é humana.** Quem pediu escolhe os achados a implementar, como dividi-los em
  stories e em que prioridade. Depois da triagem, o agente pode criar as stories, com a
  confirmação de [escrita em board](#escrita-em-board-compartilhado): cada uma cita a US de
  revisão e os achados que cobre, e segue o fluxo do tipo dela — nunca a tag `review`.

| Status | Critério |
|---|---|
| `Ready` | Escopo da revisão definido na descrição |
| `In progress` | Registro de início |
| `Ready for test` | Relatório publicado na story; aguarda a triagem |
| `Done` | Triagem feita: cada achado tem destino no comentário da triagem — story criada (link), agrupado em outra, ou descartado com o motivo |

Registro de teste, staging e produção não se aplicam, e `In revision` e `Waiting for
deployment` não são usados. O worktree de leitura sai com `git worktree remove` quando o
relatório é publicado.

### Regras de auditoria (conferir se o status está certo)

Auditar é comparar o status atual da story com o que as evidências dizem que ele deveria
ser.

- **Precedência.** Avalie do mais avançado para o menos: `Done`, `Waiting for deployment`,
  `Ready for test`, `In revision`, `In progress`, `Ready`, `New`. O primeiro critério
  satisfeito é o status esperado. Status opcional que o board não tem sai da lista.
- **Story com a tag `config`** segue a tabela da seção dela: sem registro de teste nem
  staging, e `Done` pela MR mergeada com a pipeline de `develop` verde.
- **Story com a tag `review`** segue a tabela da seção dela: `Ready for test` pelo
  relatório publicado, `Done` pela triagem com destino para cada achado.
- **Story em status arquivado** (`is_archived: true`, como o `Archived` do Ponto) fica fora
  da auditoria de transição: alguém a tirou do fluxo de propósito. Reporte o status, sem
  recomendar movê-la.
- **`Ready` exige ausência de trabalho, não ausência de commits:** sem registro de início e
  sem MR `TG-xx`, aberta ou mergeada. A branch apagada depois do merge não devolve a story a
  `Ready` — a MR mergeada continua lá.
- **Registro de início sem commits é `In progress`.** O executor pode estar lendo, testando
  hipótese, ou ter sido interrompido antes do primeiro commit. Nunca recomende regressão a
  `Ready` por falta de commits.
- **MR `TG-xx` sem registro de início também é trabalho.** Alguém começou sem registrar: o
  esperado é `In progress` (ou mais avançado, pelos outros critérios), e o relatório aponta
  o registro que falta.
- **Entregue pela MR de outra story.** Sem MR `TG-xx` própria, procure também MRs que citem
  a story no título ou na descrição (`#xx`, `TG-xx`): `glab mr list --search TG-xx --all` e
  `--search "#xx"`. Achando, reporte "entregue por TG-yy, a confirmar" com a cadeia da MR
  achada, sem inferir o status — quem decide é a pessoa. Foi o caso da US #12 do
  `plataforma-iac`, entregue pela TG-11 e auditada como `Ready` pela regra estrita.
- **Worktree sem registro de início não conta.** O orquestrador prepara worktrees de
  antemão; worktree existir é preparação, não início ([`worktree.md`](worktree.md)).
- **Evidência inacessível** — API fora, overlay ilegível, story sem acesso: o resultado é
  "não foi possível confirmar", sem transição.
- **Auditoria não move status sozinha: reporta.** O relatório diz status atual, status
  esperado, as evidências consultadas e as que não se conseguiu ler.

### Atualizar o status

Para mudar o estado de uma story, use `taiga_stories_update` com o `id` do status lido em
`us_statuses`. Consulte o schema que o servidor MCP expõe no momento da chamada para saber
como informar a story e o status. Esta referência não fixa nome de parâmetro, ID numérico,
payload ou capacidade que não estejam comprovados pelo servidor — **não adivinhe esses
valores**.

Antes de atualizar, confirme o projeto e a story corretos. A mudança é visível no board
compartilhado: **confirme a transição com quem pediu** e, depois, confira o resultado na
leitura da story.

A exceção é um pacote de tarefa do orquestrador que liste transições explícitas — `In
progress` ao começar, `In revision` ao devolver, registro de bloqueio ao interromper,
desbloqueio ao retomar, `In progress` de volta quando a revisão tem achados. Essas já vêm
autorizadas. Nenhuma outra transição é implícita.

## O que existe

### Projetos

| Ferramenta | Devolve |
|---|---|
| `taiga_projects_list` | Todos os projetos acessíveis: `id`, `name`, `slug`, `description`. Aceita `search` |
| `taiga_projects_get` | Um projeto com detalhe |

### User stories

| Ferramenta | Para |
|---|---|
| `taiga_stories_list` | Listar as stories de um projeto |
| `taiga_stories_get` | Uma story pelo id numérico, com todos os campos |
| `taiga_stories_create` | Criar |
| `taiga_stories_update` | Atualizar |
| `taiga_stories_archive_or_close` | Tirar do board de forma **reversível** |

### Tasks

`taiga_tasks_list`, `taiga_tasks_get`, `taiga_tasks_create`, `taiga_tasks_update`,
`taiga_tasks_archive_or_close` — mesma forma.

### Epics

`taiga_epics_list`, `taiga_epics_get`, `taiga_epics_add_user_story`.

### Outros

| Ferramenta | Para |
|---|---|
| `taiga_users_list` | Usuários, para atribuir |
| `taiga_milestones_list` | Sprints |
| `taiga_diagnostics` | Confere a conexão: servidor, conta, número de projetos |

## As três que estão bloqueadas

`taiga_stories_delete`, `taiga_tasks_delete` e `taiga_epics_delete` estão em
`permissions.deny` da configuração do Claude Code.

**O motivo:** os boards são compartilhados e estão em produção. Apagar story ou task alheia
é irreversível, e é invisível para quem dependia dela — o card simplesmente some do board de
outra pessoa.

**A alternativa correta existe e foi deixada disponível de propósito:**
`archive_or_close`. Ela tira do board e é reversível. Se alguém pedir para "remover" um
item, é quase sempre isso que quer dizer.

Se uma exclusão for genuinamente necessária, ela é uma ação humana na interface do Taiga —
não peça para relaxar a regra.

## Resolver o id do projeto

**Use `taiga_projects_list`. Não confie em lista mantida à mão.**

Índices escritos por pessoas envelhecem em silêncio: o índice de projetos da vault hoje omite
dois projetos ativos, e nada nele indica que está incompleto.

E **não deduza o id a partir do nome do repositório** — eles divergem com frequência:

| GitLab | Slug no Taiga |
|---|---|
| `triagem.ai` | `triagemai` |
| `contavinculada` | `conta-vinculada` |
| `ponto` | `sistema-de-ponto` |
| `kaizenstat` | `kaizenstats` |
| `infra` | `infra-2025` |

Uma vez resolvido, o par (slug, id) pertence ao `AGENTS.md` do repositório, na tabela de
identidade do projeto — assim a próxima sessão não precisa consultar de novo.

## O uso no fluxo

```
1. taiga_stories_get(<id>)           → título, descrição, critérios, is_blocked
2. worktree + branch TG-<id>         → worktree.md
3. a story pode começar?             → abaixo; se não, bloqueio e para; bloqueada, desbloqueio
4. registro de início                → campos pela API + assigned_users + In progress, com autorização
5. commits "<Verbo> ... - TG-<id>"
6. MR e ciclo até a devolução        → ciclo-da-mr.md
7. revisão por outro agente          → revisao-da-mr.md
8. taiga_stories_archive_or_close    ← somente se arquivamento/fechamento for pedido
```

O passo 1 é o que muda a qualidade do resto: com o título da story em mãos, a mensagem de
commit sai no verbo certo e descreve o efeito, não o esforço.

### A story pode começar?

O passo 3 vem antes do registro de início porque o registro afirma que o trabalho começou:
feito numa story que não pode andar, deixa no board um início sem trabalho atrás. Duas
perguntas, respondidas pelo conteúdo da story, não pelo status:

- **A especificação está fechada?** Critérios de aceite presentes na descrição — o critério
  de `Ready`. Uma story em `New` com critérios pode começar quando quem pediu a entregou
  para execução; uma em `Ready` sem critérios é dúvida de especificação.
- **O que ela consome já está na `develop`?** Leia o que a descrição cita e a story vizinha
  anterior (`neighbors` do `taiga_stories_get`), e confira em `origin/develop` o código de
  que a story depende. Existindo só na branch de outra story, com MR aberta, é
  **dependência de story não mergeada**. Na US #15 do `plataforma-iac` (B7), o IP a validar
  era um campo do `Draft` da B6, que estava só na MR !24: sem ela, a validação não tinha
  fluxo nenhum para bloquear.

Qualquer "não" é impedimento externo: registro de bloqueio com a causa, **sem** registro de
início e sem mudar o status, e relatório de interrompida
([`ciclo-da-mr.md`](ciclo-da-mr.md#4-os-dois-desfechos)). Empilhar a branch sobre a da outra
story é decisão de quem pediu, não do executor ([`worktree.md`](worktree.md#base-da-branch)).

### Retomar story bloqueada

Quem desbloqueia é **quem retoma a story, no começo da rodada nova** — não quem bloqueou,
cuja sessão já terminou. O passo 3 se refaz a partir da causa do `blocked_note`: a condição
que ele dá para retomar se confere na fonte (a MR citada está `merged`, o código de que a
story depende está em `origin/develop`), e não se presume pelo tempo que passou.

- **A causa se resolveu:** desbloqueie (`is_blocked: false`, `blocked_note: ""`, pela
  [API](#gravar-e-ler-os-registros-pela-api-do-taiga), com o `version` relido), releia a
  story e siga o fluxo. O registro de início que já existe não se refaz: faça só o que
  falta. A branch parada numa `develop` velha avança antes do primeiro commit
  ([`worktree.md`](worktree.md#retomar)).
- **Não se resolveu:** a story continua bloqueada e a rodada termina interrompida. Se a
  causa mudou, atualize o `blocked_note`.

O desbloqueio segue a autorização das outras transições ([abaixo](#atualizar-o-status)).

**Cuidado com o passo 8.** Arquivar a story é uma ação visível para o time e é diferente de
movê-la para `Done`, mesmo num board em que `Done` fecha a story. Confirme antes — merge em `develop` não significa nem que staging já
roda a versão ([`cadeia-de-entrega.md`](cadeia-de-entrega.md)), muito menos que a entrega foi
aceita ou que a story deve sair do board.

## Escrita em board compartilhado

Criar e atualizar são permitidos, e continuam sendo ações que aparecem para outras pessoas.
Antes de `stories_create` ou `stories_update`, confirme com quem pediu:

- O projeto certo (os ids divergem dos nomes de repositório).
- Que a story ainda não existe — duplicata em board de Kanban é pior que ausência, porque
  duas pessoas passam a trabalhar em cards diferentes para a mesma coisa.

Leitura é livre.
