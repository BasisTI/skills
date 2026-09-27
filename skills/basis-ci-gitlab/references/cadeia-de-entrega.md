# A cadeia de entrega: da MR à versão em execução

"Staging roda a versão" e "produção roda a versão" são os critérios que movem a story para
`Ready for test` e `Done` (ver [`taiga-mcp.md`](taiga-mcp.md)). Esta página diz como provar
cada um, elo por elo, a partir de fontes verificáveis.

## Por que os commits da branch não provam nada

A MR de feature para `develop` é mergeada com **squash**: com mais de um commit, o GitLab
gera um commit novo, com outro SHA, e os commits da branch `TG-xx` não entram em `develop`.
Procurar o SHA do último commit da branch no histórico de `develop`, ou na imagem, dá "não
encontrado" para uma mudança que foi entregue. (Com um commit só, o `squash_commit_sha` pode
coincidir com o head da branch — mas não conte com isso.) O ponto de partida é o commit que
o merge registrou, lido na API da MR.

## Os cinco elos

Para **cada target** afetado pela mudança — o `ci/pipeline.toml` pode publicar várias
imagens, e cada uma tem a sua cadeia:

1. **Commit do merge.** MR `TG-xx`→`develop` com `state: merged`; o commit é o
   `squash_commit_sha` (ou o `merge_commit_sha`, se não houve squash; se os dois vierem
   `null`, merge fast-forward sem squash, é o `sha` da MR).
2. **Pipeline de `develop` que contém o commit.** Uma pipeline de `develop` com o job
   `publish-develop` que publicou a imagem, cujo SHA tem o commit do elo 1 no histórico.
   Não filtre a pipeline por `status=success`: o timeout de shutdown do engine marca como
   `failed` um job que já publicou (ver "O que engana" no `SKILL.md`), e o elo 5 — o digest —
   é a prova final de qual imagem roda:

   ```sh
   git fetch origin develop
   git merge-base --is-ancestor <squash_sha> <pipeline_sha> && echo contém
   ```

   Com squash e merge commit, o `publish-develop` roda no `merge_commit_sha`, do qual o
   `squash_commit_sha` é pai — o teste de ancestralidade cobre os dois casos. Uma pipeline
   posterior que também contenha o commit serve igualmente: o que importa é a imagem
   carregar a mudança, não ser a primeira a carregá-la.
3. **Tag da imagem.** A CalVer dessa pipeline, `YYYY.MM.DD.<CI_PIPELINE_IID>`. Em produção,
   `production-<calver>` com a mesma CalVer (§7 do `SKILL.md`).
4. **Overlay do ambiente.** O `newTag` do `kustomization.yaml` do overlay em `argocd-apps`,
   escrito pelo Image Updater, é igual à tag do elo 3 — ou a uma posterior que também
   satisfaça o elo 2.
5. **O que está rodando.** A Application no ArgoCD está `Synced` e `Healthy`, **e** o digest
   da imagem dos pods é o digest da tag no registry. `Synced` sozinho diz que o cluster bate
   com o Git, não que o pod novo subiu.

Os elos 4 e 5 são território da `basis-k8s-deploy`
(`references/argocd-image-updater.md` daquela skill): onde fica o overlay, como o Image
Updater escreve, como ler o digest dos pods.

"Staging roda a versão" = os cinco elos fechados no ambiente de staging. "Produção roda a
versão" = os cinco elos fechados em produção, com a tag `production-*`. Elo que não se
consegue ler (API fora, overlay sem acesso, cluster inacessível) não é elo fechado: o
resultado é "não foi possível confirmar", não "sim".

## Receitas dos elos 1 e 2

No diretório do repositório do projeto (o `:id` do `glab api` é resolvido pelo remote):

```bash
glab api "projects/:id/merge_requests/<iid>" | jq '{state, squash_commit_sha, merge_commit_sha}'
glab api "projects/:id/pipelines?ref=develop&per_page=50" | jq '.[] | {id, iid, sha, status}'
glab api "projects/:id/pipelines/<pipeline_id>/jobs" | jq '.[] | select(.name=="publish-develop") | {status, web_url}'
```

Exemplo real, no `ponto`: a MR !75 (`TG-111`) devolveu `squash_commit_sha` `fdc778d0` e
`merge_commit_sha` `0f8fd1b9`; a pipeline de `develop` de `iid` 446 roda no `0f8fd1b9`, com
`publish-develop` `success`, e `git merge-base --is-ancestor fdc778d0 0f8fd1b9` confirma. A
tag esperada termina em `.446`.

*A confirmar no piloto:* o caminho mais curto de CalVer para pipeline. Duas opções: pegar o
sufixo da CalVer (o `CI_PIPELINE_IID`) e filtrar pelo `iid` na listagem acima; ou achar no
registry a tag `sha-<commit>` com o mesmo digest da CalVer. A data da CalVer vem do relógio
do job, então não a use para achar a pipeline — o `iid` é o que identifica.

## O que não é produção

**Tag `production-*` no registry com o overlay ainda na versão anterior não é produção.** O
promote terminou, mas o Image Updater ainda não escreveu, ou escreveu e o ArgoCD não
sincronizou. A story não é `Done` até os elos 4 e 5 fecharem. O mesmo vale para staging: a
CalVer publicada pelo `publish-develop` não move a story para `Ready for test` sozinha.
