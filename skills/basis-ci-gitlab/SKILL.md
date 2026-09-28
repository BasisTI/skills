---
name: basis-ci-gitlab
description: >-
  Fluxo de uma mudança na Basis, do card do Taiga à imagem em produção: worktree e branch
  `TG-xxx`, status da story, commit, MR até a revisão, `ci/pipeline.toml`, template de CI
  e orchestrator Dagger. Use quando alguém disser "como nomeio a branch", "worktree",
  "trabalhar em paralelo", "retomar a story", "posso marcar squash?", "devolver a MR",
  "revisar a MR", "revisão geral", "a
  story está no status certo?", "minha pipeline falhou", "o Sonar não comentou na MR", "o
  quality gate passou mas não testou nada", "criar o projeto no Sonar", "o promote subiu
  versão velha", "a pipeline da MR aparece skipped", "Project not found or access denied",
  "chave desconhecida no pipeline.toml", "qual ref do ci-templates eu uso", "rodar a
  pipeline na minha máquina", "subir pra produção", "cria a user story", "é só
  configuração". Identidade do projeto vem do `AGENTS.md`; se faltar, pergunte. Prefira à
  `basis-k8s-deploy` quando a pergunta parar na imagem publicada.
---

# CI no GitLab: do card à imagem em produção

**A pipeline não está no `.gitlab-ci.yml`.** Esse arquivo tem de 3 a 8 linhas e só inclui um
template versionado, compartilhado por todos os projetos. A pipeline é o `ci/pipeline.toml`
— o que este projeto tem de próprio — mais um programa Dagger em Go que também roda na sua
máquina. Quem abre o `.gitlab-ci.yml` procurando o build acha um `include` e conclui que o
projeto "não tem CI".

O TOML é desse jeito por um motivo que vale entender antes de mexer nele: **o mapa de
imagens que o `promote` consome é derivado dos mesmos targets do build, não declarado à
parte.** Build e promoção não podem divergir porque a divergência não é representável.

Dois pares não-negociáveis, e errar qualquer um dos dois é caro:

- **`develop` é staging, `main` é produção.**
- **Squash na MR feature→develop. Nunca na develop→main.**

## Quando usar

Alguém diz: *"como nomeio a branch"*, *"posso marcar squash?"*, *"minha pipeline falhou"*,
*"o Sonar não comentou na MR"*, *"o promote subiu versão velha"*, *"a pipeline aparece
skipped e deixou mergear"*, *"quero rodar a pipeline na minha máquina"*, *"subir isso pra
produção"*. Ou vai integrar um projeto novo na CI e pergunta o que precisa existir.

**Esta skill não cobre** manifesto, kustomize, ArgoCD, Image Updater ou operadores — isso é
`basis-k8s-deploy`. A fronteira é a imagem no registry com a tag de produção: até lá, aqui;
dali em diante, lá. A exceção é **ler**: para dizer se uma story está em `Ready for test` ou
`Done`, a auditoria atravessa a fronteira e confere overlay, ArgoCD e digest dos pods, sem
mudar nada ([`references/cadeia-de-entrega.md`](references/cadeia-de-entrega.md)).

## Os três hábitos que resolvem

**1. Abra o `ci/pipeline.toml` antes do `.gitlab-ci.yml`.** O segundo é um `include`; o
primeiro é o projeto. A pergunta "por que esse job não rodou" quase sempre se responde nos
dois juntos, nessa ordem.

**2. Rode a função localmente antes de empurrar commit para ver pipeline.** É a vantagem de
a pipeline ser um programa. Empurrar commit para descobrir se o TOML está válido é o ciclo
mais caro que existe aqui — e `validate` responde em segundos.

**3. Verde não é prova. Pergunte o que a checagem avaliou.** Um quality gate `PASSED` pode
não ter avaliado nada, e um job `failed` pode ter feito o trabalho todo. As duas coisas
acontecem neste ambiente e estão documentadas abaixo.

## 0. O mapa de identidade do projeto

Sete nomes que quase nunca são iguais entre si, e que o agente precisa para agir sem
adivinhar:

