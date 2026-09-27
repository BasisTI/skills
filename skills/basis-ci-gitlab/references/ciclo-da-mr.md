# O ciclo da MR até a devolução

Do primeiro push até a MR devolvida para revisão humana, no worktree da story
([`worktree.md`](worktree.md)). O trabalho termina num de dois **desfechos** — devolvida ou
interrompida — e num relatório. Revisão e merge não fazem parte dele.

## 1. Abrir a MR

Commits no padrão da skill (`<Verbo> ... - TG-xx`), primeiro push com upstream:

```sh
git push --set-upstream origin TG-xx
glab mr create --target-branch develop --squash-before-merge --remove-source-branch \
  --title "<título no padrão do commit> - TG-xx" --description "<resumo>" --yes
```

**Retomada:** se há MR `TG-xx` **aberta**, a rodada continua nela — só `git push`. Uma
segunda MR aberta para a mesma story divide a revisão e os comentários de evidência em dois
lugares. `glab mr list --source-branch TG-xx` lista as abertas; MR já mergeada não se retoma
(ver [`worktree.md`](worktree.md#retomar)).
Na retomada de uma story interrompida, desfaça o bloqueio (`is_blocked: false`, pela API —
ver [`taiga-mcp.md`](taiga-mcp.md#gravar-e-ler-os-registros-pela-api-do-taiga)) — com a
mesma autorização das outras transições.

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

O GitLab da Basis é CE (18.0.2 em 2026-09-27), sem *merged results pipelines*: a pipeline de
MR roda no próprio head, e a comparação de SHA é direta.

`glab ci status` não serve para isso: ele lê a pipeline mais recente **da branch**, que pode
ser uma pipeline de branch sem os jobs de MR, ou de outro SHA. Registre o id, o SHA e o link
da pipeline aceita — vão para o relatório.

## 3. Corrigir e repetir

Leia as falhas e as issues do Sonar, corrija, faça commit e push — e **volte ao passo 2 a
cada push**. A pipeline verde anterior não vale para o SHA novo.

Cada rodada que termina reprovada conta como uma **tentativa registrada**: a causa (o job e
a mensagem, ou a regra do Sonar e o arquivo) e o que foi mudado. É o registro que decide o
desfecho.

## 4. Os dois desfechos

**Devolvida para revisão** — `check-quality` verde no SHA atual, **ou** reprovada
exclusivamente por suspeitas de falso positivo do Sonar (abaixo). Status → `In revision`, se
o board tiver; senão a story continua `In progress`. Relatório com desfecho `devolvida`.

**Interrompida** — a **mesma causa** aparece em 3 tentativas registradas, ou há um
impedimento externo: acesso, ambiente, dúvida de especificação. Uma correção que revela uma
falha **nova** é progresso, não repetição. A contagem é por causa, no total da rodada: causas
que se alternam (A, B, A, B, A) fecham 3 tentativas de A e interrompem. Registro de bloqueio
(`is_blocked` + `blocked_note` com a causa, pela API); status continua `In progress`.
Relatório com desfecho `bloqueada`, a causa, as tentativas e a última falha. `falhou` fica
para a rodada que não chegou a nenhum dos dois desfechos por falha do próprio executor
(sessão caiu, ferramenta indisponível no meio do ciclo).

As transições deste passo seguem a autorização de
[`taiga-mcp.md`](taiga-mcp.md#atualizar-o-status): pacote do orquestrador que as liste, ou
confirmação de quem pediu.

## Suspeita de falso positivo do Sonar

Quando uma issue parece falso positivo, **liste-a e deixe a decisão com quem revisa**. Para
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

## O relatório de devolução

- Desfecho: `devolvida` | `bloqueada` | `falhou`
- Link da MR
- Pipeline: id, SHA, link; `check-quality` executado e resultado
- Link(s) do(s) comentário(s) de evidência
- Sonar: `ok`, ou a lista de suspeitas de falso positivo
- Testes executados e resultado
- Tentativas (se interrompida), dúvidas e bloqueadores

## Depois do desfecho

O agente **para**. Revisão e merge são humanos. As transições seguintes — `Ready for test`,
`Waiting for deployment`, `Done` — são do orquestrador ou de quem acompanha, pelos critérios
de [`taiga-mcp.md`](taiga-mcp.md) e pela [cadeia de entrega](cadeia-de-entrega.md). Se a
revisão pedir mudança com a MR ainda aberta, a próxima rodada retoma o mesmo worktree e a
mesma MR.
