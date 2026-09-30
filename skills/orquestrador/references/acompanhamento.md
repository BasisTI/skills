# Acompanhamento

Use `herdr agent get/read` para estado e saída, conforme a skill `herdr`. `done` ou `idle` significa disponível para entrada, não story entregue. Confira relatório, tarefas em background e pipeline antes de concluir a rodada.

Envie o prompt uma vez; um timeout pode acontecer depois da entrega. Consulte estado e saída antes de repetir. Use esperas limitadas que permitam atualizações ao usuário, evitando polling contínuo.

Reutilize o monitor de pipeline da `basis-ci-gitlab`, com logs no diretório único da rodada. Confira pipeline da MR e revisão atual, job de qualidade efetivamente executado e evidências do relatório. Após push, invalide a validação do SHA anterior.

Persistência: pacote, relatório, evidências, logs e registro de missão com projeto, story, papel, rodada, alias resolvido, pane, worktree, MR, SHA e pipeline. O pacote pede relatório em arquivo para sobreviver ao encerramento do pane; se a skill Herdr vigente orientar somente saída no pane, registre essa adaptação explícita no pacote autorizado.

Bloqueio de permissão: informe ação, motivo real e camada que recusou; use o mecanismo de aprovação disponível. Uma autorização de tarefa não contorna deny/sandbox. Continue trabalho independente. Após rejeição da revisão automática, não repita a mesma ação disfarçada; apresente o que permanece bloqueado.

Falha recorrente: preserve histórico entre agentes e rodadas. Na segunda ocorrência da mesma causa, informe a recorrência ao executor e solicite correção da causa; na terceira, interrompa conforme `basis-ci-gitlab`. Falha nova não apaga causas anteriores.
