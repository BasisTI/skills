# Conclusão e limpeza

## Auditoria proativa

Execute auditoria pelos critérios da `basis-ci-gitlab`; para produção, use cadeia de entrega e `basis-k8s-deploy`. Diferencie aprovação da MR, merge, teste e entrega. Em projetos com fluxo simplificado, use seus critérios declarados. Apresente evidências e execute transições já autorizadas. As transições automáticas da [configuração](configuracao.md#autonomia-e-transições-automáticas) são executadas quando a evidência é confirmada e registradas no registro da missão e no relatório ao usuário, sem pergunta. As demais seguem como pergunta concreta: "posso mover a TG-xx para X?", com a evidência junto.

Detecte pendências em outro repositório e prepare a story no board que receberá a mudança. Escrita no Taiga segue autorização existente. Após merge, libere dependentes elegíveis; a [limpeza](#limpeza-depois-do-merge) e, na última MR da onda, o [encerramento](central.md#encerrar-a-onda) são do `orq`.

## Limpeza depois do merge

Depois do merge a limpeza é automática e sem pergunta: com a [Central](central.md) e o daemon do `orq` no ar, ele roda `orq limpar <ref>` quando a última MR da US é mesclada. Não peça confirmação para fechar panes, remover worktree, branches, pastas ou recursos Docker da US: tudo foi enviado ao remoto, e o `orq limpar` só age se a conferência passa.

O `orq limpar` age sobre o que o despacho [gravou em `recursos.json`](despacho.md#recursos-da-us-temporários-e-docker): fecha os panes `idle`/`done` (relidos logo antes), remove o worktree limpo e a branch local e a remota cujo conteúdo já está na branch de destino (com squash, por conteúdo), o `TMPDIR`, os recursos Docker com o rótulo `orq.us` e, por último, a pasta de trabalho. Ele recusa a US com MR não mesclada ou head mesclado diferente do aprovado, e nunca usa `prune` nem apaga fora das raízes. `orq limpar <ref> --dry-run` mostra o plano.

- **Com `preservado`** (árvore suja, commit não enviado, agente `working`…), nada é forçado: o motivo está na saída e no `orq diario`, e o daemon tenta de novo a cada 5 min. Resolva a causa (commite e envie, espere o agente) ou, se o resto é descartável, peça à pessoa; não use `wt remove`, `rm -rf` nem `--force` por fora.
- **Sem Central ou sem daemon** (`orq plugin doctor`): rode `orq limpar <ref>` você mesmo, também sem perguntar. Sem o `orq`, aplique à mão as mesmas conferências: MR mesclada, nenhum agente usando o diretório, árvore limpa, nada fora do remoto (com squash, `git diff --quiet <head da branch> <squash> -- <pasta do projeto>`), e só então `wt remove <branch> --yes` com cwd explícito e `git branch -D`.
- **Corrigir depois do teste:** recrie worktree e panes a partir da `main`, numa branch nova ([despacho](despacho.md#worktree-e-pacote)), grave os recursos de novo e ligue a MR nova. O `orq limpar` age outra vez no merge seguinte.
- O daemon desligado por `ORQ_LIMPEZA_AUTOMATICA=0` deixa a chamada do `orq limpar` com você.

Origem: pedido do Cedric em 2026-10-17 (orq #13): "Não perguntar mais antes de fechar o pane de um executor e/ou revisor e limpar branches, worktrees e pastas no ~/tmp e /tmp. Quando o MR relacionado com a US é mesclado, a limpeza tem que ser automática; tudo foi enviado para o remote." Naquele dia havia 21 worktrees, 18 GB em `~/tmp/orquestrador` e um contêiner de revisão rodando havia duas semanas.

## Fim de onda

Com todas as US em `done`, MRs mescladas ou fechadas e sem pendência aberta, o daemon encerra a onda (exceto a de `plano`) e remove o Docker com o rótulo `orq.onda`. Confira, sem perguntar:

1. `orq onda ver <id>`: onda encerrada e nenhuma US com `preservado` aberto em `orq diario --onda <id>`. Onda ainda aberta: o `encerramento.faltam` de `orq onda proxima` diz o que impede.
2. Sobras: `orq limpar <ref> --dry-run` de cada US da onda, e `orq limpar --onda <id>` se o daemon não rodou o Docker.
3. Pendências abertas viram resolvidas, levadas para outra onda ou para o Taiga ([encerrar a onda](central.md#encerrar-a-onda)).
4. Entregue a tabela de merge da onda ([ondas](ondas.md)).

## Artefatos

Preserve relatórios, evidências e decisões até a retenção configurada e o destino persistente estarem confirmados: a pasta de trabalho da US só sai com o `orq limpar`, depois do merge, e o que precisa durar vai antes para o destino persistente. Fora do `orq limpar`, apague apenas descartáveis enumerados, dentro da raiz de artefatos e vinculados à missão: resolva caminhos, confira raiz e symlinks, rejeite raiz inteira, caminho vazio ou destino fora dela. Não conceda acesso genérico a `rm -rf`. Migração de diretórios antigos exige verificar origem/destino e colisões antes de mover.

Panes: feche somente os criados pela missão e sem trabalho pendente (agente `idle` ou `done`, conferido logo antes de fechar); o `orq limpar` já faz isso. O aviso ao coordenador não marca o fim do trabalho. Na TG-225 do convey, a aba do revisor foi fechada com ele ainda `working`, registrando o resultado do aviso. Pane de planejamento com conversa do usuário em andamento continua aberto.

## Permissões

A limpeza pelo `orq` não pede aprovação da pessoa; o que o harness bloquear segue as referências de Claude Code/Codex. Se o classificador bloquear, registre comando, motivo e camada; conclua as operações permitidas e entregue somente o resíduo bloqueado ao usuário. Não declare limpeza completa após uma recusa.
