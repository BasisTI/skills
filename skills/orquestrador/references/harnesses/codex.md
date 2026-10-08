# Codex

Confira `codex --help` e a configuração efetiva. A CLI instalada pode oferecer `--model`, `--config`, `--cd`, `--add-dir`, `--sandbox` e `--ask-for-approval`; passe somente argumentos suportados. Esforço deve usar a chave reconhecida pela instalação, conferida antes do despacho.

## Espera

O Codex não tem tarefa em background que acorde um turno encerrado. Com worker ativo, a espera ([acompanhamento](../acompanhamento.md#worker-ativo-implica-espera-armada)) é um laço dentro do turno: cada volta roda `herdr agent wait <worker> --timeout 60000` (ou uma espera de 45–60 s), confere relatório e estado da MR e dá uma linha de progresso ao usuário. O turno termina quando o worker termina, bloqueia ou mostra anomalia. Foi assim que a reação caiu de horas para 12–49 s na TG-63.

## Diretórios e aprovação

No perfil do coordenador, registre os diretórios necessários para worktrees, metadados Git e artefatos. `--add-dir <diretorio>` acrescenta diretório gravável na execução compatível; não amplia os direitos do processo pai ou da plataforma que o lançou. Confirme `.git` real de worktrees e raízes de escrita antes de tentar remover.

`workspace-write` e aprovação sob demanda permitem solicitar execução fora da caixa quando disponível. `--ask-for-approval never` não concede acesso: pode tornar a operação impossível de escalar. Não use bypass ou `danger-full-access` como receita para limpeza.

## wt remove e temporários

Após verificar elegibilidade, execute `wt remove` com cwd explícito. Se o sandbox recusar, use a aprovação disponível com comando concreto e justificativa. Uma regra por prefixo `wt remove`, quando suportada, cobre várias branches; a aprovação do alcance e a política efetiva precisam ser conferidas. A skill não pode criar uma exceção ao classificador.

Para artefatos, use helper validado restrito ou comandos sobre caminhos enumerados dentro da raiz autorizada. Um prefixo genérico `rm` não limita o diretório de exclusão. Rejeição da revisão automática deve ser reportada com motivo; preserve o resíduo e continue ações independentes.

## Revisão

Codex pode não oferecer `qa-adversarial` como subagente. O arquivo do papel é uma alternativa apenas quando autorizada; registrar origem e modo de uso. Não presumir que uma skill de revisão comum substitui esse contrato.
