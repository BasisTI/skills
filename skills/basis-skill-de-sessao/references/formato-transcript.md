# Formato do transcript de sessão

Tudo aqui foi medido nos transcripts da máquina, não suposto. Se o formato mudar de versão
do Claude Code, remeça a medição antes de confiar nesta página.

Medições desta página: 111 sessões, 182 MB, versão `2.1.220` do Claude Code.

## Onde ficam

```
~/.claude/projects/<slug>/<sessionId>.jsonl
```

O `slug` é o caminho absoluto do diretório de trabalho com `/` trocado por `-`. O diretório
`/home/cedric/tmp/incidente-banned-ips-nigeria` vira
`-home-cedric-tmp-incidente-banned-ips-nigeria`.

Uma linha por registro, JSON por linha. Linha malformada acontece; leitor precisa tolerar e
seguir, não abortar.

## Tipos de registro

Contagem de uma sessão real de 166 registros, para dar a proporção:

| Tipo | Qtd | Serve para |
|---|---|---|
| `assistant` | 49 | Texto, raciocínio e chamadas de ferramenta |
| `user` | 29 | **Prompt de pessoa e resultado de ferramenta, misturados** |
| `bridge-session` | 12 | Controle interno, ignorar |
| `attachment` | 12 | Arquivo anexado ao prompt |
| `mode`, `permission-mode` | 22 | Controle interno, ignorar |
| `ai-title` | 11 | Título que o agente deu à sessão |
| `last-prompt` | 11 | Último prompt, para retomada |
| `system` | 8 | Duração de turno e metadados |
| `file-history-*` | 12 | Snapshot de arquivo, ignorar |

## A armadilha do `user` duplo

Registros `type: "user"` são as duas coisas, e a diferença é o que separa sinal de ruído.
Medido em 60 transcripts:

| Forma do `content` | Tem `toolUseResult` | Ocorrências | O que é |
|---|---|---|---|
| lista com `tool_result` | sim | 13.848 | Saída de ferramenta |
| string | não | 1.122 | **Prompt real** |
| lista com `text` | não | 50 | **Prompt real** |
| lista com `image` + `text` | não | 5 | **Prompt real**, com imagem |
| lista com `text` + `tool_result` | sim | 5 | Saída de ferramenta |

**Regra:** prompt real é registro `user` **sem** a chave `toolUseResult`. O formato do
`content` varia e não serve de critério; a chave, sim.

A proporção é o argumento para não ler transcript a olho: cerca de 92% dos registros `user`
são saída de ferramenta.

## A segunda armadilha: maquinaria do cliente

A regra acima é necessária e **não é suficiente**. O Claude Code grava, como registros `user`
sem `toolUseResult`, coisas que a pessoa não digitou:

| Marcador no início do `content` | O que é |
|---|---|
| `<command-name>` / `<command-message>` / `<command-args>` | Eco do slash command |
| `<local-command-caveat>` | Aviso de comando local |
| `<local-command-stdout>` | Saída do comando |
| `<system-reminder>` | Contexto injetado pelo runtime |
| `This session is being continued from a previous conversation` | Sumário de compactação |

O sumário de compactação é o pior dos cinco por dois motivos: traz **centenas de linhas**, o
que numa sessão longa faz o dossiê ficar mais sumário que sessão; e o texto dele descreve
becos sem saída em prosa, o que dispara os regex de negativa e **inventa becos que nunca
existiram**.

Medido numa sessão de planejamento do `ponto`: 12 "prompts" detectados só pela regra do
`toolUseResult`, dos quais **5 eram maquinaria** — dois blocos de `/compact`, o caveat, o
stdout e o sumário inteiro. Sobram 7 reais.

O `extrair-sessao.py` filtra pelos marcadores acima nos primeiros 600 caracteres, mais slash
command puro (`/compact`, `/clear`). Quem for ler transcript a mão precisa fazer o mesmo
descarte.

**Consequência prática:** sessão que passou por `/compact` tem o começo da história só no
sumário. Se o dossiê parecer começar no meio, é isso — vale ler o sumário à parte, como
contexto, sem tratá-lo como fala do relator.

## Estrutura de `assistant`

`message.content` é lista de blocos:

- `text` — o que foi dito ao usuário. É onde costuma estar a conclusão já redigida.
- `thinking` — raciocínio. Contém as hipóteses descartadas, e é volumoso.
- `tool_use` — chamada de ferramenta, com `id`, `name` e `input`.

Para `Bash`, `input` tem `command` e `description`. Para `Write` e `Edit`, tem `file_path`.

## Casar comando com resultado

O bloco `tool_use` tem `id`. O `tool_result` correspondente, no registro `user` seguinte,
traz `tool_use_id` com o mesmo valor. É assim que se descobre se um comando falhou.

No bloco `tool_result`:

- `is_error` — booleano, ausente em alguns casos.

No `toolUseResult` do registro, para Bash:

- `stdout`, `stderr` — saída
- `interrupted` — se foi cortado
- `noOutputExpected`

Saída vazia (`stdout` em branco, sem erro) é o sinal mais interessante e o mais fácil de
perder: costuma ser o momento em que uma hipótese caiu. No incidente do mailcow foi
exatamente assim que a pista mudou de direção.

## Campos de contexto

Nos registros `assistant`, úteis para o cabeçalho do dossiê:

```
cwd         diretório de trabalho
gitBranch   branch no momento
timestamp   ISO 8601 em UTC
version     versão do Claude Code
sessionId   identificador da sessão
```

## Localizar sessão

O registro `ai-title` traz o resumo dado pelo agente — "Analisar incidente de ataque de
força bruta mailcow". É o índice mais barato. O `last-prompt` traz o começo do último
prompt, útil quando a sessão não tem título.