| Chave | Exemplo | Onde é usada |
|---|---|---|
| Projeto no GitLab | `basis/ponto` | `glab`, `include:`, MR |
| Id numérico no GitLab | `5371` | chamadas de API, binding do Sonar |
| Projeto no Taiga | `sistema-de-ponto` (id `35`) | branch `TG-xxx`, rastreabilidade |
| Grupo no registry | `ponto` | `[project] group` do TOML |
| Projeto no Sonar | `ponto` | chave permanente da análise |
| Pasta no IaC | `manifests/ponto/` | handoff para `basis-k8s-deploy` |
| Staging | `staging` (no `plataforma-iac`: não há) | critérios de status da story ([`references/taiga-mcp.md`](references/taiga-mcp.md)) |

**Ordem de resolução:** o que veio no prompt → o `AGENTS.md` do repositório → **perguntar**.
Nunca deduzir de um `find`, de um `git remote` ou da semelhança entre nomes. O grupo do
registry e a chave do Sonar coincidirem no exemplo acima é acidente, não regra — no
`colaboradados` a chave do Sonar é `colaboradados-beneficios` e o target se chama
`beneficios`.

Bloco para colar no `AGENTS.md` do repositório:

```markdown
## Identidade do projeto

| Onde       | Valor                    |
|------------|--------------------------|
| GitLab     | basis/<repo> (id <NNNN>) |
| Taiga      | <slug> (id <NN>)         |
| Staging    | <ambiente>, ou "não há"  |
| Registry   | <group>                  |
| Sonar      | <chave>                  |
| ArgoCD app | <app>                    |
| IaC        | manifests/<app>/         |
```

Onde já existe `CLAUDE.md`, ele vira uma linha de ponteiro (`Ver @AGENTS.md`) — o conteúdo
mora num arquivo só, e o formato aberto é lido também por Cursor, Codex e OpenCode.

`$REPO_IAC` é **opcional** e só interessa a quem for cruzar para o repositório de IaC — o
momento de precisar dele já é o handoff para `basis-k8s-deploy`.

## 1. O caminho de uma mudança

```
card no Taiga  →  worktree + branch TG-xxx (de origin/develop)  →  commits  →  MR para develop
    →  check-quality (ciclo até devolver)  →  revisão (qa-adversarial)  →  merge (squash)
        →  publish-develop  →  staging
        →  MR develop→main (sem squash)  →  promote  →  produção
```

**Branch:** criada a partir de `develop`, nomeada `TG-xxx` onde `xxx` é o número da user
story no Taiga. Não é estética: existe integração GitLab↔Taiga, e é o nome que costura o
código ao card.

**Worktree:** um por story, irmão do repositório principal, em `../<repo>.TG-xxx`. É o que
deixa vários agentes trabalharem no mesmo repositório sem um trocar a branch do outro.
Começar é `git fetch origin` e `wt switch --create TG-xxx --base origin/develop`; retomar
uma story com MR aberta é `git fetch origin` e `wt switch TG-xxx`, sem `--create`, na mesma
MR — MR já mergeada não se retoma, a rodada nova é worktree e MR novos. O `wt` não muda o
diretório do shell de um agente: os comandos seguintes rodam no caminho do worktree. Por que
irmão, o que copiar, upstream e remoção em [`references/worktree.md`](references/worktree.md).

**Commit:** verbo no infinitivo, e ` - TG-xxx` no fim.

```
Corrigir configuração de volume no docker-compose - TG-58
```

O teste é completar a frase **"Aplicar esse commit vai…"**. Se não completar, a mensagem
está descrevendo o que você fez, não o que o commit faz — e é a segunda que serve a quem lê
o log depois.

**MR de feature para `develop`:** marque **Delete Branch** e **Squash commits**.

**Até devolver a MR:** a pipeline que conta é o `head_pipeline` da MR, e só quando o SHA dela
é o head da MR e o `check-quality` terminou (nem `skipped`, nem ausente; espere com
`scripts/esperar-pipeline-mr.sh`) — `glab ci status` lê a branch e pode mostrar o
verde de um SHA antigo. Corrigir e empurrar recomeça a checagem. Suspeita de falso positivo
do Sonar é listada para quem revisa, nunca marcada nem suprimida, e a pipeline segue
declarada reprovada. Evidência de cada funcionalidade vai num comentário não resolvível da
MR. O ciclo termina **devolvida** (verde, ou reprovada só por suspeitas) ou **interrompida**
(mesma causa em 3 tentativas, ou impedimento externo), com relatório, e o agente para ali.
Detalhe em [`references/ciclo-da-mr.md`](references/ciclo-da-mr.md).

