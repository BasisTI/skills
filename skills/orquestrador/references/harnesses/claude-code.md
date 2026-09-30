# Claude Code

Confira `claude --help` e a configuração efetiva antes de iniciar. Selecione modelo/esforço do alias usando opções suportadas na instalação. Skill local pertence ao coordenador; instruções do alvo pertencem ao worker.

## Permissões de worktrees e temporários

A CLI oferece `--add-dir`, `--allowedTools` e `--settings`; confira sintaxe e política vigentes. Configure no escopo do projeto coordenador, com diretórios dos alvos/artefatos explicitamente autorizados. Regras de permissão ficam no perfil do ambiente, não nos aliases de modelo.

Para autorizar comandos Bash do Worktrunk, uma regra específica como `Bash(wt remove *)` pode ser usada quando aceita pela versão instalada, após o usuário aprovar o alcance. Ela permite todas as invocações compatíveis; critérios de limpeza continuam obrigatórios. Prefira helper restrito se for necessário limitar repositórios/branches mecanicamente. Confira também as variantes reais do comando (`wt -C ...`, wrappers), sem ampliar a regra automaticamente.

Para temporários, autorize helper validado restrito à raiz configurada. Sem helper, peça aprovação para comandos com caminhos concretos já verificados. Não permita `Bash(rm *)` para resolver este caso.

`--allowedTools` não garante vencer deny, sandbox ou classificador do modo auto. Inspecione a resposta real; `claude auto-mode --help` permite descobrir ferramentas de diagnóstico sem mudar a política. Uma instrução na skill não modifica permissões efetivas. Alterações de settings seguem a autorização do usuário e a política administrada. Não use bypass de permissões como solução de limpeza.
