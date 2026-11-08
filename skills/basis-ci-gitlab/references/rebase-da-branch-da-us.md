# Trazer a base para a branch da US sem pedir force push

A branch da US fica atrás da base (`develop` no GitLab, `main` no GitHub) quando outra story
mexe nos mesmos arquivos e é mesclada primeiro. O rebase local exige
`git push --force-with-lease`, e o harness pede confirmação a cada um. Há três caminhos, na
ordem em que valem. Os dois primeiros não usam force push; se o harness pede confirmação neles
depende do modo: em modo auto passaram nas medições, e o classificador decide caso a caso; em modo default, depende de o comando estar no `allow`
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
conflito: com conflito o comando falha e a branch fica como estava, então vale o critério abaixo
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
- **PR de US no GitHub mesclada sem squash** (por merge ou rebase): caminho 3, porque o merge
  da base ficaria no histórico. Confira como o PR será mesclado antes de escolher.
- **MR `develop` → `main` ou MR de release, em conflito:** nenhum dos dois. Não se reescreve a
  `develop`: o conflito é decisão da pessoa, que escolhe, por exemplo, resolver numa branch
  própria.

Conflito que exige escolher entre dois comportamentos também é decisão da pessoa.

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

## 3. Branch de US sem squash: rebase local com autorização no harness

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

A pessoa aplica; o agente não edita essas configurações. Cada harness casa o comando por
texto, e nenhum restringe de verdade a "branches de US": abaixo está o que foi **medido com
o snippet final somado à configuração real desta máquina** (2026-11-08) e o que é só
leitura. O que vale em outra máquina depende do que ela já tem em `allow`.
`BasisTI/skills` e `BasisTI/orq` não têm proteção de `main` no servidor, então a regra local
é a única barreira ali; no GitLab da `colaboradados`, `main` e `develop` têm
`allow_force_push:false`.

**Claude Code** — `permissions` em `~/.claude/settings.json` (ou `.claude/settings.json`);
`deny` vence `allow`. Medido (claude-haiku-5-5, modo default, remoto bare local, fontes
`user` + `local`; o `settings.json` real desta máquina não tem regra de `git push`):
`TG-50:main` negado; `TG-50` rodou; `release/1.0` e `--all` pedem confirmação (não casam
com o `allow`; em `claude -p` aparecem como negativa). Nas medições anteriores, também
negados `TG-50 develop`, `main`, `+TG-50` e `TG-50 --force`. **Limite:** `TG-50:feature-x`
(refspec para branch não protegida) roda. Em Claude Code, `*:*` é sintaxe inválida (`:*` no
fim é prefixo), por isso não há `deny` genérico de refspec.

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

**Codex** — `~/.codex/rules/*.rules`. Medido com `codex execpolicy check --rules <arquivo>
<comando…>` (codex-cli 0.167.0), com o `default.rules` real desta máquina somado. A regra casa
por prefixo de argumentos, **sem curinga**: não existe `TG-*`. Ponto decisivo: este
`default.rules` tem `prefix_rule(pattern=["git","push"], decision="allow")`. Com um allow
genérico de `git push`, "sem regra" vira **allow** e só os `forbidden` valem: refspec para
branch protegida (`TG-50:main`, `HEAD:main`), `+TG-50` e `release/1.0` **passam**. Quem tem
essa linha só fica protegido contra o que o `forbidden` enumera. **Recomendação à pessoa:**
remover esse allow genérico; sem ele, o que não casa fica sem regra, e o que o Codex faz então
depende de `approval_policy` e do sandbox, e não foi medido. Custo da recomendação: sem o
`allow` genérico, o `git push` comum dos workers em Codex passa a depender do sandbox,
inclusive em worktree, e pode aumentar as confirmações.

```python
prefix_rule(pattern=["git","push","--force-with-lease","origin","TG-50"], decision="allow", justification="rebase da US 50")
prefix_rule(pattern=["git","push","--force-with-lease","origin",["main","develop","staging","master"]], decision="forbidden", justification="branch protegida")
prefix_rule(pattern=["git","push","--force-with-lease","origin","TG-50",["main","develop","staging","master","--all","--mirror","--force","-f"]], decision="forbidden", justification="argumento extra")
prefix_rule(pattern=["git","push",["--force","-f"]], decision="forbidden", justification="use --force-with-lease")
```

O `allow` é por branch exata (`"TG-50"`, um por US); sem ele, só os `forbidden`. Medido:

| comando | só o documento | + `default.rules` real |
|---|---|---|
| `origin TG-50` | allow | allow |
| `origin TG-51` | sem regra | allow |
| `origin main`, `--force`, `TG-50 develop` | forbidden | forbidden |
| `origin TG-50:main`, `HEAD:main`, `+TG-50`, `release/1.0` | sem regra | **allow** |

**OpenCode** — `permission.bash` em `opencode.json`; a última regra que casa vence, então os
`deny` vêm depois do `allow`. **Só as regras de `git push`**, sem `"*"`: o que não casa com
nenhuma regra cai no `allow` padrão do agente (a configuração real desta máquina não tem
bloco `permission`). Um ` *` final é opcional no matcher, então `TG-* *` negaria o próprio
`TG-50`; o `?*` exige algo depois do espaço. Medido numa reimplementação do matcher lido do
binário v2.2.5 (não pelo OpenCode): `TG-50` e `TG-50:feature-x` allow; `TG-50:main`,
`TG-50 develop`, `TG-50 --force`, `TG-50 feature-x`, `--all`, `main` e `+TG-50` deny. **Limite:**
`feature-x`, `release/1.0` e `HEAD:x` caem no `allow` padrão, isto é, rodam sem perguntar.
As regras efetivas foram conferidas com `opencode debug agents --standalone`; a pergunta em si
não foi disparada.

```json
{
  "permission": {
    "bash": {
      "git push --force-with-lease origin TG-*": "allow",
      "git push --force-with-lease origin TG-* ?*": "deny",
      "git push --force-with-lease origin *main*": "deny",
      "git push --force-with-lease origin *master*": "deny",
      "git push --force-with-lease origin *develop*": "deny",
      "git push --force-with-lease origin *staging*": "deny",
      "git push --force-with-lease origin +*": "deny",
      "git push --force-with-lease origin -*": "deny",
      "git push --force *": "deny",
      "git push -f *": "deny"
    }
  }
}
```