**Depois de devolver:** outro agente revisa a MR com o `qa-adversarial`, lançado com harness,
modelo e esforço escolhidos como os da implementação — vêm de quem pediu, ou se pergunta.
Achado `Bloqueante` ou `Sério` devolve a story a `In progress` para uma nova rodada na mesma
MR; sem eles, a MR aguarda o merge, que é humano. Detalhe em
[`references/revisao-da-mr.md`](references/revisao-da-mr.md).

**MR de `develop` para `main`:** **não** marque Squash. Esmagar aqui destruiria o histórico
de várias features numa entrada só, e é justamente esse histórico que o `promote` e a
auditoria de produção consultam.

## 2. O Taiga pelo MCP

O servidor MCP `taiga` expõe as ferramentas `mcp__taiga__*`. Serve para o agente **ler a
story antes de nomear a branch e escrever o commit**, em vez de pedir o número a quem já
está com o card aberto.

| Para | Ferramenta |
|---|---|
| Descobrir o id do projeto | `taiga_projects_list` (aceita `search`) |
| Ler a story que vai virar branch | `taiga_stories_get` |
| Listar o que está em aberto | `taiga_stories_list`, `taiga_tasks_list` |
| Criar ou atualizar | `taiga_stories_create`, `taiga_stories_update` |
| Arquivar/fechar, quando solicitado | `taiga_stories_archive_or_close` |
| Conferir a conexão | `taiga_diagnostics` |

**As três ferramentas de `delete` estão em `permissions.deny`.** Os boards são compartilhados
e estão em produção; apagar story ou task alheia é irreversível e invisível para quem
depende dela. A saída correta para "tirar do board" é `archive_or_close`, que é reversível —
foi deixada disponível de propósito.

**Resolva o id pelo `taiga_projects_list`, não por lista mantida à mão.** Índices escritos à
mão envelhecem em silêncio: o que existe hoje na vault omite dois projetos ativos. Se a
skill não estiver configurada com o servidor, pergunte — não tente adivinhar o id a partir
do nome do repositório, porque eles divergem (`triagem.ai` no GitLab é `triagemai` no
Taiga; `contavinculada` é `conta-vinculada`).

**Status: critério para mover e regra para auditar.** Os nomes vêm do board
(`taiga_projects_get` → `us_statuses`), não da memória: o Ponto grafa `In progress` e
`Ready for test`. Cada status tem um critério verificável: `In progress` exige o **registro
de início** (campos customizados, gravados pela API do Taiga enquanto o MCP não os cobre),
não commits; `Ready for test` exige staging rodando a versão; `Done` exige o **registro de
teste** e produção rodando a versão — a cadeia completa até os pods, não a tag no registry.
`In revision` e `Waiting for deployment` são opcionais, e sem eles os critérios caem nos
status existentes. Story com a tag `config` — mudança sem efeito no comportamento da
aplicação, nunca código, nem uma classe `@Configuration` — dispensa o teste em staging e
chega a `Done` com a MR mergeada e a pipeline de `develop` verde. Story com a tag `review`
— revisão com o `qa-adversarial` sobre código já mergeado — não tem MR: o relatório vai num
comentário da story (`Ready for test`), e a triagem humana dos achados a leva a `Done`. Story bloqueada é
desbloqueada por quem a retoma, no começo da rodada, depois de conferir na fonte que a causa
do `blocked_note` se resolveu. Arquivar é só a pedido. A auditoria compara o status com as evidências e
reporta; transição se confirma com quem pediu antes de executar.
Tabelas, regras e autorização em [`references/taiga-mcp.md`](references/taiga-mcp.md); a
cadeia em [`references/cadeia-de-entrega.md`](references/cadeia-de-entrega.md).

## 3. `ci/pipeline.toml` é a fonte de verdade

Um arquivo por repositório, declarativo. Dele saem, ao mesmo tempo, o que buildar, o que
analisar no Sonar e o mapa de imagens de `check-images`/`promote`.

```toml
schema-version = 1

[project]
group = "ponto"                       # vira <registry>/ponto/<image>

[defaults.maven]
image = "maven:3.9.11-eclipse-temurin-25"

[targets.ponto]
type = "maven"                        # obrigatório
path = "."
sonar = true
```

**O parse é estrito.** Chave desconhecida é erro, não aviso — um `sonar-key` no lugar de
`sonar-project-key` derruba a pipeline com mensagem de parse, e isso é deliberado: falhar
alto é melhor que ignorar em silêncio uma configuração que alguém acha que está valendo.

