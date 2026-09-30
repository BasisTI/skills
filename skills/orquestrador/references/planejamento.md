# Planejamento em conversa dedicada

Quando planejamento puder avançar sem esperar a rodada atual, ofereça ao usuário discutir o assunto com um agente de planejamento em outro pane. Exemplo: “Enquanto acompanhamos a implementação, quer discutir a fase seguinte em um painel de planejamento?” Aguarde aceite para abrir essa conversa.

Resolva o alias de planejamento e use o template. Inclua origem, objetivo, stories, decisões, dependências, situação da execução e perguntas abertas. Envie contexto por prompt ou mecanismo de handoff disponível. Use `ai-memory-handoff` se usar continuidade da memória; não consuma nem crie handoffs em outro escopo por conveniência. O prompt explícito é suficiente quando não há transferência de sessão.

Nomeie o pane com projeto e assunto, respeitando limites do Herdr, e mostre nome e ID ao usuário. Consulte a CLI instalada para descobrir foco/navegação; só mude o foco quando o usuário pedir ou aceitar a mudança de contexto. Se não houver função de foco, indique o pane pelo nome e ID.

O agente começa: “Esta conversa foi encaminhada pelo Orquestrador de <projeto> para discutirmos <assunto>.” Ele conversa diretamente com o usuário. Resultados de código e revisão continuam no coordenador.

Ao concluir, entregue plano, decisões aprovadas com origem, propostas ainda pendentes, dependências e critérios de aceite. Planejar não autoriza implementar nem escrever no Taiga. O coordenador incorpora o resultado e confere dependências antes de despachar.
