# Conclusão e limpeza

## Auditoria proativa

Execute auditoria pelos critérios da `basis-ci-gitlab`; para produção, use cadeia de entrega e `basis-k8s-deploy`. Diferencie aprovação da MR, merge, teste e entrega. Em projetos com fluxo simplificado, use seus critérios declarados. Apresente evidências e execute transições já autorizadas; se faltou autorização, pergunte sobre a transição concreta.

Detecte pendências em outro repositório e prepare a story no board que receberá a mudança. Escrita no Taiga segue autorização existente. Após merge, libere dependentes elegíveis.

## Worktrees

A limpeza integra a missão autorizada. Verifique MR mesclada, nenhum agente/processo usando o diretório, árvore limpa e ausência de trabalho local não incorporado. Confira branch correta, relação com a MR e procedimentos da `basis-ci-gitlab/worktree.md`. Use `wt remove <branch> --yes` a partir do repositório alvo com cwd explícito; releia estado após cada remoção.

Árvore suja, MR aberta ou commits locais sem destino conhecido impedem a remoção. Preserve e reporte. Permitir `wt remove` no harness não dispensa essas verificações.

## Artefatos e panes

Preserve relatórios, evidências e decisões até a retenção configurada e o destino persistente estarem confirmados. Apague apenas descartáveis enumerados, dentro da raiz de artefatos e vinculados à missão. Resolva caminhos, confira raiz e symlinks; rejeite raiz inteira, caminho vazio ou destino fora dela. Migração de diretórios antigos exige verificar origem/destino e colisões antes de mover.

Prefira um helper de limpeza restrito quando existir e tiver sido validado; esta versão não fornece esse helper. Não conceda acesso genérico a `rm -rf`. Operações de organização independentes podem continuar quando exclusão for bloqueada.

Feche somente panes criados pela missão e sem trabalho pendente. Pane de planejamento com conversa do usuário em andamento continua aberto. Registre recursos removidos/preservados e resultado da verificação.

## Permissões

Prepare plano de limpeza com caminhos e verificações, então use o mecanismo de aprovação do harness se necessário. Consulte referências de Claude Code/Codex. Se o classificador bloquear, registre comando, motivo e camada; conclua as operações permitidas e entregue somente o resíduo bloqueado ao usuário. Não declare limpeza completa após uma recusa.