**A regra que explica o desenho:** quando "o que dispara o build" e "o que resolve a versão
publicada" usam listas de caminhos diferentes, há drift — e o drift é silencioso. No
`kaizenstat`, antes da versão declarativa, a lista de imagens era mantida à mão em paralelo
ao mapa de builds, e as duas divergiram: dois serviços estavam na lista de promoção **sem
ter target de build**. Hoje a lista é derivada dos targets, e essa divergência deixou de ser
representável.

O mesmo princípio tem uma segunda face, que já custou uma promoção errada: um target com
`extra-trigger-paths` é reconstruído quando qualquer um dos caminhos muda, então a versão
publicada precisa ser resolvida pelo commit mais recente **entre todos eles** — resolver só
pelo caminho primário promove uma imagem velha, com a pipeline toda verde.

Validar antes de empurrar, **quando a mudança toca o `ci/pipeline.toml`** — é o que o
`validate` avalia:

```bash
dagger call -m github.com/BasisTI/daggerverse/orchestrator@<versão> \
  --source . --config-path ci/pipeline.toml validate
```

A `<versão>` é a que o template em uso chama, não a mais nova: pegue o `ref` do
`.gitlab-ci.yml` e leia o template nesse `ref`.

```bash
REF=$(awk '/ref:/{gsub(/["\x27]/,"",$2); print $2; exit}' .gitlab-ci.yml)
glab api "projects/basis%2Fiac%2Fci-templates/repository/files/templates%2Fdagger-orchestrator.gitlab-ci.yml/raw?ref=$REF" \
  | grep -o 'orchestrator@[^ "]*' | sort -u          # v1.15.1 → orchestrator@3.15.0
```

Schema completo — cada chave, default, e as validações cruzadas — em
[`references/pipeline-toml-schema.md`](references/pipeline-toml-schema.md).

## 4. O `.gitlab-ci.yml` é um include

```yaml
include:
  - project: 'basis/iac/ci-templates'
    ref: <versão>
    file: 'templates/dagger-orchestrator.gitlab-ci.yml'
```

É isso. Projetos com módulo Dagger próprio acrescentam `variables: {DAGGER_MODULE: "."}`, e
é a única exceção em uso.

**Qual job roda quando** — a tabela que responde "por que esse job não rodou":

| Job | Stage | Dispara em |
|---|---|---|
| `validate-pipeline-config` | check | MR que toca `ci/pipeline.toml` |
| `check-quality` | check | MR com destino `develop` |
| `publish-develop` | build | push em `develop` |
| `sonar-branch-develop` | pre-prod | push em `develop`, depois do publish |
| `sonar-branch-full` | check | agendamento com `SONAR_FULL_SCAN=true` |
| `security-check` | check | agendamento com `SECURITY_SCAN=true` |
| `check-images-ready` | pre-prod | MR develop→main **e** push em `main` |
| `promote-production` | promote | push em `main` |

Repare que `check-quality` só roda com destino `develop`. Uma MR de feature aberta
direto para `main` não passa por análise nenhuma.

**Os três últimos a entrar são os dois de branch do Sonar e o de segurança**, e os três só
existem a partir da `v1.12.1`/`v1.14.0`. Projeto pinado abaixo disso não os tem — e a pergunta
"por que esse job não rodou" tem, nesses casos, a resposta mais boba de todas: o `ref`.

**`security-check` é a varredura de dependências, e só roda por agendamento.** O que ela
procura não está no diff — a base de CVE do NVD muda sozinha, então prendê-la a merge request
faz todo MR pagar um scan que quase sempre não revela nada, enquanto a dependência que apodrece
sem ninguém commitar não é vista por MR nenhum. Ela não tem `allow_failure`, ao contrário do
`sonar-branch-full`: lá o vermelho chega depois do deploy e não bloqueia nada; aqui o job **é**
o controle, e a notificação ao dono do agendamento é o que faz a varredura existir.

Sem agendamento o job nunca dispara. Criar com o script do próprio ci-templates:

```bash
scripts/create-security-schedules.sh ~/Projetos/Basis/meu_projeto
```

Semanal na `develop`, com `SECURITY_SCAN=true` — a guarda que impede um agendamento criado
com outra finalidade de disparar a varredura sem querer. O lado Maven é o perfil
`security-check` do pom, em `basis-java-code-standards` §1.1; sem ele o job roda um `verify`
comum e passa sem varrer nada.

