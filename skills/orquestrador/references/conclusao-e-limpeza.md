# Conclusão e limpeza

## Auditoria proativa

Execute auditoria pelos critérios da `basis-ci-gitlab`; para produção, use cadeia de entrega e `basis-k8s-deploy`. Diferencie aprovação da MR, merge, teste e entrega; o fluxo de status por tipo de projeto está em [configuração](configuracao.md#fluxo-de-status-por-tipo-de-projeto). Em projeto cuja `[autonomia]` lista `Done:main`, o `Done` pelo commit na `main` não pede produção rodando a versão, e a auditoria não reabre a story por isso ([regra](configuracao.md#transicoes_automaticas)). Em projetos com fluxo simplificado, use seus critérios declarados. Apresente evidências e execute transições já autorizadas. As transições automáticas da [configuração](configuracao.md#autonomia-e-transições-automáticas) são executadas quando a evidência é confirmada e registradas no registro da missão e no relatório ao usuário, sem pergunta. As demais seguem como pergunta concreta: "posso mover a TG-xx para X?", com a evidência junto.

Detecte pendências em outro repositório e prepare a story no board que receberá a mudança. Escrita no Taiga segue autorização existente. Após merge, libere dependentes elegíveis; a [limpeza](#limpeza-depois-do-merge) e, na última MR da onda, o [encerramento](central.md#encerrar-a-onda) são do `orq`.

## Limpeza depois do merge

Depois do merge a limpeza é automática e sem pergunta: com a [Central](central.md) e o daemon do `orq` no ar, ele roda `orq limpar <ref>` quando a última MR da US é mesclada. Não peça confirmação para fechar panes, remover worktree, branches, pastas ou recursos Docker da US: tudo foi enviado ao remoto, e o `orq limpar` só age se a conferência passa.

O `orq limpar` age sobre o que o despacho [gravou em `recursos.json`](despacho.md#recursos-da-us-temporários-e-docker): fecha os panes registrados com `--pane` que estão `idle`/`done` (relidos logo antes), remove o worktree limpo e a branch local e a remota cujo conteúdo já está na branch de destino (com squash, por conteúdo), o `TMPDIR`, os recursos Docker com o rótulo `orq.us` e, por último, a pasta de trabalho. Ele recusa a US com MR não mesclada, sem head aprovado registrado (`--aprovado`) ou com head mesclado diferente do aprovado, e nunca usa `prune` nem apaga fora das raízes. `orq limpar <ref> --dry-run` mostra o plano.

- **Com `preservado`** (árvore suja, commit não enviado, agente `working`…), nada é forçado: o motivo está na saída e no `orq diario`, e o daemon tenta de novo a cada 5 min. Resolva a causa (commite e envie, espere o agente) ou, se o resto é descartável, peça à pessoa; não use `wt remove`, `rm -rf` nem `--force` por fora.
- **Sem Central ou sem daemon** (`orq plugin doctor`): rode `orq limpar <ref>` você mesmo, também sem perguntar. Sem o `orq`, aplique à mão as mesmas conferências: MR mesclada, nenhum agente usando o diretório, árvore limpa, nada fora do remoto (com squash, `git diff --quiet <head da branch> <squash> -- <pasta do projeto>`), e só então `wt remove <branch> --yes` com cwd explícito e `git branch -D`.
- **Corrigir depois do teste:** rode `orq recursos reabrir <ref>` **antes** de recriar qualquer coisa. Ele só vale depois do merge (recusa MR aberta e MR mesclada sem `--aprovado`), espera uma limpeza em andamento terminar (trava da US) e deixa a US reaberta, e então a limpeza recusa até haver MR nova ligada. Só depois recrie worktree e panes a partir da `main`, numa branch nova e num caminho novo (sufixo da rodada), grave-os com `orq recursos gravar` e ligue a MR nova ([despacho](despacho.md#recursos-da-us-temporários-e-docker)). O `orq limpar` age outra vez no merge seguinte. Recriar o worktree antes do `reabrir` deixa uma limpeza em curso apagá-lo.
- O daemon desligado por `ORQ_LIMPEZA_AUTOMATICA=0` deixa a chamada do `orq limpar` com você.

A lista `--pane` do `recursos.json` é a autoridade de posse dos panes, e o arquivo é confiável no nível do usuário local: o `orq` não o autentica.

Origem: pedido do Cedric em 2026-10-17 (orq #13): "Não perguntar mais antes de fechar o pane de um executor e/ou revisor e limpar branches, worktrees e pastas no ~/tmp e /tmp. Quando o MR relacionado com a US é mesclado, a limpeza tem que ser automática; tudo foi enviado para o remote." Naquele dia havia 21 worktrees, 18 GB em `~/tmp/orquestrador` e um contêiner de revisão rodando havia duas semanas.

## Fim de onda

Com todas as US em `done`, MRs mescladas ou fechadas e sem pendência aberta, o daemon encerra a onda (exceto a de `plano`) e remove o Docker com o rótulo `orq.onda`. Confira, sem perguntar:

1. `orq onda ver <id>`: onda encerrada e nenhuma US com `preservado` aberto em `orq diario --onda <id>`. Onda ainda aberta: o `encerramento.faltam` de `orq onda proxima` diz o que impede.
2. Sobras: `orq limpar <ref> --dry-run` de cada US da onda, e `orq limpar --onda <id>` se o daemon não rodou o Docker.
3. Pendências abertas viram resolvidas, levadas para outra onda ou para o Taiga ([encerrar a onda](central.md#encerrar-a-onda)).
4. Servidores órfãos: procure processos de servidor que os workers deixaram, como `python3 -m http.server` e `kubectl port-forward`, cuja linha de comando ou cwd aponta para `~/tmp/orquestrador/<projeto>/TG-<ref>` de uma US da onda, e encerre-os sem perguntar. Liste com `ps -eo pid,etimes,args` e `ls -l /proc/<pid>/cwd`, e ouça o que cada um publica com `ss -ltnp`. Encerre só o que casa com a pasta da onda (nunca por nome de comando), com `kill <pid>` e sem `-9` de início; confira depois que a porta fechou. O que escutar em `0.0.0.0` e apontar para outra pasta não é seu: informe. Os [pacotes](../assets/pacote-implementacao.md) pedem que todo servidor temporário escute em `127.0.0.1` e que o próprio worker o encerre ao terminar; este item pega o que escapou.
5. Entregue a tabela de merge da onda ([ondas](ondas.md)).

Origem: em 2026-10-18 havia cinco `http.server` órfãos, rodando de 2 a 5 dias e ouvindo em `0.0.0.0`, que publicavam na rede local as pastas de revisão (BASIS-330230, BASIS-330266, portal-liven TG-133 e TG-148, kaizenstat TG-39), quatro delas já apagadas. O Cedric pediu que isso entre no checklist de fim de onda (orq #14).

## Artefatos

Preserve relatórios, evidências e decisões até a retenção configurada e o destino persistente estarem confirmados: a pasta de trabalho da US só sai com o `orq limpar`, depois do merge, e o que precisa durar vai antes para o destino persistente. Fora do `orq limpar`, apague apenas descartáveis enumerados, dentro da raiz de artefatos e vinculados à missão: resolva caminhos, confira raiz e symlinks, rejeite raiz inteira, caminho vazio ou destino fora dela. Não conceda acesso genérico a `rm -rf`. Migração de diretórios antigos exige verificar origem/destino e colisões antes de mover.

Panes: feche somente os criados pela missão e sem trabalho pendente (agente `idle` ou `done`, conferido logo antes de fechar); o `orq limpar` já faz isso. O aviso ao coordenador não marca o fim do trabalho. Na TG-225 do convey, a aba do revisor foi fechada com ele ainda `working`, registrando o resultado do aviso. Pane de planejamento com conversa do usuário em andamento continua aberto.

## Permissões

A limpeza pelo `orq` não pede aprovação da pessoa; o que o harness bloquear segue as referências de Claude Code/Codex. Se o classificador bloquear, registre comando, motivo e camada; conclua as operações permitidas e entregue somente o resíduo bloqueado ao usuário. Não declare limpeza completa após uma recusa.
