# Configuração local do coordenador

## Instalação e precedência

Instale `orquestrador` no escopo de projeto, nunca com `--global`. No coordenador, use a raiz local de skills suportada pelo harness (por exemplo `.agents/skills/` ou `.claude/skills/`). A descoberta deve ser confirmada em cada harness.

Copie o exemplo de `assets/` para `config/orquestrador.toml`. Ajuste caminhos, identidades e modelos antes do primeiro uso. Ignore `config/orquestrador.local.toml` no Git; credenciais ficam fora de ambos e entram por referência.

Precedência: escolha explícita atual do usuário → preferência persistente autorizada → arquivo local → arquivo compartilhado. Mescle tabelas por nome e campos por chave; listas do arquivo local substituem a lista anterior. Registre a resolução. Esta convenção é desta skill, não um recurso do parser TOML.

## Duas tabelas

**Aliases**: cada nome resolve harness, modelo, esforço e perfil de ambiente. O perfil contém capacidades e permissões verificadas, sem prometer que o sandbox as concederá.

**Seleção**: regras associam papel, complexidade e risco a um alias. Use o primeiro seletor compatível, na ordem do arquivo; `*` aceita qualquer valor. Papéis iniciais: planejamento, implementação e revisão. Avalie complexidade por ambiguidade, extensão e dependências; risco por impacto e reversibilidade. Documente a classificação.

Fallback só usa aliases listados e disponíveis. Se nenhum puder cumprir o contrato, reporte bloqueio e peça a escolha que falta. Escalada por ambiguidade ou falhas recorrentes usa a política configurada; não autoriza gasto ou modelo fora das escolhas do usuário.

## Autonomia e transições automáticas

A autorização permanente vive em `[autonomia]`, não na memória de um harness: o Codex coordenador não lê a memória do Claude.