**Pin o `ref`, e confira qual está em uso.** Os projetos hoje divergem — há repositórios em
`v1.11.0`, `v1.11.1`, `v1.13.0` e `v1.14.0`. Herdar de `main` faria uma mudança no template
quebrar todos os projetos ao mesmo tempo. Como cada `ref` traz um conjunto diferente de jobs,
confira o do projeto antes de concluir que um job sumiu.

**Todo mundo que abre MR precisa de leitura em `basis/iac/ci-templates`.** O GitLab resolve
`include: project:` com a permissão do **usuário que disparou a pipeline** — não do runner,
não de um token de serviço. Sem acesso, a pipeline nem começa:

```
Project `basis/iac/ci-templates` not found or access denied!
```

A mensagem é deliberadamente ambígua (não revela se o projeto existe), então parece erro de
digitação no caminho. É permissão.

Variáveis que o projeto precisa ter em Settings → CI/CD: `EXTERNAL_REGISTRY_URL`,
`EXTERNAL_REGISTRY_USER`, `EXTERNAL_REGISTRY_PASSWORD`, `SONAR_HOST`, `SONAR_TOKEN`,
`GITLAB_STATUS_TOKEN`. O runner precisa da tag `dagger`.

Opcional, e só para projeto Java que roda o OWASP Dependency-Check: `NVD_API_KEY` (mascarada),
a partir do template `v1.13.0`. Opcional **para o projeto**, não para o job: nos jobs de `mvn
verify` a flag é condicional e quem não define a variável simplesmente não a recebe, mas o
`security-check` falha com `exit 1` e mensagem explícita quando ela falta — varredura de
segurança que não consegue consultar a base não tem por que rodar em silêncio. Projeto sem o
agendamento nunca chega nesse job e nunca precisa da variável.

O plugin em si está em `basis-java-code-standards` §1.1; o que importa **aqui** é por que criar
a variável no GitLab não basta — ver §5.

Template anotado em [`references/template-gitlab-ci.md`](references/template-gitlab-ci.md).

## 5. Rodar a pipeline na sua máquina

A pipeline é um programa, e é por isso que se escolheu Dagger. As sete funções do
orchestrator:

```bash
dagger call -m github.com/BasisTI/daggerverse/orchestrator@<versão> \
  --source . --config-path ci/pipeline.toml <função>
```

`validate` · `sonar-project-keys` · `check-quality` · `security-check` · `publish-all` ·
`check-images` · `promote`

`security-check` entrou no `3.13.0` e é irmã de `check-quality`, sem Sonar e sem detecção de
mudanças: varre **todos** os targets Maven, porque o target parado há meses é o mais provável
de ter apodrecido e o diff o deixaria de fora. A chave do NVD nela é obrigatória, não opcional.

Na prática, `validate` é a que se usa toda hora e a que mais economiza ciclo.

**E o limite, que precisa vir na mesma seção para a promessa não ficar maior que a
entrega:** o engine do Dagger **não usa o resolvedor DNS da VPN do host**. Um hostname
interno resolve, dentro do contêiner, para outra máquina na borda da rede. O sintoma é erro
de certificado:

```
Failed to query server version: ... (certificate_unknown) The certificate chain is not trusted
```

e a causa é DNS. Não troque certificado nem CA — verifique para qual IP o nome resolve
dentro do contêiner versus no host. **Consequência prática:** o que depende de serviço
interno (a análise do Sonar) só roda no runner. `validate` e o build em si rodam local.

**O segundo limite, e o que mais engana: o container do Dagger é hermético.** Variável
definida em Settings → CI/CD existe no shell do job e **não existe dentro do build**. Não há
passthrough de ambiente: o que chega ao container é só o que o orchestrator recebe por flag e
repassa explicitamente. Hoje são quatro segredos — `--sonar-token`, `--gitlab-token`,
`--registry-password` e `--nvd-api-key` —, todos na forma `env:NOME`, que faz o Dagger ler a
variável sem o valor aparecer no log do comando.

O modo de falha é cruel porque a variável **está** lá, certa, mascarada, e o erro fala de
credencial. Assinatura real, com a `NVD_API_KEY` já criada no projeto:

```
[ERROR] Error updating the NVD Data
Caused by: NvdApiException: Invalid API Key, length of 0 too short to provided a masked partial key
```

