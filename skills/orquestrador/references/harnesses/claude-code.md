# Claude Code

Confira `claude --help` e a configuração efetiva antes de iniciar. Selecione modelo/esforço do alias usando opções suportadas na instalação. Skill local pertence ao coordenador; instruções do alvo pertencem ao worker.

## Espera

O Claude Code acorda o turno quando um comando em background termina. Arme a espera ([acompanhamento](../acompanhamento.md#worker-ativo-implica-espera-armada)) como um comando Bash em background e encerre o turno só depois de armá-la:

```bash
shell_em_background() {  # o Claude Code do worker tem um shell filho rodando
  local sid pid
  sid=$(herdr agent get "$1" | jq -r '.result.agent.agent_session.value // empty')
  pid=$(jq -r --arg s "$sid" 'select(.sessionId == $s) | .pid' ~/.claude/sessions/*.json 2>/dev/null | head -1)
  [ -n "$sid" ] && [ -n "$pid" ] && pgrep -P "$pid" -f shell-snapshots >/dev/null
}
parado_desde=
until [ -s <relatorio> ]; do
  st=$(herdr agent get <worker> 2>/dev/null | jq -r '.result.agent.agent_status // empty')
  [ -z "$st" ] && break                                   # pane sumiu
  case "$st" in
    working) parado_desde= ;;
    blocked) break ;;
    *) [ -z "$parado_desde" ] && parado_desde=$(date +%s)
       [ $(( $(date +%s) - parado_desde )) -ge 600 ] && break ;;  # parado 10 min sem relatório
  esac
  sleep 30
done
```

O laço sai com relatório gravado, worker `blocked`, pane sumido ou worker `idle`/`done` sem relatório por 10 min seguidos. A tolerância de 10 min é valor de partida: ela cobre a janela em que o executor está entre um comando e o seguinte, e o contador zera sempre que o worker volta a `working`. Ao acordar, o coordenador confere qual sinal saiu e trata os três últimos (`blocked`, pane sumido, parado) como anomalia ([anomalias](../acompanhamento.md#anomalias)).

A função `shell_em_background` é um atalho opcional: se achar shell em background no processo, o worker não conta como parado. Ela teve falso negativo na Claude Code 2.1.296 (TG-212 do colaboradados, 2026-10-10: duas esperas acordaram como anomalia com o executor ainda no meio da rodada, e ambas voltaram a `working` sozinhas). A causa exata não foi identificada. A hipótese é a janela entre o fim do comando em background e o turno seguinte, ou um comando de espera que não é filho direto do processo da sessão. Por isso o atalho não substitui a tolerância de tempo. Se usá-lo, chame-o no ramo `*)` antes de contar como parado.

O shell em background é conferido pelo processo, não pela tela. A versão 2.1.295 escreve "Running 1 shell command" ou "Ran 1 shell command" no lugar do antigo "shell still running", e o texto muda entre versões: na TG-107 do portal-liven (2026-10-09) a espera acusou anomalia enquanto o executor aguardava a pipeline. O Herdr informa o id da sessão (`agent_session.value`); o Claude Code registra o pid de cada sessão em `~/.claude/sessions/<pid>.json`, e cada comando Bash roda num `zsh`/`bash` filho que carrega um arquivo de `shell-snapshots`. Esses dois detalhes são internos do Claude Code: sem o arquivo da sessão, a função devolve falso. Para vigiar merge, acrescente a consulta do estado da MR ao laço. O harness mata a espera no limite de tempo de background (~2 h) e sob falta de memória: ao receber esse aviso, confira estado e relatório e rearme. Uma pergunta ao usuário pendente (AskUserQuestion) impede reagir ao worker; com worker ativo, pergunte em texto.

## Permissões de worktrees e temporários

A CLI oferece `--add-dir`, `--allowedTools` e `--settings`; confira sintaxe e política vigentes. Configure no escopo do projeto coordenador, com diretórios dos alvos/artefatos explicitamente autorizados. Regras de permissão ficam no perfil do ambiente, não nos aliases de modelo.

Para autorizar comandos Bash do Worktrunk, uma regra específica como `Bash(wt remove *)` pode ser usada quando aceita pela versão instalada, após o usuário aprovar o alcance. Ela permite todas as invocações compatíveis; critérios de limpeza continuam obrigatórios. Prefira helper restrito se for necessário limitar repositórios/branches mecanicamente. Confira também as variantes reais do comando (`wt -C ...`, wrappers), sem ampliar a regra automaticamente.

Para temporários, autorize helper validado restrito à raiz configurada. Sem helper, peça aprovação para comandos com caminhos concretos já verificados. Não permita `Bash(rm *)` para resolver este caso.

`--allowedTools` não garante vencer deny, sandbox ou classificador do modo auto. Inspecione a resposta real; `claude auto-mode --help` permite descobrir ferramentas de diagnóstico sem mudar a política. Uma instrução na skill não modifica permissões efetivas. Alterações de settings seguem a autorização do usuário e a política administrada. Não use bypass de permissões como solução de limpeza.
