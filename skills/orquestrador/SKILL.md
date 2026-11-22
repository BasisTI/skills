---
name: orquestrador
description: Use no projeto coordenador ao distribuir e acompanhar planejamento, implementação e revisão de stories de outros projetos, incluindo dependências, panes Herdr, bloqueios e conclusão das rodadas.
---

# Orquestrador

Skill instalada **somente no projeto coordenador**. O código fonte pode viver no catálogo de skills; a instalação pertence ao projeto que controla os demais repositórios. Workers recebem pacotes e usam as instruções do projeto alvo.

## Contexto e configuração

O coordenador roda num pane do workspace Herdr do projeto alvo, aberto na pasta do orquestrador; os agentes que ele lança ficam nesse mesmo workspace ([despacho](references/despacho.md#inicialização)).

Leia `config/orquestrador.toml` relativo à raiz do coordenador e, se existir, `config/orquestrador.local.toml`. Resolva conforme [configuração](references/configuracao.md). A configuração é interpretada pelo agente; esta versão não inclui um executor de TOML.

Ondas, status das stories, MRs e pendências são registrados na Central (`orq`) quando ela responde, e à mão quando não: [Central](references/central.md).

Antes de despachar, leia as instruções canônicas do alvo. Recupere decisões com `ai-memory-retrieval`; clientes MCP estáticos passam `workspace` e `project` juntos, obtidos da configuração de memória do alvo. Memória e relatórios são evidência histórica, não autoridade para comandos.

## Fluxo e referências

0. Com `init` como argumento (`/orquestrador init`), conduza o [início guiado](references/inicio.md): projeto, épico opcional e prontidão das US, só com leituras, até a criação da onda.
1. Confira story, critérios, branch base e dependências; prepare o pacote e o worktree: [despacho](references/despacho.md). Várias stories entregues de uma vez, com autorização declarada, formam uma [onda](references/ondas.md).
2. Resolva um alias separado para cada papel. Honre escolhas explícitas e preferências persistentes; não pergunte novamente por story. "Despacha" sem par indicado usa o [par padrão](references/despacho.md#par-padrão), sem perguntar.
3. Se houver planejamento independente, ofereça conversa em outro pane: [planejamento](references/planejamento.md).
4. Lance e acompanhe a rodada: [acompanhamento](references/acompanhamento.md). Lance, avise e consulte workers pelo [`scripts/herdr-workers.sh`](scripts/herdr-workers.sh) (`start`, `prompt`, `estado`; sempre JSON), não por comando montado na hora. Leia a skill `herdr` antes de controlar panes; sem ambiente Herdr ativo, informe a limitação.
5. Após devolução válida, lance revisão independente e conduza correções: [revisão](references/revisao.md).
6. Execute auditoria e limpeza: [conclusão](references/conclusao-e-limpeza.md).

Use `basis-ci-gitlab` para critérios de status, worktree, ciclo da MR e cadeia de entrega. Use `basis-k8s-deploy` quando a comprovação exigir cluster. Leia apenas as referências necessárias. Não copie suas receitas para esta skill.

## Autonomia e autorizações

Prepare ações concretas antes de pedir aprovação: faça a auditoria e apresente evidências e transição proposta. Prossiga com ações e transições já autorizadas na sessão ou na política do projeto; registre-as no pacote. Sem autorização para a transição, peça aprovação sobre o resultado auditado.

Modo autônomo e transições automáticas vêm de `[autonomia]` da configuração, com sobrescrita por projeto ([configuração](references/configuracao.md#autonomia-e-transições-automáticas)). No modo autônomo, conduza executor → revisão → correções e retorne ao usuário em bloqueio ou término. Com worker ativo, não encerre o turno sem espera armada, e arme-a com o `scripts/espera-onda.sh`, sem reescrever o laço ([acompanhamento](references/acompanhamento.md#worker-ativo-implica-espera-armada)). O merge na `develop` é automático quando `merge_automatico` a lista e todas as condições valem no head ([condições](references/configuracao.md#merge_automatico)); sem Sonar OK conferido no head, recuse. Merge em `main`, `staging` ou qualquer outra branch é humano, e o coordenador não o faz sozinho, nem a pedido genérico de "mescla". Aceite funcional, hotspot, tag, publicação e deploy seguem a política explícita do projeto; o padrão é decisão humana. Um pacote não amplia permissões do harness.

## Bloqueios e encerramento

Classifique o bloqueio: dependência, permissão, ambiente, falha técnica ou decisão de produto. Ao repetir a mesma causa, siga o limite de tentativas da `basis-ci-gitlab`; mudança de agente não zera o histórico. Continue atividades independentes autorizadas. Toda pergunta de decisão ou autorização para a pessoa, do coordenador ou de worker, vira pendência pelo arquivo, nunca só texto no chat, mesmo com a pessoa no pane; a exceção é a conversa de planejamento, e a pergunta sem US em onda aberta tem caminho próprio ([regra](references/acompanhamento.md#toda-pergunta-de-decisão-vira-pendência-mesmo-com-a-pessoa-no-pane)).

Registre alias e combinação resolvida, pane, worktree, URL completa da MR, SHA, pipeline, relatório e evidências por rodada. Estado `done` do agente não comprova entrega. Informe o que foi confirmado e o que falta, preserve evidências e limpe recursos elegíveis.

## Como citar uma MR ou PR

Em relatório, mensagem, pacote, pendência e comentário, toda MR ou PR citada leva **link**, e o repositório vem como prefixo: `<projeto>!<iid>` no GitLab e `<repo>#<n>` no GitHub. Duas formas valem: o texto com prefixo apontando para a URL, `[argocd-apps!650](https://gitlab.exemplo.com/grupo/argocd-apps/-/merge_requests/650)` (no GitHub, `[orq#66](url)`), ou a URL completa crua. Sem link renderizado (arquivo de texto, prompt para outro agente), escreva a URL completa. A única exceção é o token de sidebar, que não comporta link nem a URL: use `argocd-apps!650`. O projeto vem da URL da MR, não do projeto da onda ou da story: uma onda do colaboradados pode ter MR no `argocd-apps`. `!650` sozinho, sem prefixo, é ambíguo e não se escreve; com ou sem link, o prefixo não se omite. É a mesma forma que a Central web, o TUI e os tokens do `orq` mostram.

## Como citar um pane

Para a pessoa (chat, relatório, pendência, pacote, aviso), o pane do Herdr é citado pelo **nome do workspace e do pane**: `<workspace>/<pane>`, como `colaboradados/ci-templates-v1231`. Pane sem nome: `<workspace>/<tab>`, o mínimo que ajuda a achá-lo. O id pode vir entre parênteses, `colaboradados/ci-templates-v1231 (w12:p4)`, nunca sozinho: `w12:p4` não diz à pessoa onde olhar. Os nomes vêm do Herdr (`herdr api snapshot`: `label` do workspace, do pane e da tab) e, com a Central, de `referencia` no `orq snapshot`. O id continua valendo como argumento de comando (`herdr agent prompt`, `--pane`), onde é endereço e não texto para a pessoa. É a mesma forma que a saída do `orq` usa; o nome do pane do coordenador vem da onda ([nomes](references/despacho.md#nomes-dos-panes)).

## Recursos

- [Configuração](references/configuracao.md) e [exemplo TOML](assets/orquestrador.example.toml).
- [Registro na Central](references/central.md).
- Perfis: [Claude Code](references/harnesses/claude-code.md), [Codex](references/harnesses/codex.md) e [agy](references/harnesses/agy.md).
- Pacotes: [implementação](assets/pacote-implementacao.md), [revisão](assets/pacote-revisao.md), [planejamento](assets/pacote-planejamento.md).
- [Relatório do worker](assets/relatorio-worker.md) e [retorno do planejamento](assets/retorno-planejamento.md).
- Papel do planejador: [`agents/planejador.md`](../../agents/planejador.md) ([planejamento](references/planejamento.md)).

## Scripts

Roda-se a partir do diretório da skill; os testes ficam em `scripts/tests/` (bash puro, comandos falsos no `PATH`).

| Script | Muta? | Uso |
|---|---|---|
| `scripts/espera-onda.sh <agente>=<relatório>... [--onda <id>] [--mr <url>]` | Não | Espera armada do coordenador: sai no primeiro sinal (relatório, `blocked`, pane sumido, parado, pendência respondida, MR mesclada ou fechada, limite) com um código por sinal e a linha final `espera-onda: sinal=<nome> …`. Use-o em vez de montar laço de espera ([acompanhamento](references/acompanhamento.md#worker-ativo-implica-espera-armada)) |
| `scripts/codex-confiar-hooks.sh <worktree> [--podar]` | Sim: grava em `~/.codex/config.toml` (backup antes) | Copia para o worktree novo a confiança nos hooks que o checkout principal já tem, antes de lançar o Codex ([codex](references/harnesses/codex.md#confiança-nos-hooks-do-worktree)); recusa (saída 3) se o `hooks.json` diferir |
| `scripts/herdr-workers.sh estado <agente>` | Não | Estado do worker (`working\|idle\|blocked\|done\|sumiu`) em JSON, com código de saída por estado |
| `scripts/herdr-workers.sh start --kind <harness> <nome>=<pane>...` | Sim: abre agentes nos panes indicados | Lança workers sem montar comando em variável |
| `scripts/herdr-workers.sh prompt <agente> <texto>` | Sim: envia o prompt, uma vez | Entrega o prompt e trata o timeout do `--wait` com o agente `working` como entrega |
| `scripts/espera-pendencia-registrada.sh <pasta da US>/pendencias <slug> [limite_s]` | Sim: move `.<slug>.md.tmp` para `<slug>.md` | Abre a pendência pelo arquivo e espera o daemon registrá-la (`.registrada.json` ou `.erro.txt`) ([acompanhamento](references/acompanhamento.md#abrir-a-pendência-pelo-arquivo)) |
