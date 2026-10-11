# Registro na Central

A Central de US (`orq`, US #3 a #5 do projeto `orq`, 2026-10-11) guarda num SQLite o estado que antes ficava nos tokens de sidebar e na parte estruturada do `missao.md`: ondas, status de cada US, panes, MRs e pendências. O comando e as flags valem pelo `README.md` do `orq` instalado; confira `orq <comando> --help` quando divergir daqui.

## Com ou sem Central

No início da sessão, resolva o binário uma vez: `orq` no PATH (`go install`) ou o do plugin, `$(herdr plugin list --json | jq -r '.result.plugins[] | select(.plugin_id=="orq") | .plugin_root')/bin/orq`. Se `<orq> version` responder, todo registro abaixo vai para a Central. Se não, o registro é o manual: tokens `story`/`fase`/`mrs_prontas` ([sidebar](acompanhamento.md#status-na-sidebar)) e lista estruturada no registro da missão. Não registre nos dois: as fontes divergem, e a sidebar mostra `$story`/`$fase` velhos ao lado de `$orq`. Workers não chamam o `orq`; pacotes e relatórios não mudam.

Com a Central, o `missao.md` guarda só o diário livre: decisões com origem, evidências e links. Ondas, status, MRs e pendências saem de `orq onda ver` e `orq diario`.

## Do fluxo ao comando

| Momento | Comando |
|---|---|
| Início da sessão | `orq coord registrar <chave-projeto> --projeto <taiga_slug>`; confira na saída o pane, que vem de `$HERDR_PANE_ID` e no Codex sem `--no-daemon` é o de outro pane ([Codex](harnesses/codex.md)) |
| Contrato da [onda](ondas.md#o-contrato) fechado; story isolada é onda de uma US | `orq onda criar "<título>" --us 215,216 --ate mr-pronta\|plano\|merge --ordem estrita\|livre [--depende 216:215]` |
| Próxima story a despachar | `orq onda proxima [<id>]` (traz `us`, `bloqueadas` e o limite; o id é obrigatório com mais de uma onda aberta) |
| Planejador aberto | `orq us status <ref> plan --pane <p> --papel planejamento --rodada 1` |
| Executor despachado ou correção r≥2 | `orq us status <ref> exec --pane <p> --papel implementacao --rodada <n>` |
| Revisor despachado | `orq us status <ref> rev --pane <p> --papel revisao --rodada <n>` |
| MR aberta | `orq mr add <ref> <url>` |
| Limite da onda alcançado | `orq us status <ref> done` |
| Aviso `pendência Pn aberta` | `orq pend add <ref> --tipo duvida\|autorizacao\|decisao "<resumo>" --pane <p>` |
| Aviso `pendência Pn respondida` | `orq pend resolver <ref>#P<n> --resposta "<resumo>"` |

`done` quer dizer que a US chegou ao `--ate` da onda: plano aprovado (`plano`), MR aprovada pela revisão independente, à espera da pessoa para o merge (`mr-pronta`) ou MR mesclada (`merge`). Depois de uma onda `plano`, encerre-a (`orq onda encerrar <id>`) e crie a de implementação: a US volta a `wait`, porque o `done` valia para o limite anterior.

**Pendências.** A Central numera sozinha, por US, sem reaproveitar; o worker numera na story a partir do próximo id livre do pacote. Para os dois baterem, o pacote leva o próximo id da Central (`orq onda ver`), e antes de cada `pend add` o coordenador confere que o número seguinte da US é o do aviso. Faltando um anterior, porque o aviso não saiu com o coordenador ocupado, registre-o antes, a partir do pane ou do relatório. Story com pendências de antes da Central entra com elas registradas na ordem, e as respondidas já resolvidas.

## Leitura e exibição

- `orq onda ver [<id>]` e `orq pend list --abertas` para conduzir; `orq snapshot` (JSON, [contrato](https://github.com/BasisTI/orq/blob/main/docs/snapshot.md)) para conferir o estado consolidado com o status Herdr dos panes.
- Para mostrar ao usuário, `orq central abrir --sem-foco` deixa pronto o workspace Central, com um pane por coordenador com onda aberta; ele vê ali ou no popup do plugin, e o foco continua com ele. Não cole tabelas que a tela já mostra.
- Sidebar: o daemon do plugin publica `orq` no pane do coordenador e `orq_mrs` no workspace. O coordenador não publica tokens com a Central ativa e não roda `orq daemon` nem `orq plugin configurar`, que são passos de instalação do usuário.
- O estado da MR no snapshot é cache do daemon (60 s), nulo sem daemon. Ele não substitui o [vigia de merge](acompanhamento.md#vigia-de-merge): o pós-merge continua disparado pela consulta direta ao `glab`/`gh`.
