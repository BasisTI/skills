# Registro na Central

A Central de US (`orq`, US #3 a #5 do projeto `orq`, 2026-10-11) guarda num SQLite o estado que antes ficava nos tokens de sidebar e na parte estruturada do `missao.md`: ondas, status de cada US, panes, MRs e pendências. O comando e as flags valem pelo `README.md` do `orq` instalado; confira `orq <comando> --help` quando divergir daqui.

## Com ou sem Central

No início da sessão, resolva o binário uma vez: `orq` no PATH (`go install`) ou o do plugin, `$(herdr plugin list --json | jq -r '.result.plugins[] | select(.plugin_id=="orq") | .plugin_root')/bin/orq`. A Central está disponível quando o registro do coordenador (primeira linha da tabela abaixo) sai com exit 0: `orq version` não abre o banco e responde mesmo sem ele (revisão r1 da US #6, 2026-10-11). Disponível, todo registro abaixo vai para ela. Se não, o registro é o manual: tokens `story`/`fase`/`mrs_prontas` ([sidebar](acompanhamento.md#status-na-sidebar)) e lista estruturada no registro da missão. Não registre nos dois: as fontes divergem, e a sidebar mostra `$story`/`$fase` velhos ao lado de `$orq`. Workers não chamam o `orq`; pacotes e relatórios não mudam.

A sidebar é outra disponibilidade: quem publica `$orq` é o daemon do plugin, e `orq plugin doctor` diz se ele está no ar, na linha `daemon` (o exit é 0 mesmo com `ERRO`). Sem daemon, a Central registra e a sidebar fica sem `$orq`; diga ao usuário e não publique tokens manuais para compensar.

**Ao passar do manual para a Central**, aposente o que você publicou à mão, porque nem o daemon nem `orq plugin configurar` tocam esses nomes, e a sidebar continua anunciando a story e a MR antigas (na mesma revisão, `w7:p10` mostrava `story=TG-107`/`fase=aguarda merge` e `w7`, `mrs_prontas=!357`). Só os panes e workspaces que o registro da missão diz que você publicou, e só se o valor ainda é o seu (`.tokens` do pane ou do workspace em `herdr api snapshot`): o token é por nome, não por fonte, e outro coordenador pode publicar o mesmo nome.

```bash
herdr pane report-metadata <pane> --source orquestrador --clear-token story --clear-token fase
herdr workspace report-metadata <workspace> --source orquestrador --clear-token mrs_prontas
```

As linhas `$story`/`$fase`/`$mrs_prontas` da configuração do Herdr ficam vazias e não mostram nada; removê-las é escolha do usuário.

**Escrita que falha no meio da missão** (`inesperado` ou `banco_ocupado` depois de o registro do início ter passado; erro de uso, conflito ou não encontrado é do comando, não da Central): não troque para os tokens manuais. Anote no diário do `missao.md` o comando que não entrou, com a hora, e siga; quando a Central voltar, reaplique na ordem e confira com `orq onda ver`. Se o manual for inevitável pelo resto da missão, registre a troca no diário e, ao voltar, aposente os tokens como acima.

Com a Central, o `missao.md` guarda só o diário livre: decisões com origem, evidências e links. Ondas, status, MRs e pendências saem de `orq onda ver` e `orq diario`.

## Do fluxo ao comando

| Momento | Comando |
|---|---|
| Início da sessão | `orq coord registrar <chave-projeto> --projeto <taiga_slug>`; confira na saída o pane, que vem de `$HERDR_PANE_ID` e no Codex sem `--no-daemon` é o de outro pane ([Codex](harnesses/codex.md)) |
| Contrato da [onda](ondas.md#o-contrato) fechado; story isolada é onda de uma US | `orq onda criar "<título>" --us 215,216 --ate mr-pronta\|plano\|merge --ordem estrita\|livre [--depende 216:215]` |
| Próxima story a despachar | `orq onda proxima [<id>]` (traz `us`, `bloqueadas` e o limite, e com a onda no limite o `encerramento`; o id é obrigatório com mais de uma onda aberta) |
| Planejador aberto | `orq us status <ref> plan --pane <p> --papel planejamento --rodada 1` |
| Executor despachado ou correção r≥2 | `orq us status <ref> exec --pane <p> --papel implementacao --rodada <n>` |
| Revisor despachado | `orq us status <ref> rev --pane <p> --papel revisao --rodada <n>` |
| MR aberta | `orq mr add <ref> <url>` |
| Limite da onda alcançado | `orq us status <ref> done` |
| Aviso `pendência Pn aberta` | `orq pend add <ref> --tipo duvida\|autorizacao\|decisao "<resumo>" --pane <p>` |
| Aviso `pendência Pn respondida` | `orq pend resolver <ref>#P<n> --resposta "<resumo>"` |
| Onda concluída ([regra](#encerrar-a-onda)) | `orq onda encerrar <id>` |

`done` quer dizer que a US chegou ao `--ate` da onda: plano aprovado (`plano`), MR aprovada pela revisão independente, à espera da pessoa para o merge (`mr-pronta`) ou MR mesclada (`merge`). Chegar ao limite não encerra a onda: [encerrar a onda](#encerrar-a-onda) é um passo do coordenador.

**Pendências.** A Central numera sozinha, por US, sem reaproveitar; o worker numera na story a partir do próximo id livre do pacote. Para os dois baterem, o pacote leva o próximo id da Central (`orq onda ver`). Antes de cada `pend add` e de cada `pend resolver`, e antes de calcular o próximo id de um pacote, o coordenador confere que a Central tem todas as pendências da US até o número do aviso, do pane ou do relatório. Faltando alguma, porque o aviso de abertura não saiu com o coordenador ocupado, registre-a antes, na ordem, e resolva-a se já foi respondida; sem isso, `pend resolver` dá `nao_encontrado` (exit 5) e o pacote seguinte reusa o id. Story com pendências de antes da Central entra com elas registradas na ordem, e as respondidas já resolvidas.

## Encerrar a onda

Encerre a onda com `orq onda encerrar <id>` quando toda US está em `done`, toda MR da onda está mesclada ou fechada e nenhuma pendência está aberta. Numa onda `mr-pronta` isso vem depois do merge humano e do [pós-merge](conclusao-e-limpeza.md#auditoria-proativa) da última US, que o [vigia de merge](acompanhamento.md#vigia-de-merge) dispara. Pendência aberta sem resposta: resolva-a, ou leve-a para outra onda ou para o Taiga e feche-a com `orq pend resolver <id> --resposta "levada para <destino>"`, registrando no diário da missão antes de encerrar. A onda `plano` não espera MR: com os planos aprovados, encerre-a e crie a de implementação, e a US volta a `wait`, porque o `done` valia para o limite anterior.

Com a onda no limite, `orq onda proxima` aplica esta regra em `encerramento`: com `pronta: true`, rode o `comando` sugerido; senão, `faltam` diz o que impede (MR à espera de merge, MR sem estado conhecido no cache do daemon, que você confere na forja como no vigia, ou pendência aberta), com a chave completa (`projeto/312#P2`), que é o id a usar no `pend resolver`: o curto (`TG-312#P2`) vai ao projeto padrão do coordenador. O `orq` só sugere, nunca encerra; o selo `concluída` na faixa da Central marca a mesma situação. Sem o campo (`orq` anterior à US #8 do projeto `orq`), confira as três condições em `orq onda ver`.

Origem: relato do Cedric em 2026-10-14. Seis ondas terminadas seguiam abertas na Central, uma com três pendências abertas, porque esta referência só mandava encerrar a onda `plano`.

## Leitura e exibição

- `orq onda ver [<id>]` e `orq pend list --abertas` para conduzir; `orq snapshot` (JSON, [contrato](https://github.com/BasisTI/orq/blob/main/docs/snapshot.md)) para conferir o estado consolidado com o status Herdr dos panes.
- Para mostrar ao usuário, `orq central abrir --sem-foco` deixa pronto o workspace Central, com um pane por coordenador com onda aberta; ele vê ali ou no popup do plugin, e o foco continua com ele. Não cole tabelas que a tela já mostra.
- Sidebar: o daemon do plugin publica `orq` no pane do coordenador e `orq_mrs` no workspace. O coordenador não publica tokens com a Central ativa, só limpa os seus na migração, e não roda `orq daemon` nem `orq plugin configurar`, que são passos de instalação do usuário.
- O estado da MR no snapshot é cache do daemon (60 s), nulo sem daemon. Ele não substitui o [vigia de merge](acompanhamento.md#vigia-de-merge): o pós-merge continua disparado pela consulta direta ao `glab`/`gh`.
