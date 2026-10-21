# Pacote de revisão

- Origem (coordenador: rótulo, nome de agente e id do pane), missão, projeto e story com critérios de aceite.
- Worker: rótulo, nome de agente e id do pane do destinatário ([nomes](../references/despacho.md#nomes-dos-panes)).
- Alias e harness/modelo/esforço resolvidos.
- Papel qa-adversarial: origem e modo autorizado.
- MR aberta, SHA a revisar, base, worktree e estado de conflitos.
- Relatório do executor, evidências, pipeline e suspeitas Sonar.
- Escopo da rodada: r1 completa; r≥2 confirma as correções no SHA novo e ataca o delta, nunca "procure quebras novas". Regra em `basis-ci-gitlab/references/revisao-da-mr.md`.
- Consumidores e configurações reais que delimitam a severidade.
- Story crítica (segurança, integridade de dados): modelo de ameaça (adversário, por onde a entrada chega) e limites aceitos.
- Histórico de achados e recorrências por classe.
- Autorizações para notas, discussões e Draft conforme basis-ci-gitlab.
- Correções pertencem ao executor; o merge segue a [política do coordenador](../references/configuracao.md#merge_automatico), e o revisor não mescla.
- Pendências da story abertas, com o id da Central (`P<n>`). Pendência nova: pelo arquivo `<diretório da rodada>/pendencias/<slug>.md`, esperando até 30 s pelo `.registrada.json` ou pelo `.erro.txt` e citando o id devolvido; sem resposta do daemon, "pendência não registrada: `<arquivo>`". **Proibido** `orq pend responder` e `orq pend resolver`. [Regra e modelo](../references/acompanhamento.md#abrir-a-pendência-pelo-arquivo); sem o daemon da #15, o pacote traz o próximo id livre.
- `TMPDIR` do worker e rótulos Docker `orq.us`/`orq.onda` ([recursos](../references/despacho.md#recursos-da-us-temporários-e-docker)); o worker usa o `TMPDIR` que recebeu e rotula o que criar no Docker.
- Servidor temporário (`python3 -m http.server`, `kubectl port-forward` etc.): escuta só em `127.0.0.1` e o próprio worker o encerra ao terminar, antes do relatório ([fim de onda](../references/conclusao-e-limpeza.md#fim-de-onda)).
- Diretório da rodada e caminho do relatório persistente.
- Aviso ao coordenador depois de gravar o relatório: [despacho](../references/despacho.md#aviso-ao-coordenador).
