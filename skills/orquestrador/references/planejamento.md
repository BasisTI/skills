# Planejamento em conversa dedicada

Quando planejamento puder avançar sem esperar a rodada atual, ofereça ao usuário discutir o assunto com um agente de planejamento em outro pane. Exemplo: “Enquanto acompanhamos a implementação, quer discutir a fase seguinte em um painel de planejamento?” Aguarde aceite para abrir essa conversa.

Resolva o alias de planejamento e use o template. Inclua origem, objetivo, stories, decisões, dependências, situação da execução e perguntas abertas. Envie contexto por prompt ou mecanismo de handoff disponível. Use `ai-memory-handoff` se usar continuidade da memória; não consuma nem crie handoffs em outro escopo por conveniência. O prompt explícito é suficiente quando não há transferência de sessão.

Abra o pane no workspace do coordenador, como em [despacho](despacho.md#inicialização). Nomeie o pane com projeto e assunto, respeitando limites do Herdr, e mostre nome e ID ao usuário. Consulte a CLI instalada para descobrir foco/navegação; só mude o foco quando o usuário pedir ou aceitar a mudança de contexto. Se não houver função de foco, indique o pane pelo nome e ID.

O agente começa: “Esta conversa foi encaminhada pelo Orquestrador de <projeto> para discutirmos <assunto>.” Ele conversa diretamente com o usuário. Resultados de código e revisão continuam no coordenador.

Ao concluir, o agente grava `retorno-planejamento.md` no caminho do pacote, com plano, decisões aprovadas com origem, propostas ainda pendentes, dependências e critérios de aceite, e avisa o coordenador como os workers ([despacho](despacho.md#aviso-ao-coordenador)). O planejador tem o mesmo ciclo deles: o coordenador arma a espera ao abrir o pane, e o retorno gravado é o sinal de fim ([acompanhamento](acompanhamento.md#worker-ativo-implica-espera-armada)). Planejador parado esperando a resposta da pessoa é o ponto humano das [anomalias](acompanhamento.md#anomalias), não anomalia. Na TG-23 da plataforma-iac (2026-10-08) o pacote só mandava avisar a pessoa no pane, e ninguém acompanhou o fim do planejamento. Planejar não autoriza implementar nem escrever no Taiga. O coordenador incorpora o resultado e confere dependências antes de despachar.
