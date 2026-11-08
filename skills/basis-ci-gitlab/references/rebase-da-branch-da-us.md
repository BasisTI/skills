# Trazer a base para a branch da US sem pedir force push

A branch da US fica atrás da base (`develop` no GitLab, `main` no GitHub) quando outra story
mexe nos mesmos arquivos e é mesclada primeiro. O rebase local exige
`git push --force-with-lease`, e o harness pede confirmação a cada um. Há três caminhos, na
ordem em que valem. Os dois primeiros não usam force push; se o harness pede confirmação neles
depende do modo: em modo auto, não; em modo default, depende de o comando estar no `allow`
(`glab` costuma estar, `gh pr update-branch`, `git reset --hard` e `git push` podem não estar).

Validado em 2026-11-08 (orq #50) num repositório local descartável com remoto bare (git
2.53): o que está marcado como **testado** foi executado; o resto é leitura de `--help` ou
de documentação, e diz isso. **Limite declarado:** o rebase no servidor (`glab mr rebase`,
`gh pr update-branch --rebase`) não foi executado contra MR/PR real. Em particular, o
`BasisTI/skills` tem `allow_update_branch:false`, que pode impedir o caminho 1 ali; se falhar,
vá para o 2 ou o 3.

## 1. Sem conflito: rebase no servidor

```sh
glab mr rebase <iid>                 # GitLab (lê `glab mr rebase --help` antes da primeira vez)
gh pr update-branch <n> --rebase     # GitHub; sem --rebase ele faz merge commit
```

O servidor reescreve a branch remota; nenhum force push sai da máquina. Só vale sem
conflito: com conflito o comando falha e a branch fica como estava, então vale o critério acima
entre o 2 e o 3. (Leitura do `--help`; não foi executado, porque exige MR/PR real e o escopo da US
proíbe mexer em projeto alheio.)

Depois, o worktree local fica divergente do remoto. Com a árvore limpa e nenhum commit
local sem push (`git status`, `git log origin/TG-xx..`), alinhe:

```sh
git fetch origin && git reset --hard origin/TG-xx
```

Se houver commit local sem push, não use `reset --hard`: faça `git pull --rebase`.

O SHA muda no servidor, então anote o antigo **antes** do comando (`OLD=$(git rev-parse HEAD)`)
e entregue-o ao revisor. O delta se confirma com `git range-diff origin/<base> $OLD HEAD`,
que dá `=` em cada commit quando o rebase foi limpo.

## 2 ou 3: com conflito (ou sem o servidor), o critério é como a MR será mesclada

- **MR mesclada com squash** (feature → `develop`, `--squash-before-merge`): caminho 2. Sem
  force push, sem autorização no harness.
- **MR mesclada sem squash** (`develop` → `main`, MR de release, PR do GitHub mesclada por
  merge ou rebase): caminho 3, porque o merge da base ficaria no histórico. Confira como o PR
  será mesclado antes de escolher.

Conflito que exige escolher entre dois comportamentos continua sendo decisão da pessoa.

## 2. Merge da base na branch, sem force

```sh
git fetch origin && git merge --no-edit origin/<base> && git push
```

Testado: o push é fast-forward, sem force. Só serve quando a MR/PR é mesclada com **squash**
(`--squash-before-merge`; feature → `develop`): os commits de merge somem no squash. Sem
squash, o histórico fica com merges da base, então não use.

Efeito no revisor, testado:

- `git diff origin/<base>...TG-xx` (três pontos) continua mostrando só o diff da US: o
  merge-base anda junto.
- `git range-diff <base-antiga>..<head-antigo> origin/<base>..<head-novo>` mostra os commits
  da US como `=` (idênticos, SHA igual). Prova que a US não mudou; **não** mostra o que o
  merge trouxe.
- `git diff <head-antigo> <head-novo>` traz junto tudo o que a base recebeu: é ruído, não
  delta.
- O delta de verdade, quando houve conflito, é a resolução dentro do merge commit:
  `git show --remerge-diff <merge>` (git ≥ 2.36) mostra só ela.

## 3. MR sem squash: rebase local com autorização no harness

```sh
git fetch origin && git rebase origin/<base>
git push --force-with-lease origin TG-xx
```

Sempre `--force-with-lease`, nunca `--force`, e com o nome da branch explícito.
Efeito no revisor, testado: `git range-diff <base-antiga>..<head-antigo> origin/<base>..<head-novo>`
mostra cada commit como `=` (rebase limpo) ou `!` com o diff entre as versões (o que o
conflito mudou). É esse o delta que o revisor confirma no SHA novo.

