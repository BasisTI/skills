# Despacho

## Elegibilidade

Leia story, critérios, plano, dependências, ADRs e estado atual do remoto. Siga o pré-voo da `basis-ci-gitlab`; uma dependência implementada mas não incorporada à branch base ainda pode impedir o início. Registre o grafo e lance trabalhos independentes dentro do limite de recursos.

## Worktree e pacote

Use a referência `worktree.md` da `basis-ci-gitlab` e a skill `worktrunk` para operações de `wt`. Confira branch base do cadastro e instruções do alvo, atualize remoto e reconheça worktree/branch/MR existentes antes de criar. O coordenador prepara o worktree; informe caminho absoluto ao executor. `wt switch` em processo filho não garante mudança do cwd: use cwd explícito para as chamadas seguintes.

Informe cópia e versão das skills usadas. Se desatualizadas, atualize conforme autorização existente; não atualize todas as skills globais automaticamente. Resolva identidade ai-memory e referências de credenciais sem copiar segredos para prompts.

Preencha o template de implementação. Registre conflitos potenciais entre stories paralelas e atualização da branch após o merge das demais. Dependentes liberadas por um merge podem ser despachadas sem nova pergunta dentro da missão autorizada ([ondas](ondas.md)).

### Fatos de ambiente

Um fato de ambiente que decide para onde uma escrita vai entra no pacote somente se foi conferido na fonte de configuração: overlay, manifest ou values. Exemplos: qual banco, instância ou API cada ambiente usa; se staging e produção compartilham o destino. O pacote registra o caminho, o valor e a data da conferência. Comentário de código, relatório de outra story e memória são pistas: confira antes de repassar. Se não for possível conferir, o pacote marca o fato como "não confirmado" e trata o destino como de produção, para que a guarda seja implementada como se a escrita fora de produção alcançasse dados reais.

Origem: no pacote r1 da TG-232 (colaboradados, 2026-10-14), o coordenador escreveu "staging tem outro Secullum", repetindo um docstring da TG-231. Os dois overlays apontavam para o mesmo banco (`SOURCES__SECULLUM_SOURCE__BANCO = "50911"`). O executor deixou a escrita liberável em staging, a revisão r1 abriu um Bloqueante e a correção custou uma rodada.

## Inicialização

Leia o perfil do harness e a skill `herdr`.

O layout é um workspace Herdr por projeto alvo, com um pane do coordenador aberto na pasta do orquestrador. Workers e conversas de planejamento nascem nesse mesmo workspace, o do pane do coordenador (`$HERDR_WORKSPACE_ID`), com o worktree como cwd e sem tirar o foco do usuário:

```bash
herdr pane split --current --direction right --cwd <worktree> --no-focus \
  --env GLAB_CONFIG_DIR=<glab_config_dir do papel>
# aba cheia (panes estreitos demais): aba nova no mesmo workspace
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd <worktree> --label <rótulo> --no-focus \
  --env GLAB_CONFIG_DIR=<glab_config_dir do papel>
```

