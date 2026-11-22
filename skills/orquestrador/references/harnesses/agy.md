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
  - O rodapé do revisor mostrou `accept-edits` numa sessão lançada com `--mode auto`. Causa candidata: o `agentMode` global do `~/.gemini/antigravity-cli/settings.json`, que na máquina do ensaio vale `accept-edits` (o `agy --help` diz que `--mode` vale "para esta sessão"). O mesmo fator pode estar por trás de "nenhum arquivo pediu aprovação" na rodada 2: o `--mode accept-edits` e o `agentMode` global coincidiam, e **qual dos dois vence não foi testado**. Por isso confira o modo no rodapé do pane depois do lançamento e, em outra máquina, o `agentMode` do `settings.json`.
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
  - **nunca** a opção que persiste em `settings.json`: ela vale para todas as sessões futuras, de qualquer projeto;
  - **Fato do ensaio (orq #108) sobre persistência.** Duas entradas aprovadas com a opção 1 ("só este") apareceram persistidas no `settings.json`: `command(chmod +x /tmp/orq/orq/TG-64/bin/herdr)` e `command(python3 /tmp/orq/orq/TG-64/probe_isolado.py)` (log `aprovacoes-revisor-64.log`, 2026-11-21 18:57:27Z e 18:58:04Z, "opção 1"; arquivo alterado às 19:06:50Z). Outras aprovações "opção 1" do mesmo ensaio **não** foram persistidas (por exemplo `probe_r2.py`, 19:17:11Z). **A causa não está confirmada**: pode ser a tecla enviada pelo coordenador, a numeração do diálogo ou um comportamento do `agy`. A regra "nunca persistir" sozinha, portanto, **não garante** que nada persista. Segundo o diário do ensaio (`ensaio-orq-108.md`, último item), só `kustomize`, `identity-hub` e `herdr` são entradas **anteriores** ao ensaio. De `find`, `grep` e `head` o diário não diz nada. Nos logs `aprovacoes-*-64.log`, `grep` e `find` aparecem aprovados na opção 2 (prefixo na conversa, que não persiste; `aprovacoes-revisor-64.log:9,11`) e `head` **não aparece** como comando aprovado em nenhum dos dois. A origem de uma eventual entrada deles no `settings.json` **não está atribuída**. O `rm -rf` de caminhos da TG-64 e o `python3 - <<'EOF'` também não foram atribuídos a uma aprovação específica.
  - Comando que o worker não deveria rodar é **negado** ("No, cancel"), e o coordenador diz o que fazer no lugar (no ensaio: uma sondagem que registrava coordenador com o pane real e subia daemons com o Herdr real foi negada, e o revisor a refez com `herdr` falso no PATH e pane inexistente). "No, cancel" interrompe o turno ("What should Antigravity CLI do instead?") e deixa o agente `done` até um prompt novo.
- **O agente não enxerga essas aprovações.** O autorrelato do `agy` sobre permissões **não é evidência**: o executor da r1 escreveu "nenhuma ação pediu aprovação manual" depois de dezenas de aprovações dadas no pane. O registro vem do coordenador (log de aprovações da onda), e o relatório do worker não o substitui.
- **Procedimento para o `blocked` do worker `agy`.** `blocked` com diálogo de comando ou de MCP é o estado **esperado** do `agy`, não anomalia ([acompanhamento](../acompanhamento.md#anomalias)). O [vigia](#aprovações-do-coordenador) responde sozinho ao que está na lista e sai com `decisao` no resto (sem vigia, a `espera-onda.sh` acorda pelo `blocked`), e o coordenador:
  1. lê o pane: `herdr pane read <pane> --source visible`;
  2. decide pela regra de prefixo acima, lendo o script antes quando for script novo;
  3. responde pela tecla da opção: `herdr pane send-keys <pane> Enter` aceita a opção selecionada, `down` navega entre as opções e `esc` cancela. **Nunca** a opção que persiste em `settings.json`; confira a opção selecionada no `--source visible` antes do `Enter`;
  4. registra a decisão no log de aprovações da onda, `<pasta da US>/aprovacoes-<papel>.log` (hora, opção, comando, motivo), que é o registro de permissões que vale ([o agente não enxerga as aprovações](#aprovações-do-coordenador));
  5. confere o `settings.json` (regra acima) e rearma a espera.

  Em **modo autônomo**, `blocked` repetido sem decisão possível pela regra (comando fora da regra que não é claramente negável, script que não dá para ler, prefixo amplo) vira **pendência** pelo arquivo, sem aprovar às cegas e sem deixar o worker parado em silêncio.
- **Vigia.** Com worker `agy` ativo, o coordenador roda o [`scripts/vigia-agy.sh`](../../scripts/vigia-agy.sh) em background **no lugar** da `espera-onda.sh` daquele worker. A espera acordaria a cada diálogo, porque o diálogo deixa o agente `blocked`. O vigia lê o pane e responde "uma vez" (opção 1, `Enter`) só ao comando que o [`vigia_agy_classificar.py`](../../scripts/vigia_agy_classificar.py) aprova. Em todo o resto sai com `decisao`, para o coordenador seguir o procedimento acima. Ele também sai no relatório gravado, como a espera:

  ```bash
  scripts/vigia-agy.sh <agente>=<relatório> --log <pasta da US>/aprovacoes-<papel>.log \
    --build-slot <build-slot.sh do projeto> \
    --raiz <worktree> --raiz <pasta da US> --raiz <TMPDIR da US> --raiz ~/.m2/repository   # run_in_background
  ```

  - **Como classifica.** É lista fechada por palavra, não regex sobre o texto:
    - o comando é separado com `shlex` e cortado em `|`, `&&`, `||` e `;`;
    - cada comando precisa estar na tabela do classificador e passar pelo validador dele;
    - antes disso, param `$` (qualquer expansão), crase, barra invertida antes de aspas ou no fim, aspas que não fecham e qualquer outro operador (`&` sozinho, `(`, `<<`, `>|`…);
    - redirecionamento, só `>/dev/null`, `2>&1` e `< arquivo`;
    - caminho com `..` para; caminho absoluto ou com `~` só vale dentro de uma `--raiz`;
    - nome de segredo em qualquer palavra para, sem distinguir caixa (`token`, `secret`, `credenc`, `.env`, `.ssh`, `glab-cli`, `.docker`, `.pgpass`…).

    `vigia-agy.sh --classificar '<comando>' [--build-slot …] [--raiz …]` mostra a decisão sem Herdr.
  - **Aprova uma vez:**
    - git de leitura sem `-O`/`--open*`/`--output`/`--ext-diff`;
    - `grep`, `rg` sem `--pre`, `ls`, `cat`, `head`/`tail`, `wc`, `jq` sem `env`;
    - `find` sem `-exec*`/`-ok*`/`-delete`/`-fprint*`/`-fls`;
    - `sed`, só `sed -n 'N,Mp' arquivo`; `sort` sem `-o`; `uniq` sem arquivo de saída;
    - `ps -p <pid> [-o campos]`, `javap` sem `-J`;
    - `glab api <caminho> [--paginate]` (só GET), `glab mr view <n>`;
    - leituras do `sonar` e do `taiga` sem `--url`, `herdr agent get`;
    - o build pelo caminho de `--build-slot` (`./mvnw`, `mvn`, `go test`, `npm test`, `uv run pytest`…), sem `exec`/`antrun`.

    O build executa o código da worktree por definição: é a mesma confiança dada ao executor, e o vigia só limita o comando do build, não o que os testes fazem.
  - **Para:**
    - todo o resto, inclusive `java`/`javac`/`python` de código escrito pelo agente;
    - nota ou comentário que o revisor vai publicar (o coordenador lê o texto antes);
    - diálogo de MCP ou de arquivo;
    - opção 1 não selecionada logo abaixo de "Run this command?";
    - `blocked` sem diálogo reconhecido.
  - **Comando em mais de uma linha na tela sempre para.** A quebra feita pela largura do pane não se distingue de uma nova linha do comando, que é outro comando. A revisão do PR skills#88 montou telas em que a junção das linhas aprovava `echo a` seguido de `mkdir`.
  - **Enter uma vez só.** Se o diálogo continua na tela 10 s depois do `Enter`, o vigia sai com `decisao` sem reenviar. Se o `send-keys` falha, ele não registra aprovação e sai com `herdr-indisponivel`.
  - **Depois de cada `decisao`:** responda no pane (registrando no mesmo log a hora, a opção, o comando e o motivo) e rearme o vigia. O comando que se repete e é seguro entra na tabela do classificador com um teste em `scripts/tests/vigia-agy.test.sh`, nunca numa exceção feita na hora.
  - **`ocioso`.** O agy fica `idle` enquanto espera uma tarefa em background que ele mesmo lançou (`/tasks` no rodapé). Antes de tratar como anomalia, olhe a tarefa. Na TG-32 era uma JVM de teste presa pelas threads do agendador do Spring depois de terminar os testes.
  - **O que o vigia não vê:** MR mesclada ou fechada e pendência respondida (esta chega pelo aviso do daemon). Quando a espera da onda depende de um merge, arme também a `espera-onda.sh --mr` para outro worker da onda.
  - **Origem:**
    - O ensaio da orq #108 usou um vigia de scratchpad. Na onda 317 (TG-32 do trabalhe-conosco, 2026-11-22), o revisor agy precisou de oito ajustes nele ao longo da revisão.
    - A primeira versão versionada usava lista proibida por regex e foi reprovada na revisão do PR skills#88. Ela aprovava comandos que apagavam ou executavam:
      - `cat x <$(…)`;
      - `&` sozinho;
      - aspas desemparelhadas;
      - `sed -n 1p -e '1e …'`;
      - `git grep -lOrm`;
      - `sort -uo`;
      - linhas juntadas.

      Cada caso virou teste.

## Pré-aprovação com `--settings`

Fonte: documentação pública do `agy` (<https://antigravity.google/docs/permissions.md>, seção "CLI fine-grained permissions"), lida em 2026-11-21 pela orq #109; as skills embutidas em `~/.gemini/antigravity-cli/builtin/skills/` só remetem a essa página. **Não foi testado no ensaio** e **não é o padrão**: o coordenador decide depois se adota.

- **Formato.** `--settings` aceita "um objeto JSON de chaves do `settings.json`, inline ou como caminho de arquivo, só para esta sessão, nunca salvo" (`agy --help`). O `settings.json` tem `permissions` com três listas, `deny`, `ask` e `allow`, de regras `ação(alvo)`. Precedência: **deny > ask > allow**.
  - Ações: `command(prefixo)`, `command(regex:padrão)`, `command(*)`, `read_file`, `write_file`, `read_url`, `execute_url`, `mcp(servidor/ferramenta)`, `mcp(servidor/*)`.
  - `command` casa por prefixo, palavra por palavra. Comando com `$(...)`, crase, expansão de chaves ou outro construto que esconda execução só passa por **correspondência exata da linha inteira**; senão cai em `ask`. Pipeline, `&&`/`;` e redirecionamento simples casam o prefixo (limites abaixo).
- **Limites do casamento por prefixo** (mesma fonte, seção "When commands require an exact match"): "pipelines, `&&`/`||`/`;` chains, quoted literals, plain `$VAR` arguments, **simple file redirects**" **casam o prefixo normalmente**. Então `command(cat)` ou `command(grep)` em `allow` também libera `cat /dev/null > ~/.zshrc` e `grep x y > qualquer-arquivo`: o redirecionamento é escrita do processo, que não passa pelas aprovações de arquivo do `agy`. A avaliação **por segmento** em `a && b` (se cada lado é conferido contra as listas) **não foi testada**; a fonte só dá o exemplo `git status && git log`. Não presuma que o `deny` do segundo lado vale.
- **Exemplo mínimo** (não liberado como padrão e **não testado**): `allow` só com comandos de build e teste; leitura (`ls`, `grep`, `head`, `tail`, `cat`, `find`) vai para `ask`, porque o redirecionamento simples casa o prefixo e `grep x > ~/.zshrc` escreve (acima).

  ```json
  {
    "permissions": {
      "allow": ["command(go test)", "command(go build)", "command(go vet)", "command(npm test)", "command(npm run build)", "command(mvn -B test)"],
      "ask": ["command(git)", "command(gh)", "command(taiga)", "command(herdr)", "command(ls)", "command(grep)", "command(head)", "command(tail)", "command(cat)", "command(find)"],
      "deny": ["command(gh pr merge)", "command(rm)", "command(pkill)", "command(killall)", "command(sudo)"]
    }
  }
  ```

  - Fora do `allow` e em `ask`: `find` (`find . -delete` e `-exec` o casariam) e os de leitura `ls`, `grep`, `head`, `tail` e `cat` (cada um casa com `> arquivo`). Se quiser algum deles em `allow`, restrinja com `regex:`.
  - **Risco assumido nos que sobram em `allow`:** `go test`, `go build`, `go vet`, `npm test`, `npm run build` e `mvn -B test` também casam com `> arquivo`, e `go test ./... > ~/.zshrc` escreve fora das aprovações de arquivo. O exemplo aceita isso porque sem eles o worker não testa nada; para recusar o risco, ponha-os em `ask` e aprove um a um.
  - **O `deny` por prefixo se contorna com variações.** A fonte diz que `command` casa "por palavra ou prefixo de token", literalmente: `command(rm -r)` **não** casa `rm -rf`, nem `rm -fr`, `rm -Rf`, `rm -R` ou `rm --recursive`; `command(git push --force)` não casa `git push origin main --force`, `git push --force-with-lease` nem `git push origin +main`. Por isso o exemplo nega `rm` inteiro e mantém **`git` em `ask`**, e não confia em `deny` de flag. Para o que o coordenador nunca aprova, o `deny` de `command(gh pr merge)` casa o prefixo, mas `gh` já está em `ask` e é a aprovação unitária que protege.
  - `ask` em `git`/`gh` reproduz a regra "um a um" e mantém o `blocked` do Herdr para o coordenador decidir.
  - Antes de adotar, ensaie numa sessão descartável: que `--settings` **mescla** com o `settings.json` global em vez de substituí-lo, que o `deny` vence uma entrada persistida em `allow` e como se comporta `a && b`. Nada disso foi exercitado.
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

No Claude Code, o worker `agy` fica com o [vigia](#aprovações-do-coordenador) (`vigia-agy.sh`) no lugar da `espera-onda.sh`: os dois saem no relatório, mas só o vigia responde aos diálogos sem acordar o coordenador a cada um. O vigia não vê pendência (chega pelo aviso do daemon) nem MR; os workers de outros harnesses na mesma onda continuam na `espera-onda.sh`.

Quando o coordenador for um `agy`: se ele acorda ao fim de um comando em background **não foi testado** (o ensaio teve coordenador Claude Code); sem isso, use o laço do Codex.

## Limite de uso

O texto da mensagem de limite de uso do `agy` é **desconhecido**: nenhuma mensagem apareceu no ensaio da orq #108, e nenhum texto está registrado aqui de propósito. Vale o sinal geral da [troca por limite](../configuracao.md#troca-por-limite): worker parado, sem relatório, com a mensagem de limite do harness no pane. Nunca decida pela cota do rodapé. Registre o texto exato quando aparecer.

## Papéis como agentes nativos

Os papéis `qa-adversarial` e `planejador` são agentes globais do `agy`, lidos de `~/.gemini/config/agents/<papel>/agent.md`.

**Esse arquivo é gerado, não é link.** No ensaio, `agy --agent planejador` carregou o papel (o rodapé mostrou `planejador (Gemini 4 Neon · xhigh)` e a conversa seguiu o papel), mas a sessão ficou só com `read_file` e MCP: sem shell nem escrita, o planejador não gravou o retorno, não rodou `taiga` nem `herdr` e emitiu o retorno no chat. Causa, na skill embutida do `agy` `migrate-agent-settings`: agente **sem `tools` no frontmatter** recebe só um conjunto pequeno de leitura, e para ter todas as ferramentas é preciso `tools: [read_file, edit_file, write_file, run_command, manage_task, search_web]` (com `subagent: true`; o `mainAgent` é tratado a seguir). Os papéis do clone não têm `tools`, e o campo não pode ir neles: no Claude Code ausência quer dizer "todas", e o campo, quando existe, restringe e usa outros nomes (`Read`, `Bash`…).

- **Geração.** `scripts/agy-gerar-papeis.sh` lê `agents/<papel>.md` do clone e grava `~/.gemini/config/agents/<papel>/agent.md` com o frontmatter do `agy` (`name`, `description`, `subagent: true`, `mainAgent: true`, `tools`) e o corpo do papel sem alteração, mais uma marca de arquivo gerado. Descarta `mode`, `model`, `color` e o `tools` do Claude Code.
  - **`mainAgent: true`, e não `false`.** A skill embutida `migrate-agent-settings` (passo "agents/<name>.md") manda `subagent: true` e `mainAgent: false` para que o agente importado "fique subagente". Mas com `mainAgent: false` o `agy agents` **não lista** o papel e `--agent <papel>` não funciona na sessão do worker (conferido em 2026-11-21, orq #111: com `mainAgent: true` os dois papéis voltam à lista). Como o papel aqui é a sessão principal do worker, o gerador grava `true`. `subagent: true` **fica**: é o que a skill manda para todo agente importado e só acrescenta a possibilidade de outro agente invocar o papel; não encontrei na skill nem no `agy --help` nada que diga que ele atrapalhe a seleção por `--agent`, e o critério de aceite (papel listado, com shell e escrita) foi o que se conferiu com os dois campos juntos.
  - **Recusas do gerador (rc 1):** `tools` com padrão entre parênteses (`Bash(git:*)`) ou `disallowedTools` (o `agy` não restringe comando, e o papel ganharia shell irrestrito); `name` vazio ou reservado do `agy` (`self`, `browser`, `research`, `deepagent`, `review-agent`, lista da mesma skill; comparado sem distinguir caixa, então `Self` e `SELF` também caem); `description` sem texto (`""`, só comentário, em lista, `[]`, `{}`, `null`, `~`, dobrada `>-`/`|` só com comentário). Comentário YAML em `tools` (`[Read, Write] # nota`) é ignorado. `--destino` com link no caminho, mesmo com barra final, ou com componente `..` é recusado (rc 3).
  - **Limite conhecido do `--destino` relativo (orq #113, M7).** O caminho relativo é lido a partir do `$PWD` lógico. Com `$HOME` no caminho real (`/var/home/u`) e o `$PWD` entrando por um link (`/home/u`), o link do `$PWD` não é reconhecido como ancestral do `$HOME` e o gerador recusa (rc 3, nada gravado). É falso positivo, que não ocorre aqui (`/home` é diretório real) e só nos sistemas com `/home -> /var/home`; contorno: `--destino` absoluto. Documentado em vez de corrigido, porque resolver o `$PWD` físico deixaria de ver links que a conferência existe para recusar.
  - **Rode de novo depois de cada `git pull` do clone**: a cópia gerada não acompanha o canônico sozinha. Rodar duas vezes não muda nada.
  - Um `agent.md` sem a marca (arquivo da pessoa) é recusado, e um link da instalação antiga da orq #107 só é trocado com `--substituir-link`.
  - Um `agent.md` do primeiro gerador (commit `cc722e9` do PR skills#75, sem o `---` de abertura) seria recusado como arquivo da pessoa (rc 3), e sairia só apagando-o à mão. Não se trata: esse commit nunca foi mesclado, e nenhum arquivo assim existe na máquina (os `agent.md` de lá eram links da orq #107).
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