- `modo_autonomo = true`: o coordenador conduz executor → revisão → correções e volta ao usuário só em bloqueio ou término.
- `transicoes_automaticas`: transições derivadas de evento comprovado, que o coordenador executa sem perguntar ([valores](#transicoes_automaticas)).
- `merge_automatico`: branches de destino em que o coordenador mescla a MR sem perguntar ([condições](#merge_automatico)).
- `acoes_automaticas`: ações repetidas que o coordenador faz sem perguntar ([valores](#acoes_automaticas)).

Esta seção é o único lugar da regra; as outras páginas apontam para ela. `[projetos.<chave>.autonomia]` sobrescreve a global por chave; lista do projeto substitui a global. Chave ausente vale como lista vazia: o que não está listado segue como pergunta concreta. Aceite funcional, hotspot do Sonar, tag, publicação, deploy e qualquer escrita ou leitura automática de produção não entram aqui.

Origem: decisão do Cedric em 2026-10-17 (orq #14). Numa pesquisa no ai-memory da Vault, de 2026-09-30 a 2026-10-17, ele autorizou as mesmas ações sessão após sessão: `Ready for test` depois do merge (6 ou mais vezes), fechar panes e worktree (8 ou mais), `Done` depois do teste (12 ou mais), tirar o Draft (5 ou mais), resolver conflito (2) e despachar com o par padrão (várias).

### Fluxo de status por tipo de projeto

O tipo vem de `branch_base` no [cadastro do projeto](#cadastro-de-projetos-e-ambiente).

| | Projeto com `develop` | Projeto com `branch_base = main` |
|---|---|---|
| Merge da MR | automático na `develop`, se `merge_automatico` a lista ([condições](#merge_automatico)) | humano |
| Depois do merge | `Ready for test`, quando a cadeia de entrega mostra o ambiente de teste rodando a versão | o mesmo |
| A pessoa diz que testou | `Waiting for deployment` | `Done` |
| Commit da US chega à `main` | `Done` (a release `develop` → `main`, que continua humana) | não se aplica |

Hoje têm `branch_base = main` `argocd-apps`, `infraestrutura`, `taiga-cli`, `pulumi-proxmox-vms`, `orq` e `skills`; a fonte é o cadastro, não esta lista. `Done:config` segue como estava. Critérios de cada status, registro de teste e cadeia de entrega são os da `basis-ci-gitlab`; a configuração só diz quais transições o coordenador faz sem perguntar. Board sem o status opcional `Waiting for deployment`: o "testei" não move a story, e o `Done` vem com o commit na `main`.

### `transicoes_automaticas`

| Valor | Evento comprovado | Transição |
|---|---|---|
| `"Ready for test"` | MR mesclada e o ambiente de teste (staging, ou o declarado pelo projeto) roda a versão do merge, pela cadeia de entrega | `Ready for test` |
| `"Waiting for deployment:testado"` | projeto com `develop`; a pessoa diz que testou a US, que está em `Ready for test` | `Waiting for deployment` |
| `"Done:main"` | projeto com `develop`; o commit do merge da US é ancestral da `main` (`git merge-base --is-ancestor <sha do merge> origin/main`) | `Done` |
| `"Done:testado-main"` | projeto com `branch_base = main`; a pessoa diz que testou a US, que está em `Ready for test` | `Done` |
| `"Done:config"` | story com a tag `config`, MR mesclada e a primeira pipeline da branch base verde | `Done` |

"Testei a US 14" é o evento. Confira que a US existe, está em `Ready for test` e é do projeto certo; grave o registro de teste como a `basis-ci-gitlab` manda, com a frase e a data como evidência, e então mova, sem perguntar. Frase ambígua ("acho que está bom", "testei parte") não é evento: pergunte. Em `Done:main` o evento é o commit na `main`, não o deploy: a cadeia até os pods, que o `Done` comum da `basis-ci-gitlab` pede, não é conferida, por decisão de 2026-10-17. Valor fora da lista é pergunta concreta ("posso mover a TG-xx para X?").

### `merge_automatico`

Lista de branches de destino; hoje só `["develop"]`. O coordenador mescla a MR cujo destino está na lista, sem perguntar, quando **todas** as condições valem **no head atual**, lidas na hora e não herdadas de leitura anterior:

1. revisão independente aprovada nesse SHA ([revisão](revisao.md)), gravado em `--aprovado`. Story `config` não tem revisão e, por isso, o merge dela segue humano;
2. pipeline verde nesse SHA: `head_pipeline.sha` igual ao `sha` da MR e `check-quality` terminado ([ciclo da MR](../../basis-ci-gitlab/references/ciclo-da-mr.md#2-vincular-a-pipeline-ao-sha-revisado));
3. quality gate do Sonar OK nesse SHA, quando o projeto usa Sonar. Gate reprovado, ausente, em andamento ou não conferido é recusa: pipeline verde sem análise não prova o gate ([Sonar](../../basis-ci-gitlab/references/sonar-analise-e-quality-gate.md));
4. sem Draft;
5. sem discussão bloqueante: `blocking_discussions_resolved` verdadeiro e nenhuma discussão resolvível aberta, a de evidência do executor inclusa ([revisão](revisao.md));
6. sem conflito: `has_conflicts` falso e `detailed_merge_status` que permita mesclar.

Faltou uma, não mescle e diga qual. Gate reprovado volta ao executor como correção, pelo ciclo normal de revisão; gate não conferido, leia-o você, no SHA do head, e só peça a pessoa se não houver acesso ao Sonar. Mescle atando ao SHA conferido, para o GitLab recusar se houve push entre a leitura e o merge:

```bash
glab mr merge <mr> --sha <sha conferido> --squash --remove-source-branch --yes
```

Confira `state: merged` depois e siga o pós-merge ([auditoria](conclusao-e-limpeza.md#auditoria-proativa)). Merge em `main`, `staging` ou qualquer branch fora da lista continua humano, inclusive o da release `develop` → `main` e inclusive numa onda autorizada a ir "até o merge" ([ondas](ondas.md#o-contrato)). Projeto `branch_base = main` não tem MR para a `develop`: o merge segue humano.

### `acoes_automaticas`

| Valor | O coordenador faz, sem perguntar |
|---|---|
| `"limpeza"` | Fechar panes do executor e do revisor e remover worktree, branches e pastas em `~/tmp` e `/tmp` da US depois do merge; reabrir pane e worktree para corrigir depois do teste ([limpeza](conclusao-e-limpeza.md#limpeza-depois-do-merge)). |
| `"tirar-draft"` | Tirar o Draft da MR (`glab mr update <mr> --ready`) com a revisão aprovada no head e o CI verde nesse head ([revisão](revisao.md)). |
| `"rebase-conflito"` | MR em conflito: o executor faz o rebase e o revisor confirma o delta ([revisão](revisao.md#conflito)). |
| `"par-padrao"` | "Despacha" sem executor e revisor indicados usa `implementacao-padrao` e `revisao-padrao` ([despacho](despacho.md#par-padrão)). |

Cada ação cobre só o que a linha diz. `limpeza` não apaga o que o `orq limpar` recusa; `tirar-draft` não substitui a aprovação; `rebase-conflito` não vale para a MR de release.

## Status na sidebar do Herdr

Passo de instalação, feito pelo usuário no `config.toml` do Herdr (`herdr --default-config` mostra o padrão). O coordenador não altera essa configuração. Com a [Central](central.md), `orq plugin configurar` acrescenta as linhas `$orq` e `$orq_mrs`, que o daemon publica, e o resto desta seção não se aplica; as linhas manuais que já existirem ficam, vazias depois da [migração](central.md#com-ou-sem-central), e removê-las é opcional. Sem ela, acrescente uma linha com os tokens manuais às linhas existentes:

```toml
[ui.sidebar.agents]
rows = [["state_icon", "machine", "workspace", "tab"], ["agent"], ["$story", "$fase"]]

[ui.sidebar.spaces]
rows = [["state_icon", "workspace"], ["branch", "git_status"], ["$mrs_prontas"]]
```

Se houver `[ui.sidebar.agents.rows_by_agent]`, a linha entra também em cada agente listado, porque essas linhas substituem `rows`. Com a linha a mais, o limite padrão de 36 colunas corta o texto: suba `sidebar_max_width` (e, se quiser, `sidebar_width`) em `[ui]`; a borda da sidebar se arrasta com o mouse até esse limite. Depois, `herdr server reload-config`. A renderização dos tokens próprios ainda não foi testada ao vivo. O que o coordenador publica está em [acompanhamento](acompanhamento.md#status-na-sidebar).

## Identidade no GitLab

Cada papel pode ter um usuário próprio no GitLab, para que MR, comentários de evidência, achados e respostas mostrem quem é executor e quem é revisor. `[identidades.<papel>]` aponta `glab_config_dir` para um diretório com o `config.yml` do `glab` daquele usuário; o pane do worker recebe `GLAB_CONFIG_DIR` com esse caminho absoluto ([despacho](despacho.md#inicialização)). O token vive só nesse `config.yml` (`600`), e o orquestrador passa o caminho, nunca o valor — `GITLAB_TOKEN` no `--env` deixaria o segredo no comando, no transcript e no estado do Herdr.

A identidade cobre o `glab`. Commit e push continuam com o `git` do usuário: autor e evento de push são dele. Papel sem entrada, como planejamento, usa o `glab` do usuário.

## Cadastro de projetos e ambiente

Cada projeto registra caminho, board Taiga, branch base, instruções de entrega e referência da identidade ai-memory. O board tem `taiga_project_id` e `taiga_slug`: a CLI `taiga` recebe o slug (`--project <slug>`), e o slug é o projeto das US na [Central](central.md), que o daemon repassa à `taiga`. Sem `taiga_slug`, leia-o do Taiga pelo id e peça ao usuário para gravá-lo na configuração; não o deduza da chave do projeto, que pode diferir. Leia `workspace`/`project` da configuração real; o cadastro não substitui a resolução de `repo-root`. Repositórios GitHub/main não herdam automaticamente comandos GitLab/develop: explicite adaptações autorizadas do projeto.

Antes do despacho confira CLI, autenticação, papel de revisão, diretórios graváveis, permissões de limpeza e recursos. Use limites globais de executores/revisores e de builds pesados; teste memória/disco disponíveis. Os números do exemplo são conservadores e precisam ser ajustados ao ambiente.

Diretório de artefatos: `<raiz>/<chave-projeto>/TG-<ref>/<papel>/r<rodada>/`. A chave deve ser única no cadastro, inclusive entre boards e workspaces. Pane recebe rótulo, nome de agente ([nomes dos panes](despacho.md#nomes-dos-panes)) e ID retornado pelo Herdr; ref isolada não identifica uma missão.
