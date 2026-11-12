# Handoff de planejamento

- Apresentação inicial: esta conversa vem do Orquestrador de <projeto> para <assunto>.
- Origem: missão, conversa e coordenador (rótulo, nome de agente e id do pane).
- Projeto alvo, board, stories e documentos.
- Objetivo e questões que o usuário quer discutir.
- Estado da execução em paralelo e dependências.
- Decisões aprovadas, propostas pendentes e restrições.
- Alias e harness/modelo/esforço resolvidos.
- Autorização para conversar; escritas externas/implementação exigem escopo próprio.
- Pane do planejador: rótulo, nome de agente e id, a comunicar ao usuário ([nomes](../references/despacho.md#nomes-dos-panes)).
- Entrega: plano, critérios, dependências e decisões com origem.
- Pendências da story abertas, com o id da Central (`P<n>`). A conversa com a pessoa dispensa pendência por pergunta, mas toda proposta que ficar sem resposta no fim vira pendência pelo arquivo `<diretório da rodada>/pendencias/<slug>.md`, uma por proposta, gravando `.<slug>.md.tmp` e rodando `scripts/espera-pendencia-registrada.sh <diretório>/pendencias <slug>` (espera 30 s pelo `.registrada.json` ou pelo `.erro.txt`, sem glob); o retorno cita o id devolvido. Saída 3 do script: "pendência não registrada: `<arquivo>`" no retorno. **Proibido** `orq pend responder` e `orq pend resolver`. [Regra e modelo](../references/acompanhamento.md#abrir-a-pendência-pelo-arquivo); sem o daemon da #15, o pacote traz o próximo id livre. Origem: TG-249 do colaboradados (2026-11-06), sete propostas ficaram só no retorno e não apareceram na Central.
- Artefato de retorno ao coordenador: caminho do `retorno-planejamento.md`.
- Aviso ao coordenador depois de gravar o retorno, com papel `planejamento`: [despacho](../references/despacho.md#aviso-ao-coordenador).
