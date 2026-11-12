# Claude Code

Confira `claude --help` e a configuração efetiva antes de iniciar. Selecione modelo/esforço do alias usando opções suportadas na instalação. Skill local pertence ao coordenador; instruções do alvo pertencem ao worker.

## Espera

O Claude Code acorda o turno quando um comando em background termina. Arme a espera ([acompanhamento](../acompanhamento.md#worker-ativo-implica-espera-armada)) com o [`espera-onda.sh`](../../scripts/espera-onda.sh), como comando Bash com `run_in_background`, e encerre o turno só depois de armá-la. Não reescreva o laço: o Bash tool roda em zsh, e o laço improvisado já morreu por isso (`${!R[@]}`, "bad substitution"). O cabeçalho do script traz parâmetros e códigos de saída:

```bash
<skill>/scripts/espera-onda.sh <worker>=<relatorio> [--onda <id>] [--mr <url>]
```

Ao acordar, leia a linha final (`espera-onda: sinal=<nome> …`) e o código de saída. Relatório, pendência respondida e MR mesclada ou fechada seguem o fluxo normal; `blocked`, pane sumido e parado são anomalia ([anomalias](../acompanhamento.md#anomalias)). Os 10 min de `--parado-s` são valor de partida: cobrem a janela em que o executor está entre um comando e o seguinte, e o contador zera sempre que o worker volta a `working`.

Não há atalho por "shell em background": a conferência pelo processo (`pgrep -P … shell-snapshots`) teve falso negativo na Claude Code 2.1.296 (TG-212 do colaboradados, 2026-10-10: duas esperas acordaram como anomalia com o executor ainda no meio da rodada), o texto da tela muda entre versões ("shell still running", "Running 1 shell command" na 2.1.295; TG-107 do portal-liven, 2026-10-09) e Monitor e subagentes em background não aparecem como shell filho (TG-225 do convey, 2026-10-09: executor `done` com o Monitor esperando a pipeline). A regra é o tempo parado.

O harness mata a espera no limite de tempo de background (~2 h) e sob falta de memória: o script tem limite próprio (`--limite-s`, padrão 6600) e, ao receber o aviso de espera morta, você confere estado e relatório e rearma. Uma pergunta ao usuário pendente (AskUserQuestion) impede reagir ao worker; com worker ativo, pergunte em texto.

## Permissões de worktrees e temporários

A CLI oferece `--add-dir`, `--allowedTools` e `--settings`; confira sintaxe e política vigentes. Configure no escopo do projeto coordenador, com diretórios dos alvos/artefatos explicitamente autorizados. Regras de permissão ficam no perfil do ambiente, não nos aliases de modelo.

Para autorizar comandos Bash do Worktrunk, uma regra específica como `Bash(wt remove *)` pode ser usada quando aceita pela versão instalada, após o usuário aprovar o alcance. Ela permite todas as invocações compatíveis; critérios de limpeza continuam obrigatórios. Prefira helper restrito se for necessário limitar repositórios/branches mecanicamente. Confira também as variantes reais do comando (`wt -C ...`, wrappers), sem ampliar a regra automaticamente.

Para temporários, autorize helper validado restrito à raiz configurada. Sem helper, peça aprovação para comandos com caminhos concretos já verificados. Não permita `Bash(rm *)` para resolver este caso.

`--allowedTools` não garante vencer deny, sandbox ou classificador do modo auto. Inspecione a resposta real; `claude auto-mode --help` permite descobrir ferramentas de diagnóstico sem mudar a política. Uma instrução na skill não modifica permissões efetivas. Alterações de settings seguem a autorização do usuário e a política administrada. Não use bypass de permissões como solução de limpeza.
