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
| `Início da implementação` | data/hora | executor, ao começar |
| `Executor` | texto (agente + modelo, ou pessoa) | executor, ao começar |
| `Worktree` | texto (branch e caminho) | executor, ao começar |
| `Testado em staging` | sim/não | quem testou |
| `Testado por` | texto | quem testou |
| `Data do teste` | data | quem testou |

Bloqueio usa o campo nativo da story, `is_blocked` + `blocked_note`.

**Hoje o MCP não cobre isso.** Ele não cria definições de campo, não lê os valores
(`userstories/custom-attributes-values`), o `custom_attributes` do `taiga_stories_update`
vai no `PATCH` da story e provavelmente é ignorado, e `is_blocked` não é exposto. Enquanto
for assim, o registro usa **tags**, com a mesma semântica e sem dado estruturado:

| Registro | Fallback por tags |
|---|---|
| Início da execução | `assigned_to` do executor + tag `execucao:TG-xx`; a mudança para `In progress` acompanha, mas não faz parte do registro |
| Interrupção | tag `bloqueado` (a story continua `In progress`) |
| Teste/aceite em staging | tag `testado-staging`, aplicada por quem testou (ou pelo orquestrador, a pedido explícito dessa pessoa) |

A regra: **campos quando o projeto os tiver definidos e o MCP souber gravá-los; senão,
tags.** O status nunca é evidência do registro: uma story arrastada de volta para `Ready` com
a tag `execucao:TG-xx` continua com início registrado. O resto desta página diz "registro de
início" e "registro de teste" para valer nas duas formas.

**Registros valem para uma versão.** O registro de teste se refere à versão testada; quando
a story é reaberta depois de uma entrega, quem reabre retira `testado-staging` (e o campo
volta a "não"), porque a próxima versão ainda não foi testada. Ao retomar uma story
interrompida, o executor retira `bloqueado`.

### Critérios de transição (quando mover)

| Para | Quando |
|---|---|
| `New` | A ideia existe; a especificação ainda precisa ser fechada |
| `Ready` | Especificação concluída: critérios de aceitação presentes |
| `In progress` | O executor começou de fato: registro de início feito. Commits não são exigidos |
| `In revision` *(opcional)* | MR devolvida para revisão ([`ciclo-da-mr.md`](ciclo-da-mr.md)) |
| `Ready for test` | Staging roda a versão |
| `Waiting for deployment` *(opcional)* | Staging roda a versão **e** registro de teste presente; produção ainda não roda a versão |
| `Done` | Registro de teste presente **e** produção roda a versão |

"A versão", em todos os critérios, é a da MR `TG-xx` mais recente. Com uma MR aberta, a story
tem trabalho em andamento, e uma entrega anterior da mesma story não satisfaz `Ready for
test` nem os seguintes.

"Roda a versão" é a cadeia de entrega completa no ambiente — commit do merge, pipeline,
tag, overlay e pods —, descrita em [`cadeia-de-entrega.md`](cadeia-de-entrega.md). Tag
publicada no registry não basta.

**Sem os opcionais.** Boards que não têm `In revision` nem `Waiting for deployment` — é o
caso comum hoje — caem nos status existentes: `In progress` vai até staging rodar a versão,
e `Ready for test` vai até `Done`. Todo critério tem para onde ir.

**Transição pendente.** Entre o merge e staging rodar a versão, a story fica no status
anterior (`In revision`, ou `In progress` sem ele). Não é um estado novo; a auditoria reporta
"transição pendente: aguardando staging".

`Done` é uma mudança de status. Não significa, por si só, arquivar, fechar ou remover a
story do board.

### Regras de auditoria (conferir se o status está certo)

Auditar é comparar o status atual da story com o que as evidências dizem que ele deveria
ser.

- **Precedência.** Avalie do mais avançado para o menos: `Done`, `Waiting for deployment`,
  `Ready for test`, `In revision`, `In progress`, `Ready`, `New`. O primeiro critério
  satisfeito é o status esperado. Status opcional que o board não tem sai da lista.
- **`Ready` exige ausência de trabalho, não ausência de commits:** sem registro de início e
  sem MR `TG-xx`, aberta ou mergeada. A branch apagada depois do merge não devolve a story a
  `Ready` — a MR mergeada continua lá.
- **Registro de início sem commits é `In progress`.** O executor pode estar lendo, testando
  hipótese, ou ter sido interrompido antes do primeiro commit. Nunca recomende regressão a
  `Ready` por falta de commits.
- **MR `TG-xx` sem registro de início também é trabalho.** Alguém começou sem registrar: o
  esperado é `In progress` (ou mais avançado, pelos outros critérios), e o relatório aponta
  o registro que falta.
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
progress` ao começar, `In revision` ao devolver, registro de bloqueio ao interromper. Essas
já vêm autorizadas. Nenhuma outra transição é implícita.

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
1. taiga_stories_get(<id>)           → título, descrição, critérios
2. worktree + branch TG-<id>         → worktree.md
3. registro de início                → status In progress + campos (ou tags), com autorização
4. commits "<Verbo> ... - TG-<id>"
5. MR e ciclo até a devolução        → ciclo-da-mr.md
6. taiga_stories_archive_or_close    ← somente se arquivamento/fechamento for pedido
```

O passo 1 é o que muda a qualidade do resto: com o título da story em mãos, a mensagem de
commit sai no verbo certo e descreve o efeito, não o esforço.

**Cuidado com o passo 6.** Fechar a story é uma ação visível para o time e é diferente de
marcá-la como `Done`. Confirme antes — merge em `develop` não significa nem que staging já
roda a versão ([`cadeia-de-entrega.md`](cadeia-de-entrega.md)), muito menos que a entrega foi
aceita ou que a story deve sair do board.

## Escrita em board compartilhado

Criar e atualizar são permitidos, e continuam sendo ações que aparecem para outras pessoas.
Antes de `stories_create` ou `stories_update`, confirme com quem pediu:

- O projeto certo (os ids divergem dos nomes de repositório).
- Que a story ainda não existe — duplicata em board de Kanban é pior que ausência, porque
  duas pessoas passam a trabalhar em cards diferentes para a mesma coisa.

Leitura é livre.
