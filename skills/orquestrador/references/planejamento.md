# Planejamento em conversa dedicada

Quando planejamento puder avançar sem esperar a rodada atual, ofereça ao usuário discutir o assunto com um agente de planejamento em outro pane. Exemplo: “Enquanto acompanhamos a implementação, quer discutir a fase seguinte em um painel de planejamento?” Aguarde aceite para abrir essa conversa.

Resolva o alias de planejamento e use o template. Inclua origem, objetivo, stories, decisões, dependências, situação da execução e perguntas abertas. Envie contexto por prompt ou mecanismo de handoff disponível. Use `ai-memory-handoff` se usar continuidade da memória; não consuma nem crie handoffs em outro escopo por conveniência. O prompt explícito é suficiente quando não há transferência de sessão.

Abra o pane no workspace do coordenador, como em [despacho](despacho.md#inicialização). Nomeie o pane como em [nomes dos panes](despacho.md#nomes-dos-panes) e mostre rótulo, nome de agente e ID ao usuário. Consulte a CLI instalada para descobrir foco/navegação; só mude o foco quando o usuário pedir ou aceitar a mudança de contexto. Se não houver função de foco, indique o pane pelo nome e ID.

O agente começa: “Esta conversa foi encaminhada pelo Orquestrador de <projeto> para discutirmos <assunto>.” Ele conversa diretamente com o usuário. Resultados de código e revisão continuam no coordenador.

O planejador segue o papel [`planejador`](../../../agents/planejador.md): uma pergunta por vez, nada de pendência enquanto a pessoa está na conversa, nunca responder às próprias perguntas, decisão só com fala e data, e o fechamento na conversa como único momento de repassar. Confira que o papel está disponível onde ele roda (instalação no próprio papel); se for apenas o arquivo adotado como papel, use-o somente quando a configuração ou a sessão autorizar, e informe a adaptação, como na [revisão](revisao.md).

Ao concluir, o agente grava `retorno-planejamento.md` no caminho do pacote, no modelo fixo [retorno-planejamento](../assets/retorno-planejamento.md), e avisa o coordenador como os workers ([despacho](despacho.md#aviso-ao-coordenador)). As pendências são abertas pelo arquivo, depois do fechamento ([abrir pelo arquivo](acompanhamento.md#abrir-a-pendência-pelo-arquivo)). O planejador tem o mesmo ciclo dos workers: o coordenador arma a espera ao abrir o pane, e o retorno gravado é o sinal de fim ([acompanhamento](acompanhamento.md#worker-ativo-implica-espera-armada)). Planejador parado esperando a resposta da pessoa é o ponto humano das [anomalias](acompanhamento.md#anomalias), não anomalia. Na TG-23 da plataforma-iac (2026-10-08) o pacote só mandava avisar a pessoa no pane, e ninguém acompanhou o fim do planejamento.

Planejar não autoriza implementar nem escrever no Taiga. O coordenador incorpora o resultado e confere dependências antes de despachar. Ao ler o retorno, confira em `orq pend list --abertas` que cada pendência listada está na Central; a que faltar, registre com `orq pend importar` ou abra pelo arquivo. Na TG-249 do colaboradados (2026-11-06) as sete propostas ficaram só no retorno, e a pessoa não as viu na Central; a pendência que nasce no meio da conversa, por sua vez, é respondida pela pessoa no chat antes de chegar à Central.

## Spec da US: estrutura, fluxo e validação

Vale para os projetos coordenados pelo orq (orq #59; desenho no épico "Publicar e revisar especificações na Central", `docs/specs/publicar-e-revisar-especificacoes/` do `BasisTI/orq`). Os comandos `orq spec registrar|conferir` e a pendência `validacao` exigem o `orq` com a migration 0011 (`orq upgrade`); sem eles, pare no passo 3 e peça o upgrade à pessoa.

**Estrutura.** A spec de uma US mora no repositório do projeto, em `docs/specs/<épico>/tg-<ref>-<nome-curto>/` (`spec.md`, `plano.md`, `decisoes.md`), ou em `docs/specs/sem-epico/tg-<ref>-<nome-curto>/`. O `README.md` do épico fica em `docs/specs/<épico>/`. O plano mora na pasta da US (nada de `plans/` na raiz), e Superpowers e as demais skills de spec gravam nessa pasta, não em `docs/superpowers/`; o pacote do planejador repassa isso. Depois da entrega a pasta fica congelada.

**Verificação antes de planejar.** Antes de abrir o planejador, confira se o projeto segue a estrutura (`docs/specs/` com pasta por US; spec ou plano em `docs/superpowers/`, `planos/`, `PLANO-*` e afins estão fora do padrão). Se não segue, mostre à pessoa o que está fora e pergunte se pode reorganizar; a reorganização é trabalho seu naquele projeto, com autorização própria: spec antiga de uma US vai para a pasta dela, e a que abrange várias US fica inteira no nível do épico, junto do `README.md`, com cada pasta de US apontando para ela. Sem o sim, planeje no formato antigo e diga isso no pacote.

**Fluxo, passos 0–8.**

0. Planeje dentro de uma onda com limite "até plano". Sem US para a spec, crie a US em New antes (autorização de transição de status do coordenador, não a do planejamento): a ref dela é a chave da spec.
1. **Antes de abrir o planejador**, crie o worktree e a branch da US (o cwd do pane do planejador é o worktree) e grave os recursos (`orq recursos gravar`); sem isso o `orq limpar` recusa a US. O planejador grava `spec.md`, `plano.md` e `decisoes.md` na pasta da US, na branch da US, e continua gravando o `retorno-planejamento.md`.
2. Abra, da branch do planejamento, uma MR que contenha **só a pasta da spec**.
3. Registre a spec: `orq spec registrar TG-<ref> --caminho <pasta da US> --mr <url da MR da spec>`. O repositório sai da URL; o mesmo comando liga a MR à US (não rode `orq mr add` antes). Se a US já tem spec, o comando recusa e mostra o registro atual: **primeiro tente sem `--substituir`**, avise a pessoa, pergunte se substitui e só com o sim repita com `--substituir` (o diário guarda o registro anterior).
4. Abra a pendência de validação pelo arquivo (`tipo: validacao`, com as seções do modelo; `titulo` e `opcoes` são ignorados) ou, sem detalhe, por `orq pend add TG-<ref> --tipo validacao`. O orq impõe o título "Spec da TG-<ref> pronta para validar", as opções **Aprovar** e **Pedir ajustes** (nenhuma recomendada), mais o texto livre, e grava **ele mesmo** o SHA da cabeça da MR: nunca escreva o SHA. Sem spec registrada a importação é recusada (`.erro.txt`); com a forja fora do ar o arquivo fica retido, sem `.erro.txt`, e o daemon importa quando ela voltar.
5. **Aprovar** (resposta repassada com `orq pend responder … --opcao 1`, depois `orq pend resolver`): acrescente ao `decisoes.md` a entrada de aprovação com o **SHA aprovado** (o que a pendência guardou: `orq pend ver`) e a análise do usuário final, se houver. Antes de mesclar rode `orq spec conferir TG-<ref>`: só "pode mesclar" libera. A conferência compara o conteúdo da **pasta registrada** entre o SHA aprovado e a cabeça e só aceita mudança em `<pasta>/decisoes.md`; mudou outro arquivo da pasta → não mescle, abra nova pendência. Se a conferência avisar "a MR não é só da spec" (arquivos de fora da pasta, por exemplo depois de rebase ou do merge da base), isso é outro sinal: confira o que entrou antes de mesclar, mas não é reprovação da spec. Então mescle a MR da spec pelo fluxo normal do projeto e passe a US de New para Ready.
5a. Depois do merge da spec a limpeza automática da US roda (é esperado). Para o código: `orq recursos reabrir <ref>`, worktree e branch **novos, com sufixo de rodada**, regrave os recursos e ligue a MR do código com `orq mr add`. Nunca reaproveite o worktree nem a branch da MR da spec.
6. **Pedir ajustes:** a resposta entra no `decisoes.md`, e você devolve os pontos ao planejador para nova rodada na mesma MR; a nova rodada exige **nova** pendência `validacao`, com o novo SHA.
7. Durante a onda, acrescente ao `decisoes.md` as respostas de pendência e os ajustes de plano, no worktree e na branch do código.
8. Depois do merge do código, a pasta da US fica congelada.

A Central mostra, no card da US, o estado da spec: *registrada*, *em validação* (SHA), *aprovada* (SHA), *mudou além do decisoes.md* ou *mesclada*; o mesmo está em `orq snapshot` (campo `spec`).

**Formato do `decisoes.md`.** Uma seção por entrada, com campos fixos. Quem escreve, escreve **para o cliente**: o usuário do sistema lê o arquivo pelo link da spec. Origem sempre por referência (`TG-<ref>#P<n>`), nunca nome de pane, e sem comentário interno; se a resposta da pendência tiver texto interno, registre só a decisão.

```markdown
## D<n> — <título curto>
- **Data:** AAAA-MM-DD
- **Origem:** conversa de planejamento (r<n>) | TG-<ref>#P<n>, respondida em AAAA-MM-DD
- **Decisão:** <o que foi decidido>
- **Fala:** "<fala do responsável>"
```

A entrada de aprovação traz também `- **SHA aprovado:** <sha>`. Decisão que vale além da US é proposta como ADR em `docs/decisoes/`.

## Coordenador que planeja na própria sessão

O coordenador pode planejar coisa pequena na própria sessão, mas segue o mesmo papel [`planejador`](../../../agents/planejador.md), com o mesmo fechamento e o mesmo modelo de retorno. O resultado é gravado em `<raiz>/<projeto>/TG-<ref>/planejamento/`, o diretório da US, e nunca no repositório do coordenador. Origem: decisão de 2026-11-14 na orq #52, depois de um coordenador gravar na documentação da Vault o resultado de um planejamento (colaboradados, 2026-11).
