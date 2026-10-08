# Pacote de revisão

- Origem (coordenador com nome e pane Herdr), missão, projeto e story com critérios de aceite.
- Alias e harness/modelo/esforço resolvidos.
- Papel qa-adversarial: origem e modo autorizado.
- MR aberta, SHA a revisar, base, worktree e estado de conflitos.
- Relatório do executor, evidências, pipeline e suspeitas Sonar.
- Escopo da rodada: r1 completa; r≥2 confirma as correções no SHA novo e ataca o delta, nunca "procure quebras novas". Regra em `basis-ci-gitlab/references/revisao-da-mr.md`.
- Consumidores e configurações reais que delimitam a severidade.
- Story crítica (segurança, integridade de dados): modelo de ameaça (adversário, por onde a entrada chega) e limites aceitos.
- Histórico de achados e recorrências por classe.
- Autorizações para notas, discussões e Draft conforme basis-ci-gitlab.
- Correções pertencem ao executor; merge/aprovação seguem política humana.
- Diretório da rodada e caminho do relatório persistente.
- Aviso ao coordenador depois de gravar o relatório: [despacho](../references/despacho.md#aviso-ao-coordenador).
