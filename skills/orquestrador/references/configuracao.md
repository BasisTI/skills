# Configuração local do coordenador

## Instalação e precedência

Instale `orquestrador` no escopo de projeto, nunca com `--global`. No coordenador, use a raiz local de skills suportada pelo harness (por exemplo `.agents/skills/` ou `.claude/skills/`). A descoberta deve ser confirmada em cada harness.

Copie o exemplo de `assets/` para `config/orquestrador.toml`. Ajuste caminhos, identidades e modelos antes do primeiro uso. Ignore `config/orquestrador.local.toml` no Git; credenciais ficam fora de ambos e entram por referência.

Precedência: escolha explícita atual do usuário → preferência persistente autorizada → arquivo local → arquivo compartilhado. Mescle tabelas por nome e campos por chave; listas do arquivo local substituem a lista anterior. Registre a resolução. Esta convenção é desta skill, não um recurso do parser TOML.

## Duas tabelas

**Aliases**: cada nome resolve harness, modelo, esforço e perfil de ambiente. O perfil contém capacidades e permissões verificadas, sem prometer que o sandbox as concederá.

**Seleção**: regras associam papel, complexidade e risco a um alias. Use o primeiro seletor compatível, na ordem do arquivo; `*` aceita qualquer valor. Papéis iniciais: planejamento, implementação e revisão. Avalie complexidade por ambiguidade, extensão e dependências; risco por impacto e reversibilidade. Documente a classificação.

Fallback só usa aliases listados e disponíveis. Se nenhum puder cumprir o contrato, reporte bloqueio e peça a escolha que falta. Escalada por ambiguidade ou falhas recorrentes usa a política configurada; não autoriza gasto ou modelo fora das escolhas do usuário.

## Identidade no GitLab

Cada papel pode ter um usuário próprio no GitLab, para que MR, comentários de evidência, achados e respostas mostrem quem é executor e quem é revisor. `[identidades.<papel>]` aponta `glab_config_dir` para um diretório com o `config.yml` do `glab` daquele usuário; o pane do worker recebe `GLAB_CONFIG_DIR` com esse caminho absoluto ([despacho](despacho.md#inicialização)). O token vive só nesse `config.yml` (`600`), e o orquestrador passa o caminho, nunca o valor — `GITLAB_TOKEN` no `--env` deixaria o segredo no comando, no transcript e no estado do Herdr.

A identidade cobre o `glab`. Commit e push continuam com o `git` do usuário: autor e evento de push são dele. Papel sem entrada, como planejamento, usa o `glab` do usuário.

## Cadastro de projetos e ambiente

Cada projeto registra caminho, board Taiga, branch base, instruções de entrega e referência da identidade ai-memory. Leia `workspace`/`project` da configuração real; o cadastro não substitui a resolução de `repo-root`. Repositórios GitHub/main não herdam automaticamente comandos GitLab/develop: explicite adaptações autorizadas do projeto.

Antes do despacho confira CLI, autenticação, papel de revisão, diretórios graváveis, permissões de limpeza e recursos. Use limites globais de executores/revisores e de builds pesados; teste memória/disco disponíveis. Os números do exemplo são conservadores e precisam ser ajustados ao ambiente.

Diretório de artefatos: `<raiz>/<chave-projeto>/TG-<ref>/<papel>/r<rodada>/`. A chave deve ser única no cadastro, inclusive entre boards e workspaces. Pane recebe nome curto único e ID retornado pelo Herdr; ref isolada não identifica uma missão.
