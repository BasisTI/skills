# agy (antigravity-cli)

Confira `agy --help`, `agy models` e `agy agents` antes de despachar: a CLI muda entre versões. Os fatos abaixo vêm do ensaio da orq #108 (2026-11-21, onda 304: orq #64 com o `agy` nos três papéis, `agy` 1.5.14, Herdr 0.9.5; relatório do ensaio em `epico-agy/relatorio-ensaio-orq-108.md` da pasta de artefatos do coordenador) e do planejamento do épico orq #105 (2026-11-20/21). O `agy` assume os papéis de executor, revisor e planejador. Fato sem ensaio aparece com a ressalva "não testado" ou "desconhecido"; não se presume.

## Lançamento

Pelo script, que chama `herdr agent start <nome> --kind agy --pane <pane> -- …`:

```bash
scripts/herdr-workers.sh start --kind agy <nome>=<pane> -- --model <id> --mode accept-edits --add-dir <worktree> --add-dir <artefatos> [--agent <papel>]
```

- **Modelo:** só `--model <id>`, com o id completo de `agy models` (ex. `gemini-4-neon-medium`). O esforço já vem no id, então o lançamento **não** passa `--effort` e o alias tem `esforco` vazio ([configuração](../configuracao.md#alias-agy)).
- **Modo:** `--mode accept-edits`, por decisão do Cedric em 2026-11-21 ("Use --mode accept-edits nos próximos workers agy"). Não use `--mode auto`. No ensaio (orq #108):
  - **`auto`** pediu aprovação para **cada arquivo** criado ("Allow creation of this file?") ou editado ("Accept this file edit?"), mesmo dentro do `--add-dir`; a edição só chegava ao disco depois de aprovada. Com esse diálogo aberto o Herdr mostra `done`, não `blocked` ([estados](#estados-no-herdr)): a `espera-onda.sh` não acorda e o executor ficou cerca de 30 min parado.
  - **`accept-edits`** (rodada 2 do executor e do revisor): nenhum arquivo pediu aprovação. Os comandos de shell continuam pedindo ([aprovações](#aprovações-do-coordenador)).
  - Leitura de arquivo nunca pediu aprovação, nem fora do cwd.
  - O rodapé do revisor mostrou `accept-edits` numa sessão lançada com `--mode auto`; a causa não foi identificada. Confira o modo no rodapé do pane depois do lançamento.
- **Diretórios:** um `--add-dir` para a worktree da US e outro para a pasta de artefatos (relatório e pendências, `~/tmp/orquestrador/<projeto>/TG-<ref>`). O `TMPDIR` da US (`/tmp/orq/<projeto>/TG-<ref>`) é outro caminho e **não** precisa de um terceiro `--add-dir`: o processo filho do comando (testes Go, por exemplo) escreve ali sem passar pelas aprovações do `agy` (ensaio, orq #108). Isso vale para o que o **processo filho** escreve; a ferramenta de escrita do próprio agente fora dos `--add-dir` não foi testada. `--add-dir` é repetível e só acrescenta ao workspace; não amplia os direitos do processo pai.
- **Sem bypass:** nunca `--dangerously-skip-permissions`. Também não use como receita para limpeza. `--sandbox` e `--settings` existem; `--settings` está em [pré-aprovação](#pré-aprovação-com---settings), sem uso por padrão.
- **Papel:** `--agent <papel>` é opção da **sessão**: vai nos argumentos nativos do `start`, depois de o coordenador conferir o papel em `agy agents`. Mandá-lo no prompt, depois do `start`, não seleciona nada ([papéis](#papéis-como-agentes-nativos)). Worker sem papel (executor) não leva `--agent`.

O pane precisa estar no prompt do shell, como nos outros harnesses. O nome do agente segue [nomes dos panes](../despacho.md#nomes-dos-panes).

## Aprovações do coordenador

No `accept-edits` os arquivos passam sozinhos, mas **comando de shell e chamada MCP pedem aprovação** no pane, e o coordenador as dá (origem: ensaio da orq #108, logs `aprovacoes-*-64.log`).

- **Comando.** Diálogo "Requesting permission for: … Run this command?", com 4 opções: uma vez; sempre nesta conversa, para o prefixo do comando; persistir em `settings.json`; cancelar. A regra é por **prefixo**, e o prefixo que o diálogo oferece varia: às vezes só o primeiro termo (`taiga`, `gh`), às vezes o comando inteiro (`rm -rf /tmp/orq/…`). O mesmo vale para comando com variável na frente: o prefixo pode ser `TMPDIR=…`.
- **MCP.** Diálogo "Allow calling this tool?", com 6 opções (uma vez, sempre na conversa, sempre persistindo em `settings.json`, negar…).
- **Por que o prefixo importa.** "Sempre nesta conversa" libera tudo que começa com o prefixo: `gh` liberaria `gh pr merge`; `TMPDIR=…` liberaria **qualquer** comando depois da variável.
- **Regra do coordenador** (a que o ensaio seguiu):
  - prefixos de **leitura e build** (`grep`, `ls`, `go test`, `npm test`, o próprio `taiga` nas leituras…) vão "sempre nesta conversa";
  - `git`, `gh` e comando com **variável na frente** vão **um a um** ("uma vez");
  - **script novo** só depois de lido pelo coordenador;
  - **nunca** a opção que persiste em `settings.json`: ela vale para todas as sessões futuras, de qualquer projeto. Mesmo com a regra, o `~/.gemini/antigravity-cli/settings.json` do coordenador acabou, depois do ensaio, com entradas `permissions.allow` de comando (uma delas liberava `herdr` inteiro, outra um `rm -rf` de caminhos da onda): confira esse arquivo ao fim de cada onda e remova o que a regra proíbe.
  - Comando que o worker não deveria rodar é **negado** ("No, cancel"), e o coordenador diz o que fazer no lugar (no ensaio: uma sondagem que registrava coordenador com o pane real e subia daemons com o Herdr real foi negada, e o revisor a refez com `herdr` falso no PATH e pane inexistente). "No, cancel" interrompe o turno ("What should Antigravity CLI do instead?") e deixa o agente `done` até um prompt novo.
- **O agente não enxerga essas aprovações.** O autorrelato do `agy` sobre permissões **não é evidência**: o executor da r1 escreveu "nenhuma ação pediu aprovação manual" depois de dezenas de aprovações dadas no pane. O registro vem do coordenador (log de aprovações da onda), e o relatório do worker não o substitui.
- **Vigia.** Com `accept-edits` os únicos diálogos que sobram são de comando e de MCP, e esses deixam o Herdr em `blocked`, que a `espera-onda.sh` já trata. Se um diálogo de **arquivo** voltar (modo errado, por exemplo `auto`), o Herdr diz `done`: a espera não acorda e o coordenador precisa olhar a tela do pane (`herdr pane read`).

## Pré-aprovação com `--settings`

Fonte: documentação pública do `agy` (<https://antigravity.google/docs/permissions.md>, seção "CLI fine-grained permissions"), lida em 2026-11-21 pela orq #109; as skills embutidas em `~/.gemini/antigravity-cli/builtin/skills/` só remetem a essa página. **Não foi testado no ensaio** e **não é o padrão**: o coordenador decide depois se adota.

- **Formato.** `--settings` aceita "um objeto JSON de chaves do `settings.json`, inline ou como caminho de arquivo, só para esta sessão, nunca salvo" (`agy --help`). O `settings.json` tem `permissions` com três listas, `deny`, `ask` e `allow`, de regras `ação(alvo)`. Precedência: **deny > ask > allow**.
  - Ações: `command(prefixo)`, `command(regex:padrão)`, `command(*)`, `read_file`, `write_file`, `read_url`, `execute_url`, `mcp(servidor/ferramenta)`, `mcp(servidor/*)`.
  - `command` casa por prefixo, palavra por palavra. Comando com `$(...)`, crase, expansão de chaves ou outro construto que esconda execução só passa por **correspondência exata da linha inteira**; senão cai em `ask`. Pipeline e `&&`/`;` casam prefixo normalmente.
- **Exemplo seguro** (não liberado como padrão): permite leitura e build, pergunta antes do que muda estado compartilhado, nega o que o coordenador nunca aprova.

  ```json
  {
    "permissions": {
      "allow": ["command(ls)", "command(grep)", "command(cat)", "command(head)", "command(tail)", "command(find)", "command(go test)", "command(go build)", "command(go vet)", "command(npm test)", "command(npm run build)", "command(mvn -B test)"],
      "ask": ["command(git)", "command(gh)", "command(taiga)", "command(herdr)"],
      "deny": ["command(gh pr merge)", "command(git push --force)", "command(git push -f)", "command(rm -r)", "command(rm -rf)", "command(pkill)", "command(killall)", "command(sudo)"]
    }
  }
  ```

  - O `deny` bloqueia o worker sem a pessoa no pane; o comando negado volta ao agente como recusa, sem diálogo.
  - `ask` em `git`/`gh` reproduz a regra "um a um" e mantém o `blocked` do Herdr para o coordenador aprovar.
  - Antes de adotar, ensaie numa sessão descartável: confira que `--settings` mescla com o `settings.json` global em vez de substituí-lo, que o `deny` vence uma entrada persistida e que `command(rm -r)` casa `rm -rf`. Nada disso foi exercitado.
  - Nunca ponha `command(*)` em `allow`.

## Estados no Herdr

Observados no ensaio da orq #108 (Herdr 0.9.5):

| Situação | Estado |
|---|---|
| Pane recém-aberto | `idle` |
| Trabalhando | `working` |
| Diálogo de **comando** ou de **MCP** aberto | `blocked` |
| Diálogo de **arquivo** aberto (só no `--mode auto`) | **`done`**, não `blocked` |
| Planejador com o turno terminado, esperando a pessoa | `done` |
| Depois de ctrl+c duas vezes | o `agy` sai e o pane volta ao shell |

Consequências:

- `done` **não comprova entrega** nem fim de trabalho ([anomalias](../acompanhamento.md#anomalias)): o relatório comprova.
- A `espera-onda.sh` acorda por `blocked` (comando, MCP) e por `parado` (`done` sem relatório há `--parado-s` segundos). Com `accept-edits` não há diálogo de arquivo, então nenhum `done` escondido atrás dele.
- **Planejador `agy`:** esperar a pessoa é `done`, e a espera sai por `parado`. Isso é esperado no ponto humano, não anomalia: passe um `--parado-s` que cubra o tempo de resposta da pessoa, ou trate cada `parado` como "ainda conversando" depois de olhar o pane. No ensaio a espera saiu duas vezes por `parado` e uma por limite de espera durante a conversa.
- O aviso do worker ao coordenador (`herdr agent prompt`) chegou como turno novo, às vezes com atraso depois do relatório. Confira o relatório no arquivo, não só o aviso.

## Retomada

- **Id da conversa.** Ao sair (ctrl+c duas vezes), o `agy` imprime "Resume with -c (or command below): `agy --conversation=<id>`". É ali que se acha o id; anote-o na saída do pane antes de fechá-lo.
- **Como retomar.** `--conversation=<id>`, no mesmo pane, com outro `--mode` se for o caso. Foi o que se fez na rodada 2 do executor e do revisor (`--conversation=<id> --mode accept-edits`): a conversa da rodada 1 e o contexto foram mantidos, e o rodapé mostrou `accept-edits · Gemini 4 Neon · medium`.
- **`-c` (`--continue`)** retoma "a conversa mais recente" (`agy --help`). O escopo dele (por pane, por diretório ou global) **não foi testado**; prefira sempre o id e não use `-c` onde houver mais de uma worktree.

## Espera

A espera do coordenador depende do harness **do coordenador**, não do worker: Claude Code com `espera-onda.sh` em background ([Claude Code](claude-code.md#espera)), Codex com o laço no turno ([Codex](codex.md#espera)). O `espera-onda.sh` lê o estado do worker pelo Herdr, então o `agy` entra como qualquer outro agente, com as particularidades de [estados](#estados-no-herdr).

Quando o coordenador for um `agy`: se ele acorda ao fim de um comando em background **não foi testado** (o ensaio teve coordenador Claude Code); sem isso, use o laço do Codex.

## Limite de uso

O texto da mensagem de limite de uso do `agy` é **desconhecido**: nenhuma mensagem apareceu no ensaio da orq #108, e nenhum texto está registrado aqui de propósito. Vale o sinal geral da [troca por limite](../configuracao.md#troca-por-limite): worker parado, sem relatório, com a mensagem de limite do harness no pane. Nunca decida pela cota do rodapé. Registre o texto exato quando aparecer.

## Papéis como agentes nativos

Os papéis `qa-adversarial` e `planejador` são agentes globais do `agy`, lidos de `~/.gemini/config/agents/<papel>/agent.md`.

**Esse arquivo é gerado, não é link.** No ensaio, `agy --agent planejador` carregou o papel (o rodapé mostrou `planejador (Gemini 4 Neon · xhigh)` e a conversa seguiu o papel), mas a sessão ficou só com `read_file` e MCP: sem shell nem escrita, o planejador não gravou o retorno, não rodou `taiga` nem `herdr` e emitiu o retorno no chat. Causa, na skill embutida do `agy` `migrate-agent-settings`: agente **sem `tools` no frontmatter** recebe só um conjunto pequeno de leitura, e para ter todas as ferramentas é preciso `tools: [read_file, edit_file, write_file, run_command, manage_task, search_web]` (com `subagent: true` e `mainAgent: false`). Os papéis do clone não têm `tools`, e o campo não pode ir neles: no Claude Code ausência quer dizer "todas", e o campo, quando existe, restringe e usa outros nomes (`Read`, `Bash`…).

- **Geração.** `scripts/agy-gerar-papeis.sh` lê `agents/<papel>.md` do clone e grava `~/.gemini/config/agents/<papel>/agent.md` com o frontmatter do `agy` (`name`, `description`, `subagent`, `mainAgent`, `tools`) e o corpo do papel sem alteração, mais uma marca de arquivo gerado. Descarta `mode`, `model`, `color` e o `tools` do Claude Code.
  - **Rode de novo depois de cada `git pull` do clone**: a cópia gerada não acompanha o canônico sozinha. Rodar duas vezes não muda nada.
  - Um `agent.md` sem a marca (arquivo da pessoa) é recusado, e um link da instalação antiga da orq #107 só é trocado com `--substituir-link`.
  - Teste: `scripts/tests/agy-gerar-papeis.test.sh` (usa pastas temporárias, nunca o `~/.gemini` real).
- **Antes do lançamento**, o coordenador roda `agy agents`. Com o papel listado, passa `--agent <papel>` nos argumentos nativos do `herdr-workers.sh start` e o pacote registra o papel já selecionado. A seleção não acontece depois, pelo prompt. Depois do primeiro lançamento com o arquivo gerado, confira no pane que o papel tem shell e escrita (o planejador consegue gravar o retorno).
- **Reserva (modo arquivo):** se `agy agents` não listar o papel (arquivo ainda não gerado, por exemplo), o `start` sai sem `--agent`, o pacote entrega o conteúdo do arquivo do papel pelo prompt e registra a adaptação (origem, modo e motivo), com `qa_adversarial_modo = "arquivo"` autorizado no [ambiente](../configuracao.md). Foi assim com o revisor da orq #64, com acesso a shell, Node e Chromium.
- **Outras formas** (herança de ferramentas, `tools` por sessão) não foram encontradas nas skills embutidas; a skill `migrate-agent-settings` só descreve a lista explícita.

## Fallback

Depois do ensaio da orq #108, as cadeias de `[[selecao]]` incluem o `agy` (orq #109, 2026-11-21; [configuração](../configuracao.md#alias-agy)):

| Papel | Cadeia |
|---|---|
| Implementação | `implementacao-padrao` → `implementacao-agy` (`gemini-4-neon-medium`) → `implementacao-fallback` → `implementacao-reserva` |
| Revisão | `revisao-padrao` → `revisao-agy` (`gemini-4-neon-high`) → `revisao-fallback` → `revisao-reserva` |
| Planejamento | `planejamento-padrao` → `planejamento-complexo` → `planejamento-agy` (`gemini-4-neon-xhigh`) |

- A troca é a [troca por limite](../configuracao.md#troca-por-limite): imediata, até o fim da story, no mesmo pane. Para o `agy` ela traz o custo das [aprovações](#aprovações-do-coordenador): o coordenador precisa estar no pane para dar as de comando, e o worker `agy` não avança sozinho. Em modo autônomo, registre a troca no aviso ao usuário e olhe o pane com mais frequência.
- Na troca para o `agy` valem o lançamento acima (modo `accept-edits`, sem `--effort`) e, para revisor e planejador, o papel gerado em [papéis](#papéis-como-agentes-nativos). Se o papel não estiver listado em `agy agents`, o modo arquivo é a reserva registrada.
- O sinal de limite do próprio `agy` segue desconhecido ([limite de uso](#limite-de-uso)): um worker `agy` parado sem relatório e sem diálogo no pane exige olhar o pane, não presumir cota.
