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
- Pendências da story abertas, com o id da Central (`P<n>`). A conversa com a pessoa dispensa pendência por pergunta, mas toda proposta que ficar sem resposta no fim vira pendência pelo arquivo `<pasta da US>/pendencias/<slug>.md`, uma por proposta, gravando `.<slug>.md.tmp` e rodando `<caminho absoluto do script> <pasta da US>/pendencias <slug>` (o coordenador escreve aqui o caminho do `espera-pendencia-registrada.sh` na cópia instalada dele, ex. `<raiz do coordenador>/.agents/skills/orquestrador/scripts/espera-pendencia-registrada.sh`; o worker não tem a skill) (espera 30 s pelo `.registrada.json` ou pelo `.erro.txt`, sem glob); o retorno cita o id devolvido. Saída 3 do script: "pendência não registrada: `<arquivo>`" no retorno. **Proibido** `orq pend responder` e `orq pend resolver`. [Regra e modelo](../references/acompanhamento.md#abrir-a-pendência-pelo-arquivo); sem o daemon da #15, o pacote traz o próximo id livre. Origem: TG-249 do colaboradados (2026-11-06), sete propostas ficaram só no retorno e não apareceram na Central.
- Shell dos workers (zsh): repasse a [regra de shell](../references/despacho.md#regra-de-shell-dos-workers), com o caminho absoluto dos scripts de espera conferidos na cópia instalada do coordenador.
- Artefato de retorno ao coordenador: caminho do `retorno-planejamento.md`.
- Aviso ao coordenador depois de gravar o retorno, com papel `planejamento`: [despacho](../references/despacho.md#aviso-ao-coordenador).
