# Worktree por story

Cada story é trabalhada num worktree próprio, com a branch `TG-xxx` criada a partir de
`origin/develop`. É o que permite vários agentes — ou uma pessoa e um agente — mexerem no
mesmo repositório ao mesmo tempo. Com um checkout só, um `git switch` de um apaga o estado
de trabalho do outro: arquivos somem no meio do build, o commit de um leva a alteração do
outro, e ninguém percebe até a MR vir com diff estranho.

Detalhes do `wt` (hooks, aliases, configuração, qual worktree um comando alcança) estão nas
skills `worktrunk` e `wt-switch-create` (repositório `max-sixty/worktrunk`); aqui fica só o
que o fluxo da Basis exige.

## Começar

```sh
git fetch origin
wt switch --create TG-xx --base origin/develop    # cria ../<repo>.TG-xx
wt step copy-ignored --to TG-xx                   # .env, caches, target/
```

O worktree nasce em `../<repo>.TG-xx`, irmão do repositório principal — o padrão do
worktrunk. Em `~/Projetos/Basis/ponto`, a story 58 fica em `~/Projetos/Basis/ponto.TG-58`.

O `fetch` antes não é cerimônia: `--base origin/develop` parte da referência remota como ela
está na sua máquina, e sem `fetch` a story começa de uma `develop` velha.

**O `wt` não muda o diretório do shell do agente.** Sem a integração de shell ativa — o caso
normal num agente —, ele avisa `Cannot change directory` e o shell continua no checkout
principal, em `develop`. Todo comando seguinte roda no caminho do worktree: `cd` explícito
para `../<repo>.TG-xx`, ou `git -C ../<repo>.TG-xx ...`. Um `git status` no diretório errado
mostra `develop` limpo e leva a concluir que nada começou — e a commitar no checkout
principal.

## Por que irmão, e dentro de `~/Projetos/Basis`

- **As ferramentas varrem a árvore.** Um worktree dentro do repositório principal (em
  `.worktrees/`, por exemplo) é visto por Maven, Spotless, o scanner do Sonar e a IDE como
  parte do projeto: módulo duplicado, formatação aplicada no vizinho, análise contando código
  que não é da MR. Irmão, ele fica fora do alcance.
- **O `ai-memory` precisa reconhecer o projeto.** Os hooks acham o `.ai-memory.toml` subindo
  a partir do diretório atual; dentro de `~/Projetos/Basis`, o worktree herda o do workspace,
  e `project_strategy = "repo-root"` junta a memória dele ao projeto do repositório
  principal. Num worktree em `/tmp` ou em outra pasta, a sessão cai fora do workspace e a
  memória não aparece nem é gravada no lugar certo.

## O que o `copy-ignored` copia

`wt step copy-ignored` copia **tudo** o que é gitignored do worktree principal: `.env`,
`target/`, `node_modules/`, caches. Para limitar, o projeto mantém um `.worktreeinclude` na
raiz. Um arquivo só é copiado se estiver ignorado pelo git **e** listado no
`.worktreeinclude` — listar um arquivo versionado não faz nada, e é a primeira coisa a
conferir quando "o arquivo não veio".

## Upstream e o primeiro push

`--base origin/develop` com um nome de branch diferente (`TG-xx`) não configura upstream. O
primeiro push precisa dizer para onde vai:

```sh
git push --set-upstream origin TG-xx
```

Com `push.autoSetupRemote = true` no git, um `git push` simples resolve.

## Retomar

Retomar vale enquanto a MR `TG-xx` está **aberta** (ou ainda não existe, mas a branch sim):
o trabalho foi interrompido, ou é uma rodada nova depois da revisão. Entrar no que existe:

```sh
git fetch origin
wt switch TG-xx --no-cd                    # cria o tracking se a branch só existir no remoto
cd ../<repo>.TG-xx
git status
git pull --ff-only                         # alguém pode ter empurrado na branch
git log -1 --oneline
```

Sem `--create`: a branch já existe, e criá-la de novo a partir de `origin/develop` gera uma
branch divergente da MR, com push rejeitado. **Se `wt switch TG-xx` falhar, a resposta não
é `--create`**: confira o `fetch` e o nome da branch (`glab mr list --source-branch TG-xx`),
ou pergunte. Os pushes novos entram na mesma MR. Um worktree com alterações não commitadas é
trabalho de alguém, não sujeira.

**MR já mergeada não se retoma.** Se a story voltou depois do merge (teste em staging
reprovou, story reaberta), os commits da branch já entraram em `develop` pelo squash:
continuar em cima deles reabre a branch apagada e traz de novo conteúdo que já está em
`develop`. A rodada nova é trabalho novo: `wt remove TG-xx` no worktree velho, depois
`git fetch origin` e `wt switch --create TG-xx --base origin/develop`, e uma MR nova.

## Criar o worktree não é começar a story

Um orquestrador pode preparar worktrees de antemão, para várias stories, antes de qualquer
agente começar. Isso é preparação. A story começa quando o executor faz o **registro de
início** (ver [`taiga-mcp.md`](taiga-mcp.md)) — e é esse registro, não a existência do
worktree, que a auditoria de status consulta.

## Remover

```sh
wt remove TG-xx
```

Depois do merge da MR, nunca antes: o worktree é onde o ciclo da MR acontece, e a rodada de
correção depois da revisão volta para ele. Quem remove:

- **Com orquestrador:** o orquestrador. O agente de implementação para quando devolve a MR,
  antes do merge, e não sabe quando o merge acontece.
- **Sem orquestrador:** quem fez o merge.

O `wt remove` apaga a branch local só se a reconhecer como mergeada. Se recusar, confira que
a MR está `merged` antes de forçar com `-D`.

## Agente sozinho × com orquestrador

- **Agente sozinho**, numa story sem branch nem worktree, cria com `wt switch --create TG-xx
  --base origin/develop --no-cd` e passa a trabalhar no caminho criado (o `--no-cd` evita
  depender de o shell do agente seguir o `cd`), ou usa a skill `wt-switch-create`, que cria e
  muda o diretório da sessão. Se a branch ou o worktree já existem, é retomada: `wt switch
  TG-xx --no-cd`, sem `--create`.
- **Com orquestrador**, o pane do Herdr já nasce dentro do worktree; o agente não cria nada,
  só confere com `git status` e `git branch --show-current` que está na branch da story.