Zero caracteres — não é chave errada, é chave ausente. Quem lê isso vai conferir a variável no
GitLab, achá-la correta e procurar no lugar errado por um bom tempo.

**Consequência para quem for adicionar ferramenta que precisa de segredo:** não dá para
resolver dentro do repositório do projeto. `extra-options` do `pipeline.toml` até chega ao
Maven, mas o TOML é versionado e segredo não mora lá. O caminho é acrescentar o parâmetro
`*dagger.Secret` no orchestrator, exportá-lo no container do módulo da tecnologia
(`WithSecretVariable`, nunca `WithEnvVariable`), passar a flag no template e subir as duas
tags — `daggerverse` primeiro, porque o template referencia a versão do orchestrator, e
mergear o template antes da tag existir quebra toda pipeline que o use.

Mais em [`references/dagger-local.md`](references/dagger-local.md).

## 6. Qualidade: por que a análise não rodou, não decorou, ou não avaliou nada

**O projeto precisa existir no Sonar antes da primeira MR.** Como `check-quality` só roda em
evento de merge request, a primeira análise de qualquer projeto é sempre uma análise de PR —
e o plugin de branch valida a branch base **antes** de o servidor auto-provisionar o
projeto. A análise morre e o projeto sequer é criado:

```
[ERROR] No branch exists in Sonarqube with the name main
```

Conceder permissão de provisionamento ao token não resolve, porque a validação acontece
antes. O script canônico que semeia projeto e binding é
`basis/iac/ci-templates/scripts/seed-sonar-projects.sh` — rode antes de abrir a MR.

**Sem os três parâmetros de pull request, o Sonar não comenta na MR.** A decoração é função
exclusiva de análise de PR. Sem `sonar.pullrequest.key`/`branch`/`base`, a análise entra
como análise de *branch*, mesmo estando dentro de uma pipeline de merge request — o
resultado aparece no servidor e nunca na MR. O template já passa os três; um módulo Dagger
local precisa passar também.

**Quality gate `PASSED` na primeira análise não prova nada.** Sem análise anterior não
existe período de *new code*, a API devolve `period: None`, nenhuma condição é avaliada e o
gate passa por vacuidade. Um projeto recém-integrado com 0% de cobertura fica verde. Antes
de confiar no primeiro verde, olhe se havia análise anterior.

Bootstrap, tipos de token, cobertura e reactor em
[`references/sonar-analise-e-quality-gate.md`](references/sonar-analise-e-quality-gate.md).

## 7. Promover para produção

MR de `develop` para `main`, **sem squash**. O merge dispara `promote-production`.

As tags, em ordem: `sha-<commit>` durante o build, a CalVer `YYYY.MM.DD.<pipeline_iid>` na
publicação, e `production-<calver>` na promoção. A CalVer é montada em bash no
`before_script`, não dentro do Dagger:

```sh
export APP_VERSION="$(date +%Y.%m.%d).$CI_PIPELINE_IID"
```

É `CI_PIPELINE_IID` — o contador **por projeto** —, não `CI_PIPELINE_ID`, que é global. A
distinção importa para quem raciocina sobre ordenação ou unicidade de tag.

**Por que a pipeline da MR develop→main costuma aparecer `skipped`.** Depois de publicar, o
orchestrator commita o bump de versão e empurra com `git push -o ci.skip`, para não disparar
uma pipeline duplicada. Como `develop` é a origem da MR develop→main já aberta, esse
`ci.skip` suprime **também** a pipeline daquela MR: o head fica sem job nenhum, aparece como
`skipped`, e **não bloqueia o merge**. Não é falha.

É exatamente por isso que `check-images-ready` roda **duas vezes** — na MR (onde
frequentemente é suprimida) e obrigatoriamente no push para `main`. A segunda é a que de
fato garante que as imagens existem antes do promote.

**Daqui em diante é `basis-k8s-deploy`.** A imagem está no registry com a tag de produção; o
Image Updater a detecta e escreve no `kustomization.yaml` do overlay.

## 8. As CLIs e o que cada uma alcança

| CLI | Login | Para |
|---|---|---|
| `glab` | já configurado | MR, pipeline, job, trace, variáveis |
| `argocd` | `argocd login argocd.basis.com.br --sso` (abre browser, Keycloak) | estado e sync de Application |
| `sonar` | `sonar auth login` | analisar arquivo, consultar API |
| `kubectl` | contexto de produção | log do Image Updater |

