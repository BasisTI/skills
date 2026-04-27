# basis-skills

Agent skills com os padrões de engenharia da [Basis](https://www.basis.com.br) para uso em Claude Code, Cursor, Codex, OpenCode e qualquer agente que consuma o formato `SKILL.md`.

## Skills disponíveis

| Skill | Quando ativar |
|-------|---------------|
| [`basis-k8s-deploy`](skills/basis-k8s-deploy/SKILL.md) | Deploy/infra: kustomize base+overlays, ArgoCD + Image Updater, Dagger CI no GitLab, secrets de operators (Postgres/RabbitMQ/Minio/MariaDB/Redis), tags CalVer. |
| [`basis-spring-app`](skills/basis-spring-app/SKILL.md) | Apps Spring: Java LTS + Maven + Spring Modulith, `application.*` em `@ConfigurationProperties`, Postgres + Flyway, Spring Cloud Stream RabbitMQ, Thymeleaf + HTMX + Tailwind + DaisyUI, Keycloak OIDC, Actuator. |
| [`basis-python-app`](skills/basis-python-app/SKILL.md) | Apps Python: 3.13+ com `uv` obrigatório, ruff, pytest, Dockerfile multi-stage, workspace só com 2+ components. |

## Instalação

Com [skills CLI](https://github.com/vercel-labs/skills):

```bash
# Lista as skills do repo e pergunta qual instalar
npx skills add BasisTI/basis-skills

# Instala uma específica
npx skills add BasisTI/basis-skills --skill basis-spring-app

# Por URL direta
npx skills add https://github.com/BasisTI/basis-skills/tree/main/skills/basis-k8s-deploy
```

Resolve por padrão pra `main`. Pra pinar numa versão estável, use a URL com a tag:

```bash
npx skills add https://github.com/BasisTI/basis-skills/tree/v2026.04.26/skills/basis-spring-app
```

Em projetos que usam Claude Code também é possível clonar o repo e referenciar via plugin/skills locais.

## Versionamento

CalVer (`vYYYY.MM.DD`), alinhado com o resto dos releases da Basis:

- **`main`**: cabeça estável, sempre instalável.
- **Tags `vYYYY.MM.DD`**: snapshot pra pinning. Criadas a cada release com mudança relevante de conteúdo.
- Mudanças menores (correções de redação, links) entram direto em `main` sem tag nova.

## Estrutura de uma skill

```
skills/<nome>/
├── SKILL.md          # frontmatter (name, description) + corpo
└── references/       # snippets, exemplos, deep dives
    └── *.md
```

O `SKILL.md` é o ponto de entrada — descreve quando ativar e link pra referências. As `references/*.md` ficam dentro da pasta da skill, então o install via `npx skills add` leva tudo junto.

## Origem e contribuição

Estas skills foram extraídas do projeto [identity-hub](https://github.com/BasisTI/identity-hub) (`docs/skills/`) durante a consolidação dos padrões de engenharia da Basis. O canônico continua sendo este repo — atualizações entram aqui primeiro e são propagadas pros projetos quando relevante.

Pra propor mudança, abra MR/PR neste repo. Conteúdo deve ser descritivo do padrão Basis atual, não de uma app específica — exemplos genéricos com `<projeto>`, `<app>`, etc.

## Licença

[Apache License 2.0](LICENSE).
