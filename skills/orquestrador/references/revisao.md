# Revisão independente

Carregue `basis-ci-gitlab/references/revisao-da-mr.md`: ela define elegibilidade, papel `qa-adversarial`, severidades, discussões, Draft, devolução e repetição de achados. Preserve as exceções `config` e o fluxo de stories `review` definidos ali.

O pacote delimita a rodada conforme as seções "Severidade ancorada no ambiente real" e "Escopo por rodada" dessa referência: r1 completa; r≥2 confirma as correções e ataca o delta; consumidores e configurações reais como escopo; em story crítica, modelo de ameaça e limites aceitos já na r1. Não copie a regra para o pacote; aponte para ela.

Escolha alias próprio de revisão. A configuração aprovada pelo usuário fornece harness/modelo/esforço sem perguntar a cada story. Antes de lançar, confira MR aberta, conflitos e head atual. Em conflito, mande o executor atualizar a branch e devolvê-la antes da revisão.

O revisor recebe critérios, evidências, SHA e relatório; não edita a implementação nem faz push. O pane do revisor abre com a identidade de `revisao` ([despacho](despacho.md#inicialização)), para que os achados saiam no nome dele. Confira que o papel `qa-adversarial` está disponível. Se for apenas um arquivo de instruções adotado como papel, use essa alternativa somente quando autorizada na configuração ou sessão; informe a adaptação.

Antes de mandar nova rodada de correção, trie os achados por ocorrência real: Bloqueante ou Sério sem projeto, consumidor ou configuração nossa onde ocorra vale como `Menor` ou limite no resumo; `Menor` não abre rodada. Correções de MR aberta usam mesma branch/worktree, mantendo a barreira de revisão. A rodada seguinte confirma correções no novo SHA e resolve as discussões correspondentes. Com os panes ainda abertos, a correção e a revisão seguinte vão para as mesmas sessões do executor e do revisor, num pacote r≥2 que remete ao r1 e muda só o necessário. Assim se preserva o contexto, como nas r2 da TG-312. Feche o pane do revisor só depois da aprovação. Confira Draft e pendências antes de declarar pronta para merge.

Se a MR for mesclada durante a revisão, avise o revisor. Preserve relatório e achados sem tentar alterar o estado de uma MR encerrada; proponha story `review` ou correção conforme o fluxo existente e autorização do usuário.

Suspeitas de falso positivo/hotspot seguem validação do revisor e decisão humana quando exigida. Confira o gate novamente no head atual após a decisão.
