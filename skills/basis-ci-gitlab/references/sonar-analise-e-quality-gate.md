# SonarQube: análise, decoração de MR e quality gate

Tudo de Sonar num arquivo só. Os modos de falha aqui têm uma coisa em comum: **quase nenhum
deles falha em vermelho.** A análise não roda, ou roda e não comenta, ou comenta um verde
que não avaliou nada.

## Bootstrap: o projeto precisa existir antes da primeira MR

O `check-quality` só roda em evento de merge request. Consequência: **a primeira análise de
qualquer projeto é sempre uma análise de pull request.**

E o plugin de branch valida a branch base **antes** de o servidor auto-provisionar o
projeto. A análise morre, e o projeto sequer chega a ser criado:

```
[ERROR] No branch exists in Sonarqube with the name main
```

Conceder permissão de provisionamento ao token **não resolve** — a validação acontece antes
de qualquer provisionamento. É ovo e galinha: para a primeira análise funcionar, o projeto
já precisa existir.

Basta que a linha da branch principal exista no banco; não é preciso análise real:

```
POST api/projects/create              project=<nome> name=<nome> mainBranch=main
POST api/alm_settings/set_gitlab_binding  almSetting="Gitlab Basis" project=<nome>
                                          repository=<id-gitlab> monorepo=<true|false>
```

**O script canônico é `basis/iac/ci-templates/scripts/seed-sonar-projects.sh`.** Ele é
mantido pelo time de CI e muta um SonarQube compartilhado — use aquele, não uma cópia.

`monorepo=true` quando vários projetos Sonar apontam para o mesmo repositório GitLab, que é
o caso comum aqui (um projeto Sonar por target com `sonar = true`). `monorepo=false` no 1:1.

### Os dois tipos de token não são intercambiáveis

| Prefixo | Tipo | Fala com |
|---|---|---|
| `sqa_` | token de análise | scanner, e só |
| `squ_` | user token | Web API (`projects/create`, `alm_settings`) |

O `SONAR_TOKEN` da pipeline é `sqa_`. Rodar o seed com ele falha — a Web API não responde a
token de análise. É o erro mais comum ao semear projeto pela primeira vez.

### Sem o binding, o Sonar analisa e nunca comenta

Um projeto criado sem `set_gitlab_binding` roda análise normalmente e não decora MR nenhuma.
Já aconteceu de ficar assim por semanas até alguém reparar que nunca houve comentário.

## Decoração: análise de PR ≠ análise de branch

Sintoma: o quality gate reprovou, o resultado está no servidor, e a MR não tem comentário
nenhum.

Diagnóstico:

```bash
sonar api GET "api/project_pull_requests/list?project=<chave>"
```

Se voltar `{"pullRequests":[]}`, a análise entrou como **branch**, não como PR. Do ponto de
vista do SonarQube não houve pull request nenhuma — e **decoração é função exclusiva de
análise de PR**.

A causa é a ausência de três parâmetros:

```
-Dsonar.pullrequest.key=<iid>
-Dsonar.pullrequest.branch=<branch de origem>
-Dsonar.pullrequest.base=<branch de destino>
```

O template compartilhado já os passa, mapeados de `CI_MERGE_REQUEST_IID`,
`CI_MERGE_REQUEST_SOURCE_BRANCH_NAME` e `CI_MERGE_REQUEST_TARGET_BRANCH_NAME`. Um módulo
Dagger local precisa passar também — os módulos `maven`/`npm`/`uv` já aceitam opções extras,
então é repasse, não mudança de módulo.

## Quality gate `PASSED` que não avaliou nada

**Sem análise anterior, não existe período de *new code*.** A API devolve `period: None`,
nenhuma condição é avaliada, e o gate passa por vacuidade.

Um projeto recém-integrado, com 0% de cobertura e nenhum teste, fica verde na primeira
análise. Confirmar antes de comemorar:

```bash
sonar api GET "api/project_analyses/search?project=<chave>"
```

Uma análise só na lista significa que o verde não tem conteúdo.

**Problema estrutural conhecido, ainda em aberto:** como `check-quality` só roda em evento
de MR, a branch `main` de projetos existentes não recebe análise nova. O período de new code
(`PREVIOUS_VERSION`) ancora em dados cada vez mais velhos. A correção proposta — um job
`sonar-develop` no template — ainda não foi implementada.

