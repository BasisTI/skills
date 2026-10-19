# Acompanhamento

Use `herdr agent get/read` para estado e saída, conforme a skill `herdr`. `done` ou `idle` significa disponível para entrada, não story entregue. Confira relatório, tarefas em background e pipeline antes de concluir a rodada.

Envie o prompt uma vez; um timeout pode acontecer depois da entrega. Consulte estado e saída antes de repetir. Nas TG-225 e TG-312 do convey, todos os `agent prompt --wait` deram timeout com o agente já `working`, e o prompt tinha sido entregue. `--timeout` só vale junto com `--wait`: sem ele, a CLI recusa o comando e nada é enviado.

## Worker ativo implica espera armada

Com worker trabalhando, o coordenador não encerra o turno sem uma espera armada que o acorde. Encerrar dizendo "o executor está trabalhando" deixa a rodada dependendo do usuário: na TG-63 foram 11,4 h parado em 3 episódios. A receita depende do harness: [Claude Code](harnesses/claude-code.md#espera) espera em background com notificação; [Codex](harnesses/codex.md#espera) não acorda um turno encerrado e faz o laço dentro do turno.

A espera termina por um destes sinais, conferidos a cada volta:

- relatório da rodada gravado no caminho do pacote (no planejamento, o `retorno-planejamento.md`);
- worker `idle`, `done` ou `blocked` (`herdr agent wait <worker> --timeout <ms>`);
- MR aprovada mesclada (vigia de merge, abaixo).

O Herdr às vezes não reconhece o estado final do Codex; por isso a espera também confere o arquivo do relatório e usa timeout curto com rearme, nunca espera indefinida.

## Anomalias

- Worker `idle`/`done` sem relatório é anomalia só depois de uma tolerância de tempo: 10 min parado seguidos, como valor de partida no [perfil Claude Code](harnesses/claude-code.md#espera). `working` zera o contador. Não basta a tela: o texto do shell em background muda entre versões ("shell still running" no piloto de 2026-09-30, "Running 1 shell command" na 2.1.295), e a conferência por processo já teve falso negativo na 2.1.296 (TG-212 do colaboradados, 2026-10-10: duas esperas acordaram como anomalia com o executor ainda trabalhando). Por isso a regra é o tempo parado, não o shell. Passada a tolerância sem relatório, é anomalia: leia a saída e decida — pedir o relatório, relançar ou bloquear.
- Revisor Codex encerrado pelo filtro do provedor ("flagged for possible cybersecurity risk") não grava relatório. Primeiro, se o worker já gravou reproduções ou achados, peça à mesma sessão que grave o relatório com o que já tem, sem continuar a investigação; na TG-212 isso deu relatório completo. Se o bloqueio voltar na mesma story, é a mesma classe de falha: troque de harness pelo fallback configurado e registre o motivo. Sem fallback configurado e com escolha explícita do usuário, pergunte a ele antes de trocar. A espera de 10 min acima detecta o caso (o Codex fica `done` sem relatório). Não espere o arquivo até o limite: na TG-22 a rodada perdida custou 2 h.
- Worker parado num ponto humano, com a pergunta escrita no pane, está num estado esperado e não numa anomalia. Repasse a pergunta ao usuário com o id da pendência ([bloqueios](#bloqueios-e-recorrência); a conversa do planejador não tem id) e rearme uma espera de retomada. A retomada exige `working` sustentado, por exemplo duas leituras com 30 s de intervalo. A compactação ociosa do Claude Code ("Compacted while idle" seguida do recap) põe o worker em `working` por instantes sem que ele retome. Na TG-225 do convey (2026-10-09), um único `working` acordou o coordenador com o executor ainda à espera da pessoa.
- Espera morta pelo harness (limite de tempo, falta de memória) não é fim da rodada: confira estado e relatório e rearme.

## Vigia de merge

MR aprovada aguardando merge entra na mesma espera: o merge é da pessoa, ou do coordenador quando a MR é para uma branch de `merge_automatico` e as condições valem no head ([configuração](configuracao.md#merge_automatico)). A cada volta, consulte o estado: `glab mr view <url> --output json | jq -r .state` (GitLab) ou `gh pr view <url> --json state -q .state` (GitHub, em maiúsculas). Em `merged`, siga o pós-merge sem esperar aviso: auditoria, transições automáticas configuradas e dependentes ([conclusão](conclusao-e-limpeza.md#auditoria-proativa)); a [limpeza](conclusao-e-limpeza.md#limpeza-depois-do-merge) é do daemon, e sem ele você roda `orq limpar`. Em `closed`, informe o usuário.

## Status na sidebar

Com a [Central](central.md), o daemon do `orq` publica a sidebar e o coordenador não publica nada; ao migrar, ele [aposenta](central.md#com-ou-sem-central) os tokens que já tinha publicado. Sem ela, a cada mudança de fase, publique o status no pane do worker e as MRs prontas no workspace:

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

Pendências da pessoa: dúvida, pedido de autorização ou decisão que o worker precisa da pessoa ganha um id `P1`, `P2`, … sequencial na story, que não reinicia entre rodadas; o pacote traz as abertas e o próximo id livre. O worker escreve o id no pane e no relatório e avisa o coordenador ao abrir a pendência e ao considerá-la respondida, no formato e com a restrição do [aviso](despacho.md#aviso-ao-coordenador). Com o coordenador ocupado, o aviso não sai, e a espera encontra a pendência no pane parado ou no relatório. O coordenador mantém a lista aberta na [Central](central.md#do-fluxo-ao-comando) (`orq pend add`/`resolver`) ou, sem ela, no registro da missão, e a repassa ao usuário com story e id ("TG-217 P1: …"). Sem id, a pendência some no texto: na noite das TG-215 a TG-218 do colaboradados (2026-10-10), a verificação do SGO da TG-217 ficou registrada só como frase do plano. No planejamento, a pergunta da conversa ao vivo não é pendência: vira `P<n>` o que fica sem resposta e sai no retorno, ou o que o planejador precisa que o coordenador acompanhe ([planejamento](planejamento.md)). O id só identifica; a autorização continua sendo dada pela pessoa no pane, como abaixo.

Autorização da pessoa: a escrita externa que o pacote reserva à pessoa (produção, cliente) é autorizada por ela, direto no pane do worker. O worker recusa a autorização repassada pelo coordenador, como o pacote manda, e o classificador do auto mode também já recusou (TG-224). Quando a pessoa der ao coordenador uma autorização em bloco, peça que ela a escreva no pane, de uma vez, para a lista conhecida de comandos, em vez de repassá-la. Na TG-225 a autorização repassada foi recusada, e a pessoa autorizou as escritas 2 a 6 no pane. Uma ação humana que o coordenador pode fazer com permissão explícita da pessoa (instalar o binário, aplicar a configuração pessoal) ele faz e informa ao worker como fato, deixando claro que isso não autoriza outras escritas. O classificador também pode barrar leituras de produção ("Production Reads", no planejamento da TG-312) e liberá-las em outra sessão. Nesse caso o planejamento transforma a leitura em tarefa do plano, e o executor pergunta à pessoa no pane se for barrado de novo.

Falha recorrente: preserve histórico entre agentes e rodadas e conte por classe, não por caso. Na segunda ocorrência da mesma classe, peça ao executor a correção da classe com as variantes testadas; se a classe voltar, leve a quem pediu uma decisão de desenho, conforme `basis-ci-gitlab`, em vez de mais uma rodada no mesmo desenho. Falha nova não apaga causas anteriores.
