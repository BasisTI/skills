# Despacho

## Elegibilidade

Leia story, critérios, plano, dependências, ADRs e estado atual do remoto. Siga o pré-voo da `basis-ci-gitlab`; uma dependência implementada mas não incorporada à branch base ainda pode impedir o início. Registre o grafo e lance trabalhos independentes dentro do limite de recursos.

## Worktree e pacote

Use a referência `worktree.md` da `basis-ci-gitlab` e a skill `worktrunk` para operações de `wt`. Confira branch base do cadastro e instruções do alvo, atualize remoto e reconheça worktree/branch/MR existentes antes de criar. O coordenador prepara o worktree; informe caminho absoluto ao executor. `wt switch` em processo filho não garante mudança do cwd: use cwd explícito para as chamadas seguintes.

Informe cópia e versão das skills usadas. Se desatualizadas, atualize conforme autorização existente; não atualize todas as skills globais automaticamente. Resolva identidade ai-memory e referências de credenciais sem copiar segredos para prompts.

Preencha o template de implementação. Registre conflitos potenciais entre stories paralelas e atualização da branch após o merge das demais. Dependentes liberadas por um merge podem ser despachadas sem nova pergunta dentro da missão autorizada.

## Inicialização

Leia o perfil do harness e a skill `herdr`.

O layout é um workspace Herdr por projeto alvo, com um pane do coordenador aberto na pasta do orquestrador. Workers e conversas de planejamento nascem nesse mesmo workspace, o do pane do coordenador (`$HERDR_WORKSPACE_ID`), com o worktree como cwd e sem tirar o foco do usuário:

```bash
herdr pane split --current --direction right --cwd <worktree> --no-focus \
  --env GLAB_CONFIG_DIR=<glab_config_dir do papel>
# aba cheia (panes estreitos demais): aba nova no mesmo workspace
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd <worktree> --label <pane> --no-focus \
  --env GLAB_CONFIG_DIR=<glab_config_dir do papel>
```

O `--env` vem de `[identidades.<papel>]` ([configuração](configuracao.md#identidade-no-gitlab)); papel sem identidade abre sem ele. Antes de iniciar o agente, rode `glab api user | jq -r .username` no pane: a identidade está pronta quando responde o usuário do papel. Responder o usuário humano, ou erro de autenticação, é bloqueio de ambiente — reporte em vez de seguir com a identidade errada.

O worktree já existe, criado pelo `wt` no passo anterior; `herdr workspace create` e `herdr worktree create/open` abririam um workspace à parte para cada worker, que é justamente o que este layout evita. Story de projeto diferente do workspace atual: pergunte ao usuário onde abrir.

Obtenha IDs da resposta; associe pane e agente à missão. Passe argumentos nativos por uma lista explícita, sem montar comandos por concatenação de texto externo.

Confirme agente pronto e entrega do prompt. Não reenvie automaticamente depois de timeout. O pacote contém transições autorizadas; registros de status são feitos pelo responsável indicado nele. Arme a espera antes de encerrar o turno ([acompanhamento](acompanhamento.md#worker-ativo-implica-espera-armada)).

## Aviso ao coordenador

O pacote informa nome e pane do coordenador. Ao gravar o relatório, o worker roda `herdr agent get <coordenador>` e, **somente se estiver `idle` ou `done`**, envia uma vez, sem reenviar:

```bash
herdr agent prompt <coordenador> "[orq] <projeto> TG-xx <papel> r<n> concluída: <caminho do relatório>" --wait --timeout 15000
```

Coordenador trabalhando não recebe aviso: a espera dele detecta o relatório. Timeout desse comando não prova que o aviso se perdeu. O aviso complementa a espera, não a substitui. Como cada harness trata entrada com o coordenador ocupado ainda não foi testado; por isso o envio fica restrito a `idle`/`done`.

Validado nas TG-225 e TG-312 do convey (2026-10-09/10): os avisos do planejador, do executor e do revisor, de Claude Code e de Codex, chegaram ao coordenador como turno novo. Com o coordenador ocupado, o worker não enviou o aviso e a espera detectou o relatório. Depois de enviar, o worker ainda registra o resultado do envio: o aviso não indica que o pane pode ser fechado ([conclusão](conclusao-e-limpeza.md#artefatos-e-panes)).
