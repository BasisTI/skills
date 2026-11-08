# Trazer a base para a branch da US sem pedir force push

A branch da US fica atrás da base (`develop` no GitLab, `main` no GitHub) quando outra story
mexe nos mesmos arquivos e é mesclada primeiro. O rebase local exige
`git push --force-with-lease`, e o harness pede confirmação a cada um. Há três caminhos, na
ordem em que valem; os dois primeiros não pedem confirmação nenhuma.

Validado em 2026-11-08 (orq #50) num repositório local descartável com remoto bare (git
2.53): o que está marcado como **testado** foi executado; o resto é leitura de `--help` ou
de documentação, e diz isso.

## 1. Sem conflito: rebase no servidor

```sh
glab mr rebase <iid>                 # GitLab (lê `glab mr rebase --help` antes da primeira vez)
gh pr update-branch <n> --rebase     # GitHub; sem --rebase ele faz merge commit
```

O servidor reescreve a branch remota; nenhum force push sai da máquina. Só vale sem
conflito: com conflito o comando falha e a branch fica como estava, então o caminho é o 2 ou
o 3. (Leitura do `--help`; não foi executado, porque exige MR/PR real e o escopo da US
proíbe mexer em projeto alheio.)

Depois, o worktree local fica divergente do remoto. Com a árvore limpa e nenhum commit
local sem push (`git status`, `git log origin/TG-xx..`), alinhe:

```sh
git fetch origin && git reset --hard origin/TG-xx
```

Se houver commit local sem push, não use `reset --hard`: faça `git pull --rebase`.

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

## 3. Conflito, ou base já mesclada sem squash: rebase local com autorização no harness

```sh
git fetch origin && git rebase origin/<base>
git push --force-with-lease origin TG-xx
```

Sempre `--force-with-lease`, nunca `--force`, e com o nome da branch explícito.
Efeito no revisor, testado: `git range-diff <base-antiga>..<head-antigo> origin/<base>..<head-novo>`
mostra cada commit como `=` (rebase limpo) ou `!` com o diff entre as versões (o que o
conflito mudou). É esse o delta que o revisor confirma no SHA novo.

Conflito que exige escolher entre dois comportamentos continua sendo decisão da pessoa.

## Em todos os caminhos

O SHA mudou: a aprovação e a pipeline do SHA antigo não valem para o novo; o CI roda de novo
e o revisor confirma o delta no SHA novo.

## Autorizar só o caminho 3 no harness

A pessoa aplica; o agente não edita essas configurações. A regra libera
`git push --force-with-lease origin TG-…` e nega as branches protegidas (`main`, `develop`,
`staging`) e `--force`/`-f`.

**Claude Code** — `permissions` em `~/.claude/settings.json` (ou `.claude/settings.json`).
`deny` vence `allow`. Leitura da documentação; não testado.

```json
{
  "permissions": {
    "allow": ["Bash(git push --force-with-lease origin TG-*)"],
    "deny": [
      "Bash(git push --force-with-lease origin main*)",
      "Bash(git push --force-with-lease origin develop*)",
      "Bash(git push --force-with-lease origin staging*)",
      "Bash(git push --force *)",
      "Bash(git push -f *)"
    ]
  }
}
```

**Codex** — arquivo `~/.codex/rules/*.rules`. Testado com `codex execpolicy check --rules <arquivo> <comando…>`
(codex-cli 0.167.0). A regra casa por prefixo de argumentos, sem curinga, e o resultado mais
restritivo vence:

```python
prefix_rule(pattern=["git","push","--force-with-lease","origin"], decision="allow", justification="rebase de branch de US")
prefix_rule(pattern=["git","push","--force-with-lease","origin",["main","develop","staging"]], decision="forbidden", justification="branch protegida")
prefix_rule(pattern=["git","push",["--force","-f"]], decision="forbidden", justification="use --force-with-lease")
```

Resultado medido: `origin TG-50` → allow; `origin main` e `origin develop` → forbidden;
`--force` e `-f` → forbidden; `git push origin TG-50` → sem regra. **Limite:** como o prefixo
não tem curinga, `origin HEAD:main` passa como allow. A proteção real das branches
protegidas é a do servidor; a regra só evita o descuido.

**OpenCode** — `permission.bash` em `opencode.json`, padrões com `*`; vale a última regra
que casa, então `"*"` vem primeiro. Leitura da documentação; não testado.

```json
{
  "permission": {
    "bash": {
      "*": "ask",
      "git push --force-with-lease origin TG-*": "allow",
      "git push --force-with-lease origin main*": "deny",
      "git push --force-with-lease origin develop*": "deny",
      "git push --force-with-lease origin staging*": "deny",
      "git push --force *": "deny",
      "git push -f *": "deny"
    }
  }
}
```

Com `"*": "ask"` na frente, tudo o mais segue pedindo confirmação, como hoje. Confira a
precedência na versão instalada antes de depender dela.