## Invocar o scanner: coordenadas, não prefixo

```
[ERROR] No plugin found for prefix 'sonar' in the current project and in the plugin groups
```

O prefixo `sonar` não está nos `pluginGroups` padrão do Maven. `sonar:sonar` só resolve
quando o `pom.xml` já declara o `sonar-maven-plugin` — o que os poms gerados por JHipster
fazem automaticamente.

Por isso passou despercebido em quatro projetos: todos eram JHipster. O primeiro projeto
sem a declaração quebrou. A forma que funciona sempre é por coordenadas completas:

```
org.sonarsource.scanner.maven:sonar-maven-plugin:<versão>:sonar
```

## Reactor: `-f`, não `-pl`

```
[ERROR] Failed to execute goal ...:sonar (default-cli) on project <módulo>:
        Maven session does not declare a top level project
```

O scanner chama `session.getTopLevelProject()`, que procura o projeto cujo diretório é a
raiz de execução do Maven. Com `-pl <módulo>` a partir da raiz do reactor, a raiz de
execução **continua sendo a raiz do reactor** — e o scanner não acha projeto de topo nela.

A correção é executar o módulo como se fosse standalone:

```
-f <módulo>/pom.xml
```

`-pl` seleciona o módulo mas mantém a raiz de execução. Para plugins que dependem do "top
level project", isso não basta. Vale para qualquer plugin com essa dependência, não só o
Sonar.

## Cobertura 0% com os testes passando

Sintoma: Sonar mostra `coverage=0.0` e `uncovered_lines == lines_to_cover` — tudo marcado
como não coberto — apesar de a suíte inteira passar.

No log:

```
jacocoArgLine set to -javaagent:...
[INFO] Skipping JaCoCo execution due to missing execution data file.
```

O agente foi configurado e nenhum `jacoco.exec` foi escrito. Causa, no `pom.xml`:

```xml
<!-- errado -->
<argLine>${jacocoArgLine} ${jvm.test.args}</argLine>
```

`${...}` é interpolado durante o **model-building** do POM, que acontece antes de o
`prepare-agent` rodar e popular a propriedade. O Surefire forka a JVM sem `-javaagent`.

```xml
<!-- certo -->
<argLine>@{jacocoArgLine} ${jvm.test.args}</argLine>
```

`@{...}` é a sintaxe de *late evaluation* do Surefire, resolvida em tempo de execução.

O sintoma engana porque parece problema de integração Sonar↔JaCoCo — e é sintaxe de
propriedade no pom. Nada na cadeia de CI está errado.

## Monte o `.git` na raiz real do repositório

Ao construir um módulo que vive em subdiretório, é tentador montar o subdiretório como raiz
do build e copiar o `.git` para dentro dele. **Isso destrói o blame.**

Reprodução, num repo com `pom.xml` na raiz e `apps/beneficios/pom.xml`:

| Montagem | `git status` | `git blame` do pom do módulo |
|---|---|---|
| `.git` copiado **dentro** do módulo | `D apps/beneficios/pom.xml`, `M pom.xml` | `00000000 (Not Committed Yet)` |
| `.git` na raiz + módulo no path real | correto | `^bda9c24 (autor ...)` |

O git resolve o índice a partir da raiz do worktree. Com o `.git` acompanhando o
subdiretório, o `pom.xml` do módulo passa a casar com a entrada `pom.xml` **da raiz** no
índice — arquivo diferente, conteúdo diferente — e todo o histórico se perde.

O SCM Publisher do Sonar usa blame para detectar código novo. Com blame quebrado, todo o
arquivo vira "novo", e o gate de new code passa a julgar código antigo.

**Regra: `.git` sempre na raiz real, com o módulo no seu path verdadeiro dentro dela.** É o
que `source-path = "."` faz no `pipeline.toml`.

## A análise não roda da sua máquina

`dagger call ... check-quality` apontando para o Sonar interno falha com erro de
certificado, e a causa é DNS — o engine do Dagger não usa o resolvedor da VPN do host. Ver
`dagger-local.md`.

Para tarefas administrativas (criar projeto, binding, consultar API) chame a API direto do
host, que resolve certo. A **análise** só roda no runner.
