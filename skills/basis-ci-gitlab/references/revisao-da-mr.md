# A revisão da MR

Da MR devolvida ([`ciclo-da-mr.md`](ciclo-da-mr.md)) até ela estar pronta para o merge. A
revisão é uma rodada própria, feita por **outro agente**, com o `qa-adversarial`: o revisor
parte da premissa de que a MR tem defeito e procura o caso que prova. O valor dele é não
carregar a intenção de quem escreveu — por isso nunca é o executor revendo o próprio
trabalho. O merge continua humano.

Story com a tag `config` não passa por esta revisão
([`taiga-mcp.md`](taiga-mcp.md#mudança-de-configuração-tag-config)). Código que já foi mergeado sem esta revisão se revisa numa story com a tag `review`
([`taiga-mcp.md`](taiga-mcp.md#revisão-global-tag-review)).

## 1. Lançar o revisor

Quem lança é quem lançou o executor — o orquestrador, ou quem pediu —, logo depois do
desfecho `devolvida`, e com a MR ainda **aberta**: `glab mr view <mr> --output json | jq
.state` antes de lançar. MR mergeada não se revisa aqui; vira story com a tag `review`. **Harness, modelo e esforço se escolhem como os da implementação:**
vêm de quem pediu; se não vieram, pergunte antes de lançar. A escolha da implementação não
passa para a revisão sem que alguém a repita.

O `qa-adversarial` é um agente instalado no harness (subagente no Claude Code e no
opencode). Se o harness escolhido não o tem, pergunte — revisão sem ele é outra revisão.

O pacote do revisor:

- a story (`taiga_stories_get`): os critérios de aceite são o que a MR precisa cumprir;
- o link da MR e o relatório de devolução, com as evidências e as suspeitas de falso
  positivo do Sonar;
- o worktree da story, para ler e rodar testes; o diff é `origin/develop...TG-xx`;
- o **escopo da rodada** (abaixo);
- em story crítica — segurança, integridade de dados —, o **modelo de ameaça** (quem é o
  adversário, por onde a entrada chega) e os **limites aceitos**.

O revisor **não edita** o worktree nem empurra na branch: o diagnóstico é dele, a correção é
do executor. Script de reprodução fica fora da árvore do código.

### Escopo por rodada

A r1 é a revisão completa; em story crítica, ela ataca o modelo de ameaça do pacote. Da r2 em
diante a rodada **confirma** as correções no SHA novo e ataca o **delta** — as regressões que
a correção pode ter trazido. Achado novo fora do delta só bloqueia com ocorrência real
(abaixo); `Menor` nunca abre rodada nova. Pacote de r≥2 não pede "procure quebras novas": na
TG-22 do `plataforma-iac`, esse pedido na r2 e um modelo de ameaça só declarado na r7
renderam 9 revisões, cada uma com uma variante mais exótica da mesma máscara.

### Severidade ancorada no ambiente real

Achado `Bloqueante` ou `Sério` diz em qual projeto, consumidor ou configuração real nossa o
caso ocorre. Sem ocorrência real — entrada construída, condição que nenhum ambiente nosso
produz, "não verifiquei produção" — é `Menor`, ou limite documentado no resumo. Na r8 da
TG-22, o Bloqueante era um codec alternativo que o próprio revisor mediu em 14 de 200.000
senhas, e nenhum playbook do `infraestrutura` usa codec alternativo; dos Bloqueantes e Sérios
de rodadas ≥3 em 83 stories, 70% eram desse tipo.

## 2. Registrar o resultado na MR

- Cada achado `Bloqueante` ou `Sério` vira uma **discussão resolvível**, no formato do
  `qa-adversarial` (onde, caso, esperado, acontece, como sei). Resolvível porque é o que
  segura o merge em projeto que exige todas as discussões resolvidas.
- O resumo — desfecho, achados `Menor`, suspeitas sem caso construído e a seção `O que
  tentei e não quebrou` — vai num comentário não resolvível.

```sh
glab mr note create <mr> -m "<achado no formato do qa-adversarial>"
glab mr note create <mr> --resolvable=false -m "<resumo da revisão>"
```

Quem resolve uma discussão de achado é a rodada de revisão seguinte, ao confirmar a
correção no SHA novo — nunca o executor.

## 3. Os dois desfechos

**Aprovada** — nenhum achado `Bloqueante` nem `Sério`, e a pipeline do SHA revisado aceita
([`ciclo-da-mr.md`](ciclo-da-mr.md#2-vincular-a-pipeline-ao-sha-revisado)) — a TG-247 foi
aprovada com o CI vermelho. O revisor tira o Draft
(`glab mr update <mr> --ready`), e só aqui: é o sinal de que a MR pode ser mesclada. A story
fica em `In revision` (ou `In progress`, sem esse status), e a MR aguarda o merge humano.
Aprovar a MR no GitLab e fazer o merge são da pessoa.

**Com achados** — ao menos um `Bloqueante` ou `Sério`. A MR **continua em Draft**, onde nasceu
([`ciclo-da-mr.md`](ciclo-da-mr.md#1-abrir-a-mr)); se alguém a tirou, o revisor a devolve
(`glab mr update <mr> --draft`). O GitLab recusa o merge de MR em Draft, e é isso que impede
alguém de mergear a MR antes da correção. Na US #15 do `plataforma-iac`, a MR !27 foi
mergeada com dois achados `Sério` em aberto, e a correção pronta ficou sem MR onde entrar; na
!296 do `portal-liven` (TG-53), aberta sem Draft, o merge veio com a revisão ainda rodando.
A story **fica em `In revision`**: o status é a barreira entre a devolução e o merge, e as
idas e voltas entre revisor e executor acontecem dentro dela — o Draft da MR é o que diz que
há correção pendente. A próxima rodada
do executor retoma o mesmo worktree e a mesma MR ([`worktree.md`](worktree.md#retomar)),
corrige, devolve de novo pelo [`ciclo-da-mr.md`](ciclo-da-mr.md), e a revisão roda outra
vez sobre o SHA novo.

**Recorrência se conta por classe**, não pelo caso: outro encoding escapando da mesma máscara
é a mesma classe. Na **2ª** ocorrência, o pacote de correção pede a classe — o executor
corrige o mecanismo e lista as variantes testadas
([`ciclo-da-mr.md`](ciclo-da-mr.md#antes-de-devolver)). Na 3ª, a story é interrompida, com
registro de bloqueio, e o que sobe para quem pediu é uma **decisão de desenho** (allowlist em
vez de blocklist, limite aceito), não mais uma rodada no mesmo desenho.

**Antes de relançar o executor**, quem lança confere que a MR continua aberta (o `state`,
como no passo 1). Mergeada mesmo assim, a correção vai numa rodada nova, com worktree e MR
novos ([`worktree.md`](worktree.md#retomar)), que é decisão de quem pediu.

As transições seguem a autorização de [`taiga-mcp.md`](taiga-mcp.md#atualizar-o-status).

## 4. O relatório da revisão

Vai para quem lançou o revisor:

- Desfecho: `aprovada` | `com achados` | `falhou` (a revisão não terminou: sessão caiu,
  ferramenta indisponível)
- Link da MR (URL completa) e o SHA revisado
- Harness, modelo e esforço usados
- Achados por severidade, com o link de cada discussão
- O que foi executado (testes, reproduções) e o que foi só lido
