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
wt step copy-ignored --to TG-xx                   # só se o projeto não tiver o hook pre-start
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

## Segredos locais e o que o `copy-ignored` copia

Os segredos de desenvolvimento local — credenciais de OAuth, tokens de integração — ficam
**uma vez**, no checkout principal, numa pasta ignorada pelo Git (no `plataforma-iac`,
`config/`). Cada worktree recebe uma cópia na criação, e ninguém começa uma story com
configuração faltando ou errada.

`wt step copy-ignored` copia do checkout principal o que é ignorado pelo Git. Sem
`.worktreeinclude`, copia **tudo** o que é ignorado — `node_modules/`, `target/`, o Node
baixado pelo build, caches —, facilmente centenas de MiB. Com o arquivo, copia **só** o que estiver ignorado **e**
listado — então liste também o que evita começar do zero:

```text
# .worktreeinclude
/config/
/node_modules/
```

**Ancore na raiz.** Os padrões seguem a sintaxe do `.gitignore`: `config/` sem a barra casa
com qualquer diretório `config` da árvore. No `plataforma-iac`, pegaria também
`plataforma-iac-core/src/main/resources/config/`, ignorado justamente porque o que fica ali
entra no jar, e espalharia para todo worktree o segredo que alguém tivesse posto no lugar
errado.

Listar arquivo versionado não faz nada; é a primeira coisa a conferir quando "o arquivo não
veio".

**Vale o `.worktreeinclude` da origem da cópia**, que por padrão é o checkout principal, e
não o do worktree de destino. Um `.worktreeinclude` novo, criado ou alterado na branch de
uma story, não muda nada até a mudança chegar à branch do checkout principal. Pelo mesmo
motivo, um `wt step copy-ignored --dry-run` rodado no worktree da story ainda mostra a lista
antiga. Para ver o efeito antes do merge, use o worktree da story como origem:
`wt step copy-ignored --from TG-xx --to develop --dry-run`. Isso só funciona se ele já tiver
os ignorados que se quer testar.

Para a cópia acontecer sozinha, o projeto declara o hook em `.config/wt.toml`:

```toml
# .config/wt.toml
pre-start = "wt step copy-ignored"
```

- **`pre-start`, não `post-start`.** O `post-start` roda em segundo plano, e o agente que
  entra no worktree logo depois pode começar antes de `config/` existir. O `pre-start`
  termina antes de o `wt switch --create` devolver.
- **Hook de projeto pede aprovação** na primeira vez, em cada máquina, e de novo quando o
  comando muda. Num terminal, o `wt` pergunta; quem recusa ganha o worktree sem os segredos.
  **Fora de terminal (orquestrador, agente), o comando falha** com `Cannot prompt for
  approval in non-interactive environment` e sai com 1, sem criar worktree nem branch. Por
  isso uma pessoa roda `wt config approvals add` no repositório antes, uma vez por máquina,
  revisando o comando. Um agente não aprova por ela, nem com `--yes`. Hook na configuração
  do usuário (`~/.config/worktrunk/config.toml`) não pede aprovação e vale para todos os
  repositórios.
- **Vale o `.config/wt.toml` do worktree onde o comando roda.** O orquestrador roda o
  `wt switch --create` no checkout principal, então o hook novo, como o `.worktreeinclude`,
  só vale depois de chegar à branch de lá. Até isso acontecer, o worktree é criado sem hook
  e sem erro, e sem os segredos. Aprove depois que o arquivo chegar ao checkout principal:
  o `approvals add` aprova o comando que encontra lá.
- **A cópia não sobrescreve.** Arquivo que já existe no worktree fica como está: segredo
  trocado no checkout principal não chega a worktrees antigos sozinho. Para atualizar:
  `wt step copy-ignored --to TG-xx --force`.

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
