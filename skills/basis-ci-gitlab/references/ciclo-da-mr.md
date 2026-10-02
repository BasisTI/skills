# O ciclo da MR até a devolução

Do primeiro push até a MR devolvida para revisão, no worktree da story
([`worktree.md`](worktree.md)). O trabalho termina num de dois **desfechos** — devolvida ou
interrompida — e num relatório. A revisão é de outro agente
([`revisao-da-mr.md`](revisao-da-mr.md)), e o merge é humano.

## 1. Abrir a MR

Commits no padrão da skill (`<Verbo> ... - TG-xx`), primeiro push com upstream:

```sh
git push --set-upstream origin TG-xx
glab mr create --target-branch develop --squash-before-merge --remove-source-branch --draft \
  --title "<título no padrão do commit> - TG-xx" --description "<resumo>" --yes
```

A MR nasce em **Draft** e fica nele durante este ciclo e as rodadas de revisão: o Draft é a
trava que impede o merge antes de a revisão aprovar. Quem o tira é a revisão aprovada
([`revisao-da-mr.md`](revisao-da-mr.md#3-os-dois-desfechos)); com a tag `config`, que não passa
por revisão, a devolução (passo 4).

Guarde a URL que o `glab mr create` imprime: é ela, e não o `!N`, que vai na resposta, no
relatório e nos comentários (ver "A MR se cita pelo link" na `SKILL.md`).

**Retomada:** se há MR `TG-xx` **aberta**, a rodada continua nela — só `git push`. Uma
segunda MR aberta para a mesma story divide a revisão e os comentários de evidência em dois
lugares. `glab mr list --source-branch TG-xx` lista as abertas; MR já mergeada não se retoma
(ver [`worktree.md`](worktree.md#retomar)). Story bloqueada chega aqui já desbloqueada:
o desbloqueio é o começo da rodada ([`taiga-mcp.md`](taiga-mcp.md#retomar-story-bloqueada)).

## 2. Vincular a pipeline ao SHA revisado

A pipeline que vale é a do **head da MR**, lida na própria MR:

```bash
glab mr view <mr> --output json | jq '{sha, head_pipeline: {id: .head_pipeline.id, sha: .head_pipeline.sha, status: .head_pipeline.status, web_url: .head_pipeline.web_url}}'
glab api "projects/:id/pipelines/<pipeline_id>/jobs" | jq '.[] | select(.name=="check-quality") | {status, web_url}'
```

Aceite a pipeline só quando as duas condições valem:

- `head_pipeline.sha` é igual ao `sha` da MR. Logo depois de um push, `head_pipeline` ainda
  aponta para a pipeline do SHA anterior — verde, e sem dizer nada sobre o código novo.
- O job `check-quality` está na lista e terminou: status final (`success` ou `failed`) —
  nem `skipped`, nem ausente, nem ainda `pending`/`running`. Pipeline sem
  `check-quality` não analisou nada (MR aberta para `main`, `ref` do template antigo, ou
  pipeline de branch em vez de pipeline de MR).

**Para esperar, use `scripts/esperar-pipeline-mr.sh <mr>`**, de dentro do repositório. Ele
repete a leitura acima até o `head_pipeline` ser do head e ter terminado, e sai com 0 (aceita:
pipeline e `check-quality` em `success`, com análise), 1 (terminou e não serve), 3 (limite de
tempo, padrão 1 h) ou 4 (**verde sem análise**: o `check-quality` passou dizendo "Nenhuma
mudança detectada", porque a MR não tocou caminho de target). O 4 é o normal numa story com
a tag `config`; numa mudança de código, significa que nada foi avaliado — investigue o
`ci/pipeline.toml` em vez de devolver. Imprime uma linha por mudança de estado e sempre o resumo final — rode-o direto
num monitor ou em segundo plano, sem laço em volta. Não improvise essa espera: na US #14 do
`plataforma-iac`, um laço feito na hora com `set -- $out` sob zsh nunca casou o SHA, e o
agente ficou 30 minutos parado depois de a pipeline terminar, até o monitor estourar.

Depois do push, o `head_pipeline` pode continuar na pipeline anterior por alguns minutos,
com a nova já rodando: é esperar o SHA bater, não aceitar a antiga. Na listagem de pipelines
da MR (`merge_requests/<iid>/pipelines`) aparecem também pipelines de origem `external` —
os status que o Sonar publica —, que não são a pipeline da MR; o `head_pipeline` não as usa.

O GitLab da Basis é CE (18.0.2 em 2026-09-27), sem *merged results pipelines*: a pipeline de
MR roda no próprio head, e a comparação de SHA é direta.

`glab ci status` não serve para isso: ele lê a pipeline mais recente **da branch**, que pode
ser uma pipeline de branch sem os jobs de MR, ou de outro SHA. Registre o id, o SHA e o link
da pipeline aceita — vão para o relatório.

## 3. Corrigir e repetir

Leia as falhas e as issues do Sonar, corrija, faça commit e push — e **volte ao passo 2 a
cada push**. A pipeline verde anterior não vale para o SHA novo.

Conta como **tentativa registrada** a rodada que empurrou uma correção para a causa e
terminou reprovada: a causa (o job e a mensagem, ou a regra do Sonar e o arquivo) e o que foi
mudado. Pipeline de um SHA já superado, ou de um push que não tentava corrigir aquela causa
(um ajuste de nome de teste, por exemplo), não conta — senão duas pipelines reprovadas pela
mesma causa antes de qualquer correção já seriam 2 das 3 tentativas. É o registro que
decide o desfecho.

## 4. Os dois desfechos

**Devolvida para revisão** — `check-quality` verde no SHA atual, **ou** reprovada
exclusivamente por suspeitas de falso positivo do Sonar (abaixo). Status → `In revision`, se
o board tiver; senão a story continua `In progress`. Relatório com desfecho `devolvida`.
A MR **continua em Draft**: devolver é pedir revisão, não liberar o merge. A exceção é a
story com a tag `config`, que não tem revisão: aí a devolução tira o Draft
(`glab mr update <mr> --ready`) e a MR vai direto ao merge humano.

**Interrompida** — a **mesma causa** aparece em 3 tentativas registradas, ou há um
impedimento externo: acesso, ambiente, dúvida de especificação, dependência de story não
mergeada ([`taiga-mcp.md`](taiga-mcp.md#a-story-pode-começar)). Uma correção que revela uma
falha **nova** é progresso, não repetição. A contagem é por causa, no total da rodada: causas
que se alternam (A, B, A, B, A) fecham 3 tentativas de A e interrompem. Registro de bloqueio
(`is_blocked` + `blocked_note` com a causa, pela API); status continua `In progress` — ou o
que era, se a interrupção veio antes do registro de início.
Relatório com desfecho `bloqueada`, a causa, as tentativas e a última falha. `falhou` fica
para a rodada que não chegou a nenhum dos dois desfechos por falha do próprio executor
(sessão caiu, ferramenta indisponível no meio do ciclo).

As transições deste passo seguem a autorização de
[`taiga-mcp.md`](taiga-mcp.md#atualizar-o-status): pacote do orquestrador que as liste, ou
confirmação de quem pediu.

## Suspeita de falso positivo do Sonar

Quando uma issue parece falso positivo, **liste-a e deixe a decisão com a pessoa que faz o
merge**. Para
cada uma: regra, `arquivo:linha`, link da issue e uma linha de justificativa. E declare no
relatório que **a pipeline continua reprovada** até alguém avaliar.

Marcar a issue no Sonar (`False Positive` ou `Accept`) ou suprimi-la no código
(`@SuppressWarnings`, `// NOSONAR`) apaga a evidência antes de alguém olhar — o agente vira
juiz da própria reprovação. Isso é decisão humana, sempre.

## Evidências na MR

Um comentário na MR **por funcionalidade**: descrição curta e, embaixo, a evidência anexada.

```sh
glab mr note create <mr> --resolvable=false -m "<descrição da funcionalidade>" \
  --attach <arquivo> [--attach <outro>]
```

Não resolvível para não bloquear o merge em projeto que exige todas as discussões
resolvidas. A evidência é a que prova a funcionalidade: captura de tela para tela, log para
job ou integração, resposta de API para endpoint, relatório de teste para regra de negócio.
Evidência que fica só no worktree some com o `wt remove`.

**Tela atrás de login que o agente não completa** (SSO, autorização OAuth do GitLab): use a
tela renderizada nos testes — o HTML que o servidor devolve, com o CSS do build, capturado
num navegador sem sessão — e **diga no comentário** que não houve sessão real. A captura com
login fica para a pessoa que faz o merge. Não contorne a autenticação para tirar a foto.

**As discussões do Sonar se resolvem sozinhas.** Quando o quality gate passa, o Sonar marca
como resolvidas as discussões que abriu na MR. O executor não resolve discussão nenhuma à
mão — nem as do Sonar, nem as da revisão.

## O relatório de devolução

Vai para quem pediu o trabalho — o orquestrador, ou a pessoa, na resposta final —, e um
resumo (desfecho, pipeline aceita, links das evidências) vai num comentário não resolvível
da MR, para quem revisa sem acesso à conversa.

- Desfecho: `devolvida` | `bloqueada` | `falhou`
- Link da MR (URL completa)
- Pipeline: id, SHA, link; `check-quality` executado, resultado, e **o que ele avaliou** —
  os targets analisados, ou "sem análise: nenhuma mudança detectada"
- Link(s) do(s) comentário(s) de evidência
- Sonar: `ok`, ou a lista de suspeitas de falso positivo
- Testes executados e resultado
- Tentativas (se interrompida), dúvidas e bloqueadores

**Interrompida antes da MR** — a story não pôde começar, ou parou antes do primeiro push:
desfecho `bloqueada`, a causa, e "não houve MR" no lugar dos itens de MR, pipeline,
evidências e Sonar. O relatório vai só para quem pediu; o `blocked_note` da story faz o papel
do comentário na MR. Diga também em que estado ficaram o worktree e a branch (limpo, com
commits locais) e se o registro de início foi feito.

## Depois do desfecho

O agente **para**. A revisão é outra rodada, de outro agente, com o `qa-adversarial`
([`revisao-da-mr.md`](revisao-da-mr.md)); o merge é humano. As transições seguintes — `Ready for test`,
`Waiting for deployment`, `Done` — são do orquestrador ou de quem acompanha, pelos critérios
de [`taiga-mcp.md`](taiga-mcp.md) e pela [cadeia de entrega](cadeia-de-entrega.md). Se a
revisão pedir mudança com a MR ainda aberta, a próxima rodada retoma o mesmo worktree e a
mesma MR.
