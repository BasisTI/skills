# Revisão independente

Carregue `basis-ci-gitlab/references/revisao-da-mr.md`: ela define elegibilidade, papel `qa-adversarial`, severidades, discussões, Draft, devolução e repetição de achados. Preserve as exceções `config` e o fluxo de stories `review` definidos ali.

O pacote delimita a rodada conforme as seções "Severidade ancorada no ambiente real" e "Escopo por rodada" dessa referência: r1 completa; r≥2 confirma as correções e ataca o delta; consumidores e configurações reais como escopo; em story crítica, modelo de ameaça e limites aceitos já na r1. Não copie a regra para o pacote; aponte para ela.

Escolha alias próprio de revisão. A configuração aprovada pelo usuário fornece harness/modelo/esforço sem perguntar a cada story. Antes de lançar, confira MR aberta, conflitos e head atual. Em conflito, siga [conflito](#conflito).

## Conflito

Com `"rebase-conflito"` em `acoes_automaticas` ([configuração](configuracao.md#acoes_automaticas)), MR em conflito não gera pergunta: o coordenador manda o executor, no mesmo pane e worktree, fazer o rebase sobre a branch de destino e empurrar com `--force-with-lease`; o revisor, depois, confirma o delta do rebase no SHA novo (o que o conflito mudou, sem refazer a revisão inteira) e a MR volta ao ritmo normal. A aprovação e a pipeline do SHA antigo não valem para o novo: o `--aprovado` é gravado de novo e o CI roda de novo. Conflito que exige escolher entre dois comportamentos (e não só reaplicar o diff) é decisão da pessoa: pendência, não rebase automático. Sem a ação na lista, a pergunta é concreta.

## Tirar o Draft e mesclar

Com `"tirar-draft"` na lista, o coordenador tira o Draft sem perguntar (`glab mr update <mr> --ready`) quando a revisão aprovou o head atual e o CI está verde nesse head; se o revisor já o tirou, não há o que fazer. Tirar o Draft não é aprovar, e achado `Bloqueante` ou `Sério` aberto mantém o Draft. O merge que vem depois segue [`merge_automatico`](configuracao.md#merge_automatico): só na `develop`, só com todas as condições no head, incluindo o quality gate do Sonar. Fora disso, a MR fica aprovada, sem Draft, à espera da pessoa.

Confira também que a evidência do executor saiu como nota não resolvível, conforme `basis-ci-gitlab/references/ciclo-da-mr.md`. Uma discussão resolvível aberta pelo executor continua segurando o merge mesmo depois de a revisão aprovar e tirar o Draft. Para conferir, use `glab api projects/:id/merge_requests/<iid>/discussions` e filtre por autor, `resolvable` e não resolvida. Havendo, devolva ao executor para resolvê-la antes da revisão. O revisor não resolve discussão do autor. Na TG-232 (colaboradados, 2026-10-15), quatro threads de evidência resolvíveis seguraram `blocking_discussions_resolved=false` depois da aprovação, e custaram uma volta extra ao executor.

Ao aprovar a revisão, grave o SHA aprovado de cada MR com `orq recursos gravar <ref> --aprovado <url>=<sha>` ([recursos](despacho.md#recursos-da-us-temporários-e-docker)): sem ele, a limpeza pós-merge recusa. O revisor recebe critérios, evidências, SHA e relatório; não edita a implementação nem faz push. O pane do revisor abre com a identidade de `revisao` ([despacho](despacho.md#inicialização)), para que os achados saiam no nome dele. Confira que o papel `qa-adversarial` está disponível. Se for apenas um arquivo de instruções adotado como papel, use essa alternativa somente quando autorizada na configuração ou sessão; informe a adaptação.

Antes de mandar nova rodada de correção, trie os achados por ocorrência real: Bloqueante ou Sério sem projeto, consumidor ou configuração nossa onde ocorra vale como `Menor` ou limite no resumo; `Menor` não abre rodada. Correções de MR aberta usam mesma branch/worktree, mantendo a barreira de revisão. A rodada seguinte confirma correções no novo SHA e resolve as discussões correspondentes. Com os panes ainda abertos, a correção e a revisão seguinte vão para as mesmas sessões do executor e do revisor, num pacote r≥2 que remete ao r1 e muda só o necessário. Assim se preserva o contexto, como nas r2 da TG-312. Feche o pane do revisor só depois da aprovação. Confira Draft e pendências antes de declarar pronta para merge.

Se a MR for mesclada durante a revisão, avise o revisor. Preserve relatório e achados sem tentar alterar o estado de uma MR encerrada; proponha story `review` ou correção conforme o fluxo existente e autorização do usuário.

Suspeitas de falso positivo/hotspot seguem validação do revisor e decisão humana quando exigida. Confira o gate novamente no head atual após a decisão.
