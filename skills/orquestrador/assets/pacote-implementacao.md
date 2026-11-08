# Pacote de implementação

- Origem: coordenador (rótulo, nome de agente e id do pane), missão e referência da conversa.
- Worker: rótulo, nome de agente e id do pane do destinatário ([nomes](../references/despacho.md#nomes-dos-panes)).
- Alvo: chave do projeto, caminho, board e story, instruções canônicas.
- Objetivo e critérios de aceite: links e escopo.
- Plano, dependências incorporadas e decisões relevantes.
- Alias e harness/modelo/esforço resolvidos; skills e versões.
- Worktree absoluto, branch, base e MR existente (no formato de [como citar](../SKILL.md#como-citar-uma-mr-ou-pr)).
- Autorizações: transições, escrita externa e limites explícitos.
- Modo autônomo, critérios de bloqueio e histórico de recorrências.
- Ambiente: credenciais por referência, recursos, locks e conflitos potenciais; destino de cada escrita por ambiente conferido na fonte ([fatos de ambiente](../references/despacho.md#fatos-de-ambiente)).
- Migração Flyway na US: nome com a ref da story, conforme a [convenção](../../basis-spring-app/references/flyway-modulith-notes.md#naming); o pacote cita, não copia a regra.
- Testes/evidências e contrato de devolução da basis-ci-gitlab. A MR ou PR só é anunciada como pronta sem Draft (`draft=false` conferido na forja antes); com pré-condição pendente, fica em Draft com `Mesclar depois de …` na primeira linha da descrição; em série empilhada (só então), o pacote diz qual é a próxima da fila ([regra](../../basis-ci-gitlab/references/revisao-da-mr.md#pronta-não-convive-com-draft)). Achados de regras do Sonar, em projeto com Sonar: lidos pela CLI depois que a pipeline analisar a MR, pela `basis-java-code-standards`; não há leitura de regras antes da MR, e o gate é o `check-quality`.
- Pendências da story abertas, com o id da Central (`P<n>`). Pendência nova: pelo arquivo `<diretório da rodada>/pendencias/<slug>.md`, esperando até 30 s pelo `.registrada.json` ou pelo `.erro.txt` e citando o id devolvido; sem resposta do daemon, "pendência não registrada: `<arquivo>`". **Proibido** `orq pend responder` e `orq pend resolver`. [Regra e modelo](../references/acompanhamento.md#abrir-a-pendência-pelo-arquivo); sem o daemon da #15, o pacote traz o próximo id livre.
- `TMPDIR` do worker e rótulos Docker `orq.us`/`orq.onda` ([recursos](../references/despacho.md#recursos-da-us-temporários-e-docker)); o worker usa o `TMPDIR` que recebeu e rotula o que criar no Docker.
- Servidor temporário (`python3 -m http.server`, `kubectl port-forward` etc.): escuta só em `127.0.0.1` e o próprio worker o encerra ao terminar, antes do relatório ([fim de onda](../references/conclusao-e-limpeza.md#fim-de-onda)).
- Diretório da rodada e caminho do relatório persistente.
- Aviso ao coordenador depois de gravar o relatório: [despacho](../references/despacho.md#aviso-ao-coordenador).