**`glab ci run` não serve para rodar a pipeline de uma MR.** Ele cria pipeline de *branch*, e
ela nasce vazia — os jobs de check exigem `merge_request_event`. É a armadilha em que se cai
com quase certeza, porque é o comando óbvio. A forma que funciona:

```bash
glab api -X POST "projects/:id/merge_requests/<iid>/pipelines"
```

Log do Image Updater, quando a imagem foi promovida e a versão não subiu:

```bash
kubectl -n argocd logs deploy/argocd-image-updater-controller \
  -l app.kubernetes.io/name=argocd-image-updater --tail=100
```

Receitas verificadas em [`references/glab-argocd-cli.md`](references/glab-argocd-cli.md).

## Assinatura — sintoma e causa

| Observação | Causa |
|---|---|
| `Project ... not found or access denied` no include | Quem abriu a MR não tem leitura em `basis/iac/ci-templates` |
| Erro de parse citando uma chave do TOML | Parse estrito — chave desconhecida, provavelmente nome errado |
| Job esperado não aparece na pipeline | `rules` do job — destino da MR, branch errada, ou `ref` do template antigo demais para ter o job |
| Pipeline da MR develop→main `skipped`, merge liberado | `git push -o ci.skip` do bump de versão suprimiu |
| Quality gate `PASSED` num projeto recém-integrado | Sem análise anterior não há new code — nada foi avaliado |
| Análise roda e o Sonar não comenta na MR | Faltam os três parâmetros de PR — virou análise de branch |
| Cobertura 0% com os testes passando | `${jacocoArgLine}` no `argLine` do surefire; precisa ser `@{jacocoArgLine}` |
| `No plugin found for prefix 'sonar'` | Invocação por prefixo em projeto que não declara o plugin |
| `Maven session does not declare a top level project` | Reactor com `-pl`; o Sonar precisa de `-f <módulo>/pom.xml` |
| `promote` subiu versão velha, pipeline verde | Versão resolvida só pelo caminho primário, ignorando `extra-trigger-paths` |
| `Job failed` no promote com a imagem publicada | Timeout de shutdown do engine **depois** do trabalho pronto |
| Erro de certificado ao chamar serviço interno do `dagger call` local | DNS: o engine não usa o resolvedor da VPN |
| Erro de credencial num build, com a variável criada e correta no GitLab | Container hermético: o segredo só entra por flag `env:NOME` do orchestrator (§5) |
| Target `dockerfile` não encontra o arquivo | O nome é `Dockerfile`, case-sensitive |
| MR "verde" e o Sonar reclama do último push | Pipeline lida por branch ou de SHA antigo; ler `head_pipeline` da MR |
| Auditoria diz `Ready` e alguém está trabalhando | Critério por commits; o início se prova pelo registro, não pelo git |
| Agente parado muito depois de a pipeline da MR terminar | Espera improvisada que nunca casa o SHA; usar `scripts/esperar-pipeline-mr.sh` |
| `production-*` no registry e a story não é `Done` | Overlay/ArgoCD ainda na versão anterior; ver a cadeia de entrega |

## O que engana

**`Error: cleanup failed` / `context deadline exceeded` no fim do job.** Vem do shutdown da
sessão do Dagger, e pode aparecer **depois** de o trabalho ter terminado com sucesso. Leia o
log até o fim antes de concluir que a lógica falhou — reexecutar um `promote` que já
funcionou é seguro (ele é idempotente), mas reexecutar por diagnóstico errado gasta tempo.

**`crane digest ... 404 MANIFEST_UNKNOWN` em vermelho.** É o caminho feliz: a checagem "essa
tag já existe?" que o `promote` faz antes de copiar. 404 significa "ainda não promovida".

**Um `.gitlab-ci.yml` de quatro linhas.** Parece projeto sem CI. É o padrão.

**O primeiro quality gate verde.** Ver §6.

**Uma pipeline `skipped` na MR de produção.** Ver §7.

**O `abaco` como modelo de anotação do Image Updater.** Ele usa `producao-[0-9.]+`, em
português e frouxo; é anterior à convenção atual e o único assim. A convenção viva é
`production-\d{4}\.\d{2}\.\d{2}[-.]\d+`. Copie de um projeto recente.

## Checklist

**Antes de abrir a MR para `develop`:**

