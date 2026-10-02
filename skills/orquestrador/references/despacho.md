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
herdr pane split --current --direction right --cwd <worktree> --no-focus
# aba cheia (panes estreitos demais): aba nova no mesmo workspace
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd <worktree> --label <pane> --no-focus
```

O worktree já existe, criado pelo `wt` no passo anterior; `herdr workspace create` e `herdr worktree create/open` abririam um workspace à parte para cada worker, que é justamente o que este layout evita. Story de projeto diferente do workspace atual: pergunte ao usuário onde abrir.

Obtenha IDs da resposta; associe pane e agente à missão. Passe argumentos nativos por uma lista explícita, sem montar comandos por concatenação de texto externo.

Confirme agente pronto e entrega do prompt. Não reenvie automaticamente depois de timeout. O pacote contém transições autorizadas; registros de status são feitos pelo responsável indicado nele.
