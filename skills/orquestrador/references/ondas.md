# Ondas

Onda é um conjunto ordenado de stories que o usuário entrega ao coordenador de uma vez, com a autorização declarada: "enquanto vou dormir pode rodar as próximas (TG-215 a TG-218) e deixar os MRs prontos" (colaboradados, 2026-10-10). Foi a noite em que as quatro MRs amanheceram aprovadas, e as regras abaixo saem dela.

## O contrato

Antes de despachar, confirme com o usuário o que ele não disse e registre o contrato (com a [Central](central.md#do-fluxo-ao-comando), em `orq onda criar` com `--ate`, `--ordem` e `--depende`; sem ela, no registro da missão):

- **Stories e ordem.** A ordem de despacho e, quando houver, a ordem de merge.
- **Até onde ir sem perguntar.** O padrão é MR aprovada, pronta para merge. Merge continua humano, salvo autorização explícita para a onda; transições seguem `[autonomia]` ([configuração](configuracao.md#autonomia-e-transições-automáticas)).
- **Empilhamento.** Se a pessoa autoriza empilhar stories que tocam o mesmo código ([abaixo](#grafo-e-recursos)). "Deixar as MRs prontas" não é essa autorização.
- **O que fica de fora.** Escritas externas que dependem da pessoa viram pendência, não bloqueio da onda. Naquela noite, sem escrita no SGO, a verificação da TG-217 ficou pendente e a implementação seguiu com a alternativa segura.

Dentro do contrato, o coordenador despacha a próxima story elegível (`orq onda proxima`, com a Central) sem nova pergunta, respeitando os limites de `[coordenador]` (`max_executores`, `max_revisores`, `max_builds_pesados`). Pedido explícito do usuário pode ampliar o limite ou encurtar o fluxo para a onda: na subida para a v1.16.0 (2026-10-05), três stories de três projetos correram com três executores simultâneos, contra `max_executores = 2`, e sem revisão, ambos por escolha do usuário. Anote a mudança no registro.

## Grafo e recursos

Monte o grafo antes de lançar, com o que cada story toca, não só com as dependências declaradas no Taiga:

- **Mesmo arquivo ou mesma regra, a base é decisão de quem pediu.** Empilhar faz a MR carregar o diff das duas stories até o merge da primeira e torna a revisão dependente dela; por isso a `basis-ci-gitlab` (`references/worktree.md`, base da branch) reserva a escolha a quem pediu. A decisão pode vir uma vez para a onda, no contrato; sem ela, a dependente aguarda a base. Empilhada, a MR diz qual precisa ser mergeada antes e, depois desse merge, passa por rebase e confirmação do revisor. No colaboradados, a TG-216 foi empilhada sobre a TG-215 por decisão do coordenador, a partir do pedido genérico; esta regra corrige isso.
- **Dependência de conteúdo, espere a aprovação.** A TG-218 precisava dos nomes de coluna da TG-217 e só começou da base depois da MR da TG-217 aprovada.
- **Recurso numerado, reserve.** Com Flyway `outOfOrder=false`, migração de número menor mesclada depois de uma maior é recusada. Reserve os números no início (TG-215 = V037, TG-216 = V038, TG-217 = V039) e torne a ordem de merge obrigatória.
- **Recurso pesado, serialize.** `mvn verify` em fila por `flock`, um revisor por vez.

Sem relação no grafo, as stories correm em paralelo: TG-215 e TG-217 começaram juntas.

## Bloqueio e fechamento

Pendência ou bloqueio de uma story não para as independentes; só as dependentes esperam. Registre a pendência com id ([bloqueios](acompanhamento.md#bloqueios-e-recorrência)) e siga.

Ao terminar a onda, entregue uma tabela na ordem de merge: story, URL completa da MR, resultado da revisão com os achados restantes, SHA da cabeça, e o que cada merge exige da seguinte (rebase, pipeline nova, confirmação curta do revisor sobre o delta). Em colaboradados, depois de cada merge humano a MR seguinte foi rebaseada, e o revisor confirmou o delta antes do merge seguinte. MR aprovada aguardando merge entra no [vigia de merge](acompanhamento.md#vigia-de-merge). Com a Central, a onda termina com o [encerramento](central.md#encerrar-a-onda), não com a tabela.