- [ ] Worktree próprio da story, criado a partir de `origin/develop` (ou retomado sem `--create`)
- [ ] Branch nomeada `TG-xxx` com o número da story
- [ ] Story pode começar: critérios de aceite presentes e o código de que depende já na `develop`
- [ ] Se a story estava bloqueada: causa conferida na fonte, bloqueio desfeito e branch atualizada a partir de `origin/develop`
- [ ] Registro de início feito na story (campos customizados + `assigned_users`)
- [ ] Mensagens de commit passam no teste "Aplicar esse commit vai…" e terminam em ` - TG-xxx`
- [ ] Se tocou o `ci/pipeline.toml`: `validate` do orchestrator, na versão do template em uso, rodou local e passou
- [ ] Se o projeto é novo no Sonar, foi semeado antes
- [ ] Delete Branch e Squash commits marcados

**Antes de devolver a MR:**

- [ ] `head_pipeline.sha` igual ao head da MR, e `check-quality` executou (não `skipped`)
- [ ] Evidências em comentário não resolvível, um por funcionalidade
- [ ] Suspeitas de falso positivo listadas, não marcadas no Sonar nem suprimidas
- [ ] Relatório completo, com o desfecho

**Antes do merge:**

- [ ] Revisão `qa-adversarial` por outro agente, sobre o SHA atual da MR, com desfecho `aprovada`
- [ ] Discussões dos achados resolvidas pela revisão que confirmou a correção

**Antes de promover para `main`:**

- [ ] Squash **desmarcado**
- [ ] As imagens dos targets alterados existem no registry com a CalVer esperada
- [ ] Se a pipeline da MR está `skipped`, é o `ci.skip` do bump — confira o push em `main`

## Scripts

| Script | Muta? | Uso |
|---|---|---|
| `scripts/estado-pipeline.sh` | Não | Reconcilia projeto, `ref` do template, presença das variáveis, pipeline da branch e da MR, e o trace do primeiro job que falhou |
| `scripts/esperar-pipeline-mr.sh <mr>` | Não | Espera a pipeline do head da MR terminar e diz se serve de aceite (0 aceita, 1 não serve, 3 limite de tempo, 4 verde sem análise). Use-o em vez de montar laço de espera |
| `source scripts/taiga-env.sh <arquivo>` | Não | Carrega a credencial do Taiga de um `compose.yaml` ou `.env` sem imprimir valor |
| `scripts/configurar-taiga-projeto.sh <id>` | Só com `--apply` | Cria no board os status `In revision` e `Waiting for deployment` e os campos customizados dos registros; sem `--apply`, mostra o plano. Exige `admin_project_values` |

## References

- [`references/pipeline-toml-schema.md`](references/pipeline-toml-schema.md) — o schema
  completo e estrito, chave a chave, com os defaults por tipo e as validações cruzadas.
- [`references/template-gitlab-ci.md`](references/template-gitlab-ci.md) — o template
  compartilhado anotado: stages, `rules`, tags, variáveis e a mecânica do `include:`.
- [`references/sonar-analise-e-quality-gate.md`](references/sonar-analise-e-quality-gate.md)
  — bootstrap, tipos de token, análise de PR, cobertura e reactor.
- [`references/dagger-local.md`](references/dagger-local.md) — rodar o orchestrator na
  máquina, o que dá e o que não dá para reproduzir.
- [`references/glab-argocd-cli.md`](references/glab-argocd-cli.md) — receitas verificadas de
  `glab`, `argocd`, `sonar` e `kubectl`.
- [`references/taiga-mcp.md`](references/taiga-mcp.md) — as ferramentas `mcp__taiga__*`, o
  que devolvem, as que estão bloqueadas, e os status: registros, critérios de transição e
  regras de auditoria.
- [`references/worktree.md`](references/worktree.md) — worktree por story: criar, retomar,
  `copy-ignored`, upstream e remoção.
- [`references/cadeia-de-entrega.md`](references/cadeia-de-entrega.md) — os cinco elos do
  commit do merge até os pods, que provam "staging/produção roda a versão".
- [`references/ciclo-da-mr.md`](references/ciclo-da-mr.md) — da abertura à devolução:
  pipeline do head, desfechos, falso positivo, evidências e relatório.
- [`references/revisao-da-mr.md`](references/revisao-da-mr.md) — da devolução ao merge:
  quem lança o `qa-adversarial`, onde vão os achados e os desfechos da revisão.
