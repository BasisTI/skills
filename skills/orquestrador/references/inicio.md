# Início guiado da sessão (`init`)

`/orquestrador init` é a skill chamada com o argumento `init` (no Codex, o pedido pelo nome da skill com "init"). É um comando que a pessoa aciona, não um hook: o menu aparece quando ela pede. Serve para quem não lembra o nome exato do projeto ("liven-painel ou portal-liven?") e quer ver, na ordem, o projeto, o épico e o que está pronto para virar onda. Origem: pedido de 2026-11-14 (orq #54). A padronização dos nomes de ponta a ponta (repositório, board, app no ArgoCD) não faz parte disto.

Tudo aqui é leitura. Nenhuma escrita no Taiga, na Central ou em repositório até a pessoa decidir criar a onda. Quem já abriu a sessão dizendo projeto e objetivo não precisa do menu: use o que ela disse.

## 1. Projeto

Leia `config/orquestrador.toml` e, se existir, `config/orquestrador.local.toml`, pela precedência da [configuração](configuracao.md#instalação-e-precedência). Mostre uma lista numerada dos `[projetos.*]`, uma linha por projeto, com a chave, o `taiga_slug` e a `branch_base`:

```text
 1. orq                 taiga: orq               base: main
 2. portal-liven        taiga: portal-liven      base: develop
```

A escolha vale por número ou por um pedaço do nome. O pedaço é comparado, sem diferenciar maiúscula, com a chave, o `taiga_slug` e o nome da pasta do `caminho`; `liven` acha `portal-liven`. Com mais de um candidato, mostre só os candidatos e peça o número. Sem nenhum, diga e mostre a lista inteira de novo. Não há campo novo de apelido no `.toml`.

Só o projeto escolhido é consultado no Taiga daí em diante, nunca os demais.

## 2. Épico (opcional)

Leia os épicos abertos do board do projeto, com a CLI `taiga` e o `taiga_slug`:

```bash
taiga epic list --project <slug> --closed=false --output json
taiga story list --project <slug> --epic <ref> --closed=false --output json
```

Para cada épico mostre ref, título e `<prontas>/<total>`:

- **total:** as US abertas do épico (`story list --epic`, sem as fechadas);
- **pronta:** a US cujo status é `New` ou `Ready`, pelo nome exato (`Ready for test` não conta), e que não está em onda aberta da Central. As ondas abertas vêm de `orq snapshot` (a US tem `chave` `<slug>/<ref>`; onda com `encerrada_em` nulo).

```text
 #31 Melhorias nos papéis e fluxos — 1/6 prontas
 #36 Publicar e revisar especificações na Central — 6/6 prontas
```

Além dos épicos, ofereça sempre duas saídas:

- **planejar algo novo:** oferece o planejador para criar épico e US, com o papel [`planejador`](../../../agents/planejador.md) ([planejamento](planejamento.md));
- **seguir sem épico:** vai direto à criação da onda (passo 3, "não precisa").

Escolher épico é opcional. Board sem o módulo de Epics (`taiga epic list` falha): diga isso e siga para "planejar algo novo" ou "sem épico". Não ligue o módulo por conta própria: isso muda o board inteiro e exige a permissão que [ondas](ondas.md#épico-da-onda) pede.

## 3. Prontidão

Com o épico escolhido, o coordenador lê as US prontas (`taiga story get <ref> --project <slug>`, mais as pendências da Central no `orq snapshot`) e apresenta, **sem a pessoa pedir**, se cada uma tem informação suficiente para despachar. Os critérios:

1. o resultado esperado está claro;
2. há critérios de aceite;
3. as dependências são identificáveis;
4. não há decisão de produto em aberto, na descrição nem nas pendências da Central.

```text
 US   resultado   situação   o que falta
 #82  pronta      falta      critério de aceite
 #55  pronta      pronta     —
```

- **Alguma precisa de planejamento:** abre o planejamento direto, com o papel `planejador` ([planejamento](planejamento.md)), sem perguntar de novo.
- **Nenhuma precisa:** o planejamento fica como oferta opcional e o fluxo segue para a criação da onda com as US prontas do épico, conforme o contrato de [ondas](ondas.md#o-contrato).

A avaliação é leitura e opinião do coordenador; quem decide é a pessoa. O ponto de encontro com a busca de US similares é a criação da onda, em [ondas](ondas.md).

## 4. Falha de leitura

Taiga fora, Central fora ou comando que falha: diga qual leitura falhou e siga o menu com o que tem. Sem `orq snapshot`, a contagem de prontas não desconta as ondas abertas e o menu avisa isso na linha do épico. Erro de autenticação não se contorna: reporte.
