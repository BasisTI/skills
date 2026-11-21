# agy (antigravity-cli)

Confira `agy --help`, `agy models` e `agy agents` antes de despachar: a CLI muda entre versões. Os fatos abaixo foram conferidos na `agy` 1.5.13 e no Herdr 0.9.5, que já aceita `herdr agent start --kind agy`. O `agy` pode assumir os papéis de executor, revisor e planejador (planejamento do épico orq #105, 2026-11-20/21). O que só um ensaio mostra está marcado "a confirmar no ensaio (orq #108)" e não se presume.

## Lançamento

Pelo script, que chama `herdr agent start <nome> --kind agy --pane <pane> -- …`:

```bash
scripts/herdr-workers.sh start --kind agy <nome>=<pane> -- --model <id> --mode auto --add-dir <worktree> --add-dir <artefatos>
```

- **Modelo:** só `--model <id>`, com o id completo de `agy models` (ex. `gemini-4-neon-medium`). O esforço já vem no id, então o lançamento **não** passa `--effort` e o alias tem `esforco` vazio ([configuração](../configuracao.md#alias-agy)).
- **Modo:** `--mode auto`. O que ele aprova sozinho e o que ainda pergunta: a confirmar no ensaio (orq #108).
- **Diretórios:** um `--add-dir` para a worktree da US e outro para a pasta de artefatos (relatório, pendências, `TMPDIR`). `--add-dir` é repetível e só acrescenta ao workspace; não amplia os direitos do processo pai.
- **Sem bypass:** nunca `--dangerously-skip-permissions`. Também não use como receita para limpeza. `--sandbox` e `--settings` existem (`--settings` aceita JSON ou arquivo, só para a sessão); use só com autorização e depois de conferir o efeito.
- **Papel:** `--agent <nome>` escolhe o agente da sessão ([papéis](#papéis-como-agentes-nativos)).

O pane precisa estar no prompt do shell, como nos outros harnesses. O nome do agente segue [nomes dos panes](../despacho.md#nomes-dos-panes).

## Retomada

`--conversation <id>` retoma uma conversa pelo id; `-c` (`--continue`) retoma a mais recente. Prefira o id: `-c` pega a mais recente da máquina e pode ser a de outro pane. Onde o id aparece e como o Herdr registra a sessão do `agy`: a confirmar no ensaio (orq #108).

## Espera

A espera do coordenador depende do harness **do coordenador**, não do worker: Claude Code com `espera-onda.sh` em background ([Claude Code](claude-code.md#espera)), Codex com o laço no turno ([Codex](codex.md#espera)). O `espera-onda.sh` lê o estado do worker pelo Herdr, então o `agy` entra como qualquer outro agente. Se o Herdr reporta `working`, `idle` e `done` para o `agy` com o mesmo sentido: a confirmar no ensaio (orq #108). Até lá vale a regra de [anomalias](../acompanhamento.md#anomalias): `done` não comprova entrega, o relatório comprova.

Quando o coordenador for um `agy`: se ele acorda ao fim de um comando em background, a confirmar no ensaio (orq #108); sem isso, use o laço do Codex.

## Limite de uso

Mensagem de limite de uso do `agy`: **a confirmar no ensaio (orq #108)**; nenhum texto está registrado aqui de propósito. Enquanto não houver, o sinal é o geral da [troca por limite](../configuracao.md#troca-por-limite): worker parado, sem relatório, com a mensagem de limite do harness no pane. Nunca decida pela cota do rodapé. Registre o texto exato quando aparecer.

## Papéis como agentes nativos

Os papéis `qa-adversarial` e `planejador` são agentes globais do `agy`, lidos de `~/.gemini/config/agents/<papel>/agent.md`, com cada `agent.md` apontando para `~/.agents/agents/<papel>.md` (que aponta para o clone; veja a seção "Instalação" de [`qa-adversarial`](../../../../agents/qa-adversarial.md#instalação) e [`planejador`](../../../../agents/planejador.md#instalação)). Os links são criados na orq #107.

- Com os links no lugar, `agy agents` precisa listar os dois papéis; o pacote então manda o worker usar `--agent <papel>` (ou o agente nativo, se a sessão já o usa).
- **Reserva (modo arquivo):** se `agy agents` não listar o papel, o pacote entrega o conteúdo do arquivo do papel pelo prompt e registra a adaptação (origem, modo e motivo), com `qa_adversarial_modo = "arquivo"` autorizado no [ambiente](../configuracao.md). Não presuma que uma skill de revisão comum substitui o contrato do papel.
- O frontmatter dos arquivos dos papéis foi escrito para Claude Code e opencode (`mode: subagent`); se o `agy` o rejeita ou ignora campos: a confirmar na orq #107 e no ensaio.

## Fallback

Nesta etapa o `agy` aparece só como alias avulso, escolhido explicitamente. Nenhuma cadeia de `[[selecao]]` o inclui; isso depende do ensaio (orq #108) e é a orq seguinte do épico.
