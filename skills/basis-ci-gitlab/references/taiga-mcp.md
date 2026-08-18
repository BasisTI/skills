# O Taiga pelo servidor MCP

O servidor MCP `taiga` dá ao agente acesso aos boards. O uso principal no fluxo é **ler a
user story antes de nomear a branch e escrever o commit** — em vez de pedir o número a quem
já está com o card aberto.

As ferramentas aparecem como `mcp__taiga__*`. Se não estiverem disponíveis, o servidor não
está configurado nesta máquina: **pergunte, não contorne**. Não invente id de story nem de
projeto.

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
1. taiga_stories_get(<id>)     → título e descrição da story
2. branch TG-<id>              → criada a partir de develop
3. commit "<Verbo> ... - TG-<id>"
4. MR com Delete Branch + Squash
5. taiga_stories_archive_or_close(<id>)   ← depois do merge, se for o fim da story
```

O passo 1 é o que muda a qualidade do resto: com o título da story em mãos, a mensagem de
commit sai no verbo certo e descreve o efeito, não o esforço.

**Cuidado com o passo 5.** Fechar a story é uma ação visível para o time. Confirme antes —
merge em `develop` significa que chegou a staging, não que a entrega foi aceita.

## Escrita em board compartilhado

Criar e atualizar são permitidos, e continuam sendo ações que aparecem para outras pessoas.
Antes de `stories_create` ou `stories_update`, confirme com quem pediu:

- O projeto certo (os ids divergem dos nomes de repositório).
- Que a story ainda não existe — duplicata em board de Kanban é pior que ausência, porque
  duas pessoas passam a trabalhar em cards diferentes para a mesma coisa.

Leitura é livre.
