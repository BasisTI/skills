# Planejamento em conversa dedicada

Quando planejamento puder avançar sem esperar a rodada atual, ofereça ao usuário discutir o assunto com um agente de planejamento em outro pane. Exemplo: “Enquanto acompanhamos a implementação, quer discutir a fase seguinte em um painel de planejamento?” Aguarde aceite para abrir essa conversa.

Resolva o alias de planejamento e use o template. Inclua origem, objetivo, stories, decisões, dependências, situação da execução e perguntas abertas. Envie contexto por prompt ou mecanismo de handoff disponível. Use `ai-memory-handoff` se usar continuidade da memória; não consuma nem crie handoffs em outro escopo por conveniência. O prompt explícito é suficiente quando não há transferência de sessão.

Abra o pane no workspace do coordenador, como em [despacho](despacho.md#inicialização). Nomeie o pane como em [nomes dos panes](despacho.md#nomes-dos-panes) e mostre rótulo, nome de agente e ID ao usuário. Consulte a CLI instalada para descobrir foco/navegação; só mude o foco quando o usuário pedir ou aceitar a mudança de contexto. Se não houver função de foco, indique o pane pelo nome e ID.

O agente começa: “Esta conversa foi encaminhada pelo Orquestrador de <projeto> para discutirmos <assunto>.” Ele conversa diretamente com o usuário. Resultados de código e revisão continuam no coordenador.

O planejador segue o papel [`planejador`](../../../agents/planejador.md): uma pergunta por vez, nada de pendência enquanto a pessoa está na conversa, nunca responder às próprias perguntas, decisão só com fala e data, e o fechamento na conversa como único momento de repassar. Confira que o papel está disponível onde ele roda (instalação no próprio papel); se for apenas o arquivo adotado como papel, use-o somente quando a configuração ou a sessão autorizar, e informe a adaptação, como na [revisão](revisao.md).

Ao concluir, o agente grava `retorno-planejamento.md` no caminho do pacote, no modelo fixo [retorno-planejamento](../assets/retorno-planejamento.md), e avisa o coordenador como os workers ([despacho](despacho.md#aviso-ao-coordenador)). As pendências são abertas pelo arquivo, depois do fechamento ([abrir pelo arquivo](acompanhamento.md#abrir-a-pendência-pelo-arquivo)). O planejador tem o mesmo ciclo dos workers: o coordenador arma a espera ao abrir o pane, e o retorno gravado é o sinal de fim ([acompanhamento](acompanhamento.md#worker-ativo-implica-espera-armada)). Planejador parado esperando a resposta da pessoa é o ponto humano das [anomalias](acompanhamento.md#anomalias), não anomalia. Na TG-23 da plataforma-iac (2026-10-08) o pacote só mandava avisar a pessoa no pane, e ninguém acompanhou o fim do planejamento.

Planejar não autoriza implementar nem escrever no Taiga. O coordenador incorpora o resultado e confere dependências antes de despachar. Ao ler o retorno, confira em `orq pend list --abertas` que cada pendência listada está na Central; a que faltar, registre com `orq pend importar` ou abra pelo arquivo. Na TG-249 do colaboradados (2026-11-06) as sete propostas ficaram só no retorno, e a pessoa não as viu na Central; a pendência que nasce no meio da conversa, por sua vez, é respondida pela pessoa no chat antes de chegar à Central.

## Coordenador que planeja na própria sessão

O coordenador pode planejar coisa pequena na própria sessão, mas segue o mesmo papel [`planejador`](../../../agents/planejador.md), com o mesmo fechamento e o mesmo modelo de retorno. O resultado é gravado em `<raiz>/<projeto>/TG-<ref>/planejamento/`, o diretório da US, e nunca no repositório do coordenador. Origem: decisão de 2026-11-14 na orq #52, depois de um coordenador gravar na documentação da Vault o resultado de um planejamento (colaboradados, 2026-11).
