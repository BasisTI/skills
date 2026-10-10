# Conclusão e limpeza

## Auditoria proativa

Execute auditoria pelos critérios da `basis-ci-gitlab`; para produção, use cadeia de entrega e `basis-k8s-deploy`. Diferencie aprovação da MR, merge, teste e entrega. Em projetos com fluxo simplificado, use seus critérios declarados. Apresente evidências e execute transições já autorizadas. As transições automáticas da [configuração](configuracao.md#autonomia-e-transições-automáticas) são executadas quando a evidência é confirmada e registradas no registro da missão e no relatório ao usuário, sem pergunta. As demais seguem como pergunta concreta: "posso mover a TG-xx para X?", com a evidência junto.

Detecte pendências em outro repositório e prepare a story no board que receberá a mudança. Escrita no Taiga segue autorização existente. Após merge, libere dependentes elegíveis.

## Worktrees

A limpeza integra a missão autorizada. Verifique MR mesclada, nenhum agente/processo usando o diretório, árvore limpa e ausência de trabalho local não incorporado. Confira branch correta, relação com a MR e procedimentos da `basis-ci-gitlab/worktree.md`. Use `wt remove <branch> --yes` a partir do repositório alvo com cwd explícito; releia estado após cada remoção.

Com squash, o `wt remove` remove o worktree, mas recusa apagar a branch ("Branch unmerged"). Confira que o conteúdo da branch está no commit de squash, com `git diff --quiet <head da branch> <squash> -- <pasta do projeto>`, porque fora dela a diferença vem de outros merges no destino. Só então use `git branch -D`.

Árvore suja, MR aberta ou commits locais sem destino conhecido impedem a remoção. Preserve e reporte. Permitir `wt remove` no harness não dispensa essas verificações.

## Artefatos e panes

Preserve relatórios, evidências e decisões até a retenção configurada e o destino persistente estarem confirmados. Apague apenas descartáveis enumerados, dentro da raiz de artefatos e vinculados à missão. Resolva caminhos, confira raiz e symlinks; rejeite raiz inteira, caminho vazio ou destino fora dela. Migração de diretórios antigos exige verificar origem/destino e colisões antes de mover.

Prefira um helper de limpeza restrito quando existir e tiver sido validado; esta versão não fornece esse helper. Não conceda acesso genérico a `rm -rf`. Operações de organização independentes podem continuar quando exclusão for bloqueada.

Feche somente panes criados pela missão e sem trabalho pendente: agente `idle` ou `done`, conferido logo antes de fechar. O aviso ao coordenador não marca o fim do trabalho. Na TG-225 do convey, a aba do revisor foi fechada com ele ainda `working`, registrando o resultado do aviso. Pane de planejamento com conversa do usuário em andamento continua aberto. Registre recursos removidos/preservados e resultado da verificação.

## Permissões

Prepare plano de limpeza com caminhos e verificações, então use o mecanismo de aprovação do harness se necessário. Consulte referências de Claude Code/Codex. Se o classificador bloquear, registre comando, motivo e camada; conclua as operações permitidas e entregue somente o resíduo bloqueado ao usuário. Não declare limpeza completa após uma recusa.
