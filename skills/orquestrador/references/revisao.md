# Revisão independente

Carregue `basis-ci-gitlab/references/revisao-da-mr.md`: ela define elegibilidade, papel `qa-adversarial`, severidades, discussões, Draft, devolução e repetição de achados. Preserve as exceções `config` e o fluxo de stories `review` definidos ali.

Escolha alias próprio de revisão. A configuração aprovada pelo usuário fornece harness/modelo/esforço sem perguntar a cada story. Antes de lançar, confira MR aberta, conflitos e head atual. Em conflito, mande o executor atualizar a branch e devolvê-la antes da revisão.

O revisor recebe critérios, evidências, SHA e relatório; não edita a implementação nem faz push. Confira que o papel `qa-adversarial` está disponível. Se for apenas um arquivo de instruções adotado como papel, use essa alternativa somente quando autorizada na configuração ou sessão; informe a adaptação.

Correções de MR aberta usam mesma branch/worktree, mantendo a barreira de revisão. A rodada seguinte confirma correções no novo SHA e resolve as discussões correspondentes. Confira Draft e pendências antes de declarar pronta para merge.

Se a MR for mesclada durante a revisão, avise o revisor. Preserve relatório e achados sem tentar alterar o estado de uma MR encerrada; proponha story `review` ou correção conforme o fluxo existente e autorização do usuário.

Suspeitas de falso positivo/hotspot seguem validação do revisor e decisão humana quando exigida. Confira o gate novamente no head atual após a decisão.
