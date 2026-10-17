# Pacote de implementação

- Origem: coordenador (rótulo, nome de agente e id do pane), missão e referência da conversa.
- Worker: rótulo, nome de agente e id do pane do destinatário ([nomes](../references/despacho.md#nomes-dos-panes)).
- Alvo: chave do projeto, caminho, board e story, instruções canônicas.
- Objetivo e critérios de aceite: links e escopo.
- Plano, dependências incorporadas e decisões relevantes.
- Alias e harness/modelo/esforço resolvidos; skills e versões.
- Worktree absoluto, branch, base e MR existente.
- Autorizações: transições, escrita externa e limites explícitos.
- Modo autônomo, critérios de bloqueio e histórico de recorrências.
- Ambiente: credenciais por referência, recursos, locks e conflitos potenciais; destino de cada escrita por ambiente conferido na fonte ([fatos de ambiente](../references/despacho.md#fatos-de-ambiente)).
- Testes/evidências e contrato de devolução da basis-ci-gitlab.
- Pendências da story abertas e próximo id livre (`P<n>`): [bloqueios](../references/acompanhamento.md#bloqueios-e-recorrência).
- `TMPDIR` do worker e rótulos Docker `orq.us`/`orq.onda` ([recursos](../references/despacho.md#recursos-da-us-temporários-e-docker)); o worker usa o `TMPDIR` que recebeu e rotula o que criar no Docker.
- Diretório da rodada e caminho do relatório persistente.
- Aviso ao coordenador depois de gravar o relatório: [despacho](../references/despacho.md#aviso-ao-coordenador).