O `--env` vem de `[identidades.<papel>]` ([configuração](configuracao.md#identidade-no-gitlab)); papel sem identidade abre sem ele. Antes de iniciar o agente, rode `glab api user | jq -r .username` no pane: a identidade está pronta quando responde o usuário do papel. Responder o usuário humano, ou erro de autenticação, é bloqueio de ambiente — reporte em vez de seguir com a identidade errada.

O worktree já existe, criado pelo `wt` no passo anterior; `herdr workspace create` e `herdr worktree create/open` abririam um workspace à parte para cada worker, que é justamente o que este layout evita. Story de projeto diferente do workspace atual: pergunte ao usuário onde abrir.

Dê ao pane o rótulo e ao agente o nome de [nomes dos panes](#nomes-dos-panes). Obtenha IDs da resposta; associe pane e agente à missão. Passe argumentos nativos por uma lista explícita, sem montar comandos por concatenação de texto externo.

Confirme agente pronto e entrega do prompt. Não reenvie automaticamente depois de timeout. O pacote contém transições autorizadas; registros de status são feitos pelo responsável indicado nele. Registre o despacho ([Central](central.md#do-fluxo-ao-comando)) e arme a espera antes de encerrar o turno ([acompanhamento](acompanhamento.md#worker-ativo-implica-espera-armada)).

## Nomes dos panes

Todo pane tem dois nomes. O **rótulo** aceita maiúsculas e só aparece na tela; nenhum comando o recebe como alvo. O **nome de agente** segue `[a-z][a-z0-9_-]{0,31}`, é único entre os agentes vivos, é o alvo de `agent get/prompt/wait` e continua valendo depois de `pane move`, quando o id do pane muda. O id serve de alternativa.

- **Onda:** nome curto e específico, com projeto e assunto: `colaboradados-ferias`, e não `colaboradados`. Tem de ser um nome de agente válido, e o título de `orq onda criar` começa por ele ([Central](central.md#do-fluxo-ao-comando)).
- **Coordenador:** ao fechar o [contrato da onda](ondas.md#o-contrato), rode `herdr pane rename <pane> <onda>` e `herdr agent rename <pane> <onda>`. Com duas ondas abertas vale o nome da mais recente; ao encerrar uma, volta o da que restou. No Codex, o pane é o que `orq coord registrar` mostra, não `$HERDR_PANE_ID` ([Codex](harnesses/codex.md)).
- **Worker:** rótulo `TG-<ref>_<Papel>`, com Papel `Executor`, `Revisor` ou `Planejador` (`TG-281_Executor`), e nome de agente igual ao rótulo em minúsculas (`tg-281_executor`), passado em `herdr agent start <nome> --kind <harness> --pane <pane>`. O rótulo vai em `herdr pane rename` ou, na aba nova, em `herdr tab create --label`. Se o nome já estiver vivo (o mesmo ref em outro board), prefixe a chave do projeto, dentro de 32 caracteres. O planejador de várias stories usa `<onda>_Planejador`. Nas rodadas r≥2, o pane e o nome continuam os mesmos.
- **Pacotes:** o coordenador e o worker aparecem com rótulo, nome de agente e id do pane.

Origem: pedido do Cedric em 2026-10-15. O `herdr agent list` do dia mostrava o coordenador do colaboradados como `colaboradados` e workers como `tg281-exec`, `exec-tg99` e `tg236-rev`, sem dizer onda, story nem papel. Comandos conferidos no Herdr 0.9.3 (`herdr pane rename --help`, `agent rename`, `agent start`, `tab create`); `agent rename` recusa maiúscula com `invalid_agent_name`.

## Aviso ao coordenador

O pacote informa rótulo, nome de agente e id do coordenador. Ao gravar o relatório, o worker roda `herdr agent get <nome-do-coordenador>` (se o nome não resolver, o id) e, **somente se estiver `idle` ou `done`**, envia uma vez, sem reenviar:

```bash
herdr agent prompt <nome-do-coordenador> "[orq] <projeto> TG-xx <papel> r<n> concluída: <caminho do relatório>" --wait --timeout 15000
```

Pendência que depende da pessoa ([bloqueios](acompanhamento.md#bloqueios-e-recorrência)) usa o mesmo comando e a mesma restrição, ao abrir e ao considerá-la respondida:

```
[orq] <projeto> TG-xx pendência P2 aberta: <resumo curto>
[orq] <projeto> TG-xx pendência P2 respondida
```

Coordenador trabalhando não recebe aviso: a espera dele detecta o relatório ou a pendência. Timeout desse comando não prova que o aviso se perdeu. O aviso complementa a espera, não a substitui. Como cada harness trata entrada com o coordenador ocupado ainda não foi testado; por isso o envio fica restrito a `idle`/`done`.

Validado nas TG-225 e TG-312 do convey (2026-10-09/10): os avisos do planejador, do executor e do revisor, de Claude Code e de Codex, chegaram ao coordenador como turno novo. Com o coordenador ocupado, o worker não enviou o aviso e a espera detectou o relatório. Depois de enviar, o worker ainda registra o resultado do envio: o aviso não indica que o pane pode ser fechado ([conclusão](conclusao-e-limpeza.md#artefatos-e-panes)).