## Em todos os caminhos

O SHA mudou: a aprovação e a pipeline do SHA antigo não valem para o novo; o CI roda de novo
e o revisor confirma o delta no SHA novo.

## Autorizar o caminho 3 no harness

A pessoa aplica; o agente não edita essas configurações. Nenhuma regra abaixo **restringe de
verdade** a branches de US: cada harness casa o comando por texto, e o que segue diz até onde
vai a restrição de cada um. `BasisTI/skills` e `BasisTI/orq` não têm proteção de `main` no
servidor (verificado em 2026-11-08), então a regra local é a única barreira ali; no GitLab da
`colaboradados`, `main` e `develop` têm `allow_force_push:false`.

**Claude Code** — `permissions` em `~/.claude/settings.json` (ou `.claude/settings.json`);
`deny` vence `allow`. Testado (claude-haiku-5-5, modo default, remoto bare local): negados
`TG-50:main`, `TG-50 develop`, `main`, `+TG-50`, `TG-50 --force` e `--all`; `refs/heads/main`
cai em pedir confirmação (não casa com o `allow`); rodam `TG-50` e, **limite**,
`TG-50:feature-x` (refspec para branch não protegida). Em Claude Code, `*:*` é sintaxe inválida
(`:*` no fim é prefixo), por isso não há `deny` genérico de refspec.

```json
{
  "permissions": {
    "allow": ["Bash(git push --force-with-lease origin TG-*)"],
    "deny": [
      "Bash(git push --force-with-lease origin TG-* *)",
      "Bash(git push --force-with-lease origin *main*)",
      "Bash(git push --force-with-lease origin *master*)",
      "Bash(git push --force-with-lease origin *develop*)",
      "Bash(git push --force-with-lease origin *staging*)",
      "Bash(git push --force-with-lease origin +*)",
      "Bash(git push --force *)",
      "Bash(git push -f *)"
    ]
  }
}
```

**Codex** — `~/.codex/rules/*.rules`. Testado com `codex execpolicy check --rules <arquivo> <comando…>`
(codex-cli 0.167.0). A regra casa por prefixo de argumentos, **sem curinga**: não existe
`TG-*`, e um `allow` genérico em `origin` liberaria qualquer destino. Duas saídas:

- manter só os `forbidden` (abaixo, sem o `allow`): barra o descuido com branch protegida e
  `--force`, e o `--force-with-lease` em branch de US segue pedindo confirmação, ou
- um `allow` por branch exata, acrescentado a cada US (`"TG-50"` abaixo). É restritivo, mas
  manual. Um helper que valide `^TG-[0-9]+$` também serviria; não foi escrito.

```python
prefix_rule(pattern=["git","push","--force-with-lease","origin","TG-50"], decision="allow", justification="rebase da US 50")
prefix_rule(pattern=["git","push","--force-with-lease","origin",["main","develop","staging","master"]], decision="forbidden", justification="branch protegida")
prefix_rule(pattern=["git","push","--force-with-lease","origin","TG-50",["main","develop","staging","master","--all","--mirror","--force","-f"]], decision="forbidden", justification="argumento extra")
prefix_rule(pattern=["git","push",["--force","-f"]], decision="forbidden", justification="use --force-with-lease")
```

Medido: `origin TG-50` → allow; `origin TG-51` → sem regra; `origin main`, `TG-50 develop` e
`--force` → forbidden. **Limites:** `TG-50:main`, `HEAD:main` e `+TG-50` ficam sem regra (pedem
confirmação, não passam), mas `TG-50 feature-x` (argumento extra com outro nome) é allow.

**OpenCode** — `permission.bash` em `opencode.json`; a última regra que casa vence, então os
`deny` vêm depois do `allow`. **Só as regras de `git push`**: sem `"*"`, o resto do shell
mantém o comportamento atual da configuração. Conferido com `opencode debug agents --standalone`
(regras efetivas na ordem escrita); a pergunta em si não foi disparada. Mesmos limites do
Claude Code (`TG-50:feature-x` passa).

```json
{
  "permission": {
    "bash": {
      "git push --force-with-lease origin TG-*": "allow",
      "git push --force-with-lease origin TG-* *": "deny",
      "git push --force-with-lease origin *main*": "deny",
      "git push --force-with-lease origin *master*": "deny",
      "git push --force-with-lease origin *develop*": "deny",
      "git push --force-with-lease origin *staging*": "deny",
      "git push --force-with-lease origin +*": "deny",
      "git push --force *": "deny",
      "git push -f *": "deny"
    }
  }
}
```
