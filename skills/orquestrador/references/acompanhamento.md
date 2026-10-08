# Acompanhamento

Use `herdr agent get/read` para estado e saída, conforme a skill `herdr`. `done` ou `idle` significa disponível para entrada, não story entregue. Confira relatório, tarefas em background e pipeline antes de concluir a rodada.

Envie o prompt uma vez; um timeout pode acontecer depois da entrega. Consulte estado e saída antes de repetir.

## Worker ativo implica espera armada

Com worker trabalhando, o coordenador não encerra o turno sem uma espera armada que o acorde. Encerrar dizendo "o executor está trabalhando" deixa a rodada dependendo do usuário: na TG-63 foram 11,4 h parado em 3 episódios. A receita depende do harness: [Claude Code](harnesses/claude-code.md#espera) espera em background com notificação; [Codex](harnesses/codex.md#espera) não acorda um turno encerrado e faz o laço dentro do turno.

A espera termina por um destes sinais, conferidos a cada volta:

- relatório da rodada gravado no caminho do pacote;
- worker `idle`, `done` ou `blocked` (`herdr agent wait <worker> --timeout <ms>`);
- MR aprovada mesclada (vigia de merge, abaixo).

O Herdr às vezes não reconhece o estado final do Codex; por isso a espera também confere o arquivo do relatório e usa timeout curto com rearme, nunca espera indefinida.

## Anomalias

- Worker `idle`/`done` sem relatório é anomalia, não espera. Leia a saída com `herdr agent read` e decida: pedir o relatório, relançar ou bloquear.
- Revisor Codex encerrado pelo filtro do provedor ("flagged for possible cybersecurity risk") não grava relatório. Relance ou troque de harness pelo fallback configurado e registre o motivo. Não espere o arquivo até o limite: na TG-22 a rodada perdida custou 2 h.
- Espera morta pelo harness (limite de tempo, falta de memória) não é fim da rodada: confira estado e relatório e rearme.

## Vigia de merge

MR aprovada aguardando merge humano entra na mesma espera. A cada volta, consulte o estado: `glab mr view <url> --output json | jq -r .state` (GitLab) ou `gh pr view <url> --json state -q .state` (GitHub, em maiúsculas). Em `merged`, siga o pós-merge sem esperar aviso: auditoria, transições automáticas configuradas e dependentes ([conclusão](conclusao-e-limpeza.md#auditoria-proativa)). Em `closed`, informe o usuário.

## Status na sidebar

A cada mudança de fase, publique o status no pane do worker e as MRs prontas no workspace:

```bash
herdr pane report-metadata <pane> --source orquestrador \
  --token story=TG-xx --token "fase=revisão r3"
herdr workspace report-metadata "$HERDR_WORKSPACE_ID" --source orquestrador \
  --token "mrs_prontas=!323 !331"
```

Os valores são só exibição: até 80 caracteres e somem quando o servidor do Herdr reinicia. A fonte de verdade é o registro da missão; republique a partir dele quando faltar. Sem as linhas `$story`, `$fase` e `$mrs_prontas` na configuração do Herdr, nada aparece ([configuração](configuracao.md#status-na-sidebar-do-herdr)).

## Pipeline e persistência

Reutilize o monitor de pipeline da `basis-ci-gitlab`, com logs no diretório único da rodada. Confira pipeline da MR e revisão atual, job de qualidade efetivamente executado e evidências do relatório. Após push, invalide a validação do SHA anterior.

Persistência: pacote, relatório, evidências, logs e registro de missão com projeto, story, papel, rodada, alias resolvido, pane, worktree, MR, SHA e pipeline. O pacote pede relatório em arquivo para sobreviver ao encerramento do pane; se a skill Herdr vigente orientar somente saída no pane, registre essa adaptação explícita no pacote autorizado.

## Bloqueios e recorrência

Bloqueio de permissão: informe ação, motivo real e camada que recusou; use o mecanismo de aprovação disponível. Uma autorização de tarefa não contorna deny/sandbox. Continue trabalho independente. Após rejeição da revisão automática, não repita a mesma ação disfarçada; apresente o que permanece bloqueado.

Falha recorrente: preserve histórico entre agentes e rodadas e conte por classe, não por caso. Na segunda ocorrência da mesma classe, peça ao executor a correção da classe com as variantes testadas; se a classe voltar, leve a quem pediu uma decisão de desenho, conforme `basis-ci-gitlab`, em vez de mais uma rodada no mesmo desenho. Falha nova não apaga causas anteriores.
