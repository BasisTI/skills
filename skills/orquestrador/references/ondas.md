# Ondas

Onda é um conjunto ordenado de stories que o usuário entrega ao coordenador de uma vez, com a autorização declarada: "enquanto vou dormir pode rodar as próximas (TG-215 a TG-218) e deixar os MRs prontos" (colaboradados, 2026-10-10). Foi a noite em que as quatro MRs amanheceram aprovadas, e as regras abaixo saem dela.

## O contrato

Antes de despachar, confirme com o usuário o que ele não disse e dê à onda um nome e ao pane do coordenador o rótulo e o nome de agente dela ([nomes dos panes](despacho.md#nomes-dos-panes)) e registre o contrato (com a [Central](central.md#do-fluxo-ao-comando), em `orq onda criar` com `--ate`, `--ordem` e `--depende`; sem ela, no registro da missão):

- **Stories e ordem.** A ordem de despacho e, quando houver, a ordem de merge.
- **Até onde ir sem perguntar.** O padrão é MR aprovada, pronta para merge; onde `merge_automatico` lista a branch de destino, o merge também entra, e a onda segue até o pós-merge ([condições](configuracao.md#merge_automatico)). Merge em outra branch (`main`, `staging`) continua humano, mesmo com autorização para a onda; transições seguem `[autonomia]` ([configuração](configuracao.md#autonomia-e-transições-automáticas)).
- **Empilhamento.** Se a pessoa autoriza empilhar stories que tocam o mesmo código ([abaixo](#grafo-e-recursos)). "Deixar as MRs prontas" não é essa autorização.
- **O que fica de fora.** Escritas externas que dependem da pessoa viram pendência, não bloqueio da onda. Naquela noite, sem escrita no SGO, a verificação da TG-217 ficou pendente e a implementação seguiu com a alternativa segura.

Dentro do contrato, o coordenador despacha a próxima story elegível (`orq onda proxima`, com a Central) sem nova pergunta, respeitando os limites de `[coordenador]` (`max_executores`, `max_revisores`, `max_builds_pesados`). Pedido explícito do usuário pode ampliar o limite ou encurtar o fluxo para a onda: na subida para a v1.16.0 (2026-10-05), três stories de três projetos correram com três executores simultâneos, contra `max_executores = 2`, e sem revisão, ambos por escolha do usuário. Anote a mudança no registro.

## Acrescentar story à onda aberta

Story que surge no meio da onda (uma menor descoberta ao trabalhar em outra) e que o usuário manda "adicionar à onda atual" entra na onda existente, sem criar onda nova nem encerrar a atual. Confirme com o usuário a onda e, se importar, o ponto da ordem; sem ponto, ela vai para o fim. Com a [Central](central.md#do-fluxo-ao-comando), use `orq onda adicionar <id> <ref>… [--apos <ref>]`: a story entra em `wait` (ou guarda o status, se veio de onda encerrada de mesmo limite), o diário registra `onda.adicionar`, e `orq onda proxima` e a regra de [encerramento](central.md#encerrar-a-onda) passam a contar com ela, o que tira a onda do estado de pronta para encerrar até a story chegar ao limite.

- **A autorização é a da onda.** A story herda `--ate`, `--ordem` e o contrato; se ela pede limite diferente, é onda à parte.
- **Exige o binário novo.** O `orq` anterior à US #42 do projeto `orq` não conhece o subcomando: imprime a ajuda de `orq onda` e sai com 0, sem adicionar nada. Confira sempre com `orq onda ver <id>` que a story entrou, e o comando aparece em `orq onda --help` só no binário novo.
- **Em onda estrita, `--apos` pode passar à frente de story em andamento.** Com a 1 em `done`, a 2 em `exec` e a 3 em `wait`, `adicionar … --apos 1` faz `orq onda proxima` devolver a nova com a 2 ainda em `exec`: duas em paralelo numa onda estrita. Para ficar atrás de tudo, não use `--apos`.
- **Dependências não vêm junto.** O comando não cria dependência. Se a nova depende de outra, ou outra dela, e a ordem for `estrita`, use `--apos` para pô-la depois da base e registre a dependência no contrato.
- **Recusas.** Onda encerrada (`onda_encerrada`): crie outra com `orq onda criar`. Story em outra onda aberta (`us_em_outra_onda`): encerre aquela onda ou decida com o usuário de qual ela é. Story já nesta onda (`us_ja_na_onda`): nada a fazer. Story vinda de onda encerrada com o mesmo limite guarda o status que tinha; com limite diferente volta a `wait`.
- **Sem a Central**, acrescente a story à lista do registro da missão e ao contrato, com a data.

## Épico da onda

Quando a onda agrupa as stories sob um épico, ou o usuário pede um épico para ela, o módulo de Epics precisa estar ligado no board. Confira antes de criar ou vincular:

```bash
taiga api GET projects/<id> --project <slug>    # procure is_epics_activated no JSON
```

O `<id>` é o do projeto no Taiga (`taiga project list` mostra slug e id). Com `is_epics_activated=false`, `taiga epic list` e `taiga epic link` não funcionam naquele board. Ligar o módulo muda a configuração do board inteiro, não só a onda: **peça permissão ao usuário** (e confirme que ele é admin do projeto) antes de rodar:

```bash
taiga api PATCH projects/<id> -F is_epics_activated=true
```

- **Sem `--auto-version`.** O projeto não tem campo de versão: com a flag, o PATCH falha com "resource has no version field". Nas stories e épicos, que têm versão, a flag continua valendo.
- **Releia depois.** Repita o `GET` e confirme `is_epics_activated=true`; PATCH aceito sem a releitura não prova a mudança.
- **Board recusado.** Sem permissão de admin o Taiga devolve 403: registre o board como pendência com id ([bloqueios](acompanhamento.md#bloqueios-e-recorrência)) e siga com as stories sem épico.

Em 2026-11-08 os 11 boards que estavam sem Epics foram ligados dessa forma, com autorização do usuário (orq #43).

## Grafo e recursos

Monte o grafo antes de lançar, com o que cada story toca, não só com as dependências declaradas no Taiga:

- **Mesmo arquivo ou mesma regra, a base é decisão de quem pediu.** Empilhar faz a MR carregar o diff das duas stories até o merge da primeira e torna a revisão dependente dela; por isso a `basis-ci-gitlab` (`references/worktree.md`, base da branch) reserva a escolha a quem pediu. A decisão pode vir uma vez para a onda, no contrato; sem ela, a dependente aguarda a base. Empilhada, a MR diz qual precisa ser mergeada antes e, depois desse merge, passa por rebase e confirmação do revisor. No colaboradados, a TG-216 foi empilhada sobre a TG-215 por decisão do coordenador, a partir do pedido genérico; esta regra corrige isso.
- **Dependência de conteúdo, espere a aprovação.** A TG-218 precisava dos nomes de coluna da TG-217 e só começou da base depois da MR da TG-217 aprovada.
- **Recurso numerado, reserve.** Com Flyway `outOfOrder=false`, migração de versão menor mesclada depois de uma maior é recusada. Migração Flyway com a ref da story na versão não colide, mas a ordem ainda é a da versão ([convenção](../../basis-spring-app/references/flyway-modulith-notes.md#naming)); para o que continua numerado (TG-215 = V037, TG-216 = V038, TG-217 = V039), reserve os números no início e torne a ordem de merge obrigatória.
- **Recurso pesado, serialize.** `mvn verify` em fila por `flock`, um revisor por vez.

Sem relação no grafo, as stories correm em paralelo: TG-215 e TG-217 começaram juntas.

## Bloqueio e fechamento

Pendência ou bloqueio de uma story não para as independentes; só as dependentes esperam. Registre a pendência com id ([bloqueios](acompanhamento.md#bloqueios-e-recorrência)) e siga.

Ao terminar a onda, entregue uma tabela na ordem de merge: story, URL completa da MR, resultado da revisão com os achados restantes, SHA da cabeça, e o que cada merge exige da seguinte (rebase, pipeline nova, confirmação curta do revisor sobre o delta). Se as MRs formam série empilhada (autorizada acima), só a próxima da fila é anunciada como pronta e sai do Draft, e as demais ficam em Draft com `Mesclar depois de <MR anterior>`; MRs independentes não ganham pré-condição ([regra](../../basis-ci-gitlab/references/revisao-da-mr.md#pronta-não-convive-com-draft)). Em colaboradados, depois de cada merge humano a MR seguinte foi rebaseada, e o revisor confirmou o delta antes do merge seguinte. MR aprovada aguardando merge entra no [vigia de merge](acompanhamento.md#vigia-de-merge). Com a Central, a onda termina com o [encerramento](central.md#encerrar-a-onda), não com a tabela.
