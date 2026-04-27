---
name: basis-k8s-deploy
description: Use when deploying or configuring a Basis application on Kubernetes — kustomize base+overlays layout, ArgoCD with Image Updater, CalVer image tags (YYYY.MM.DD.Seq), Dagger CI on GitLab, operator-managed dependencies (Postgres/RabbitMQ/Minio/MariaDB/Redis) and their secret patterns. Activate for any change under iac/argocd-apps/manifests/, ArgoCD app definitions, CI pipeline questions, or when wiring secrets/env vars from K8s into a Spring app.
---

# Basis Kubernetes Deploy

Padrões da Basis para infra/deploy de aplicações no K8s. Pareada com `basis-spring-app` (esta documenta o lado ops; aquela documenta o lado dev).

## 1. Convenções globais

- **Registry**: `basis-registry.basis.com.br/<app>/<componente>`
- **Tag CalVer**: `YYYY.MM.DD.Seq` — `Seq` é o `CI_PIPELINE_ID` do GitLab (não-contíguo, único globalmente)
- **Namespace**: um por aplicação (ex: `identity-hub`, `licitacao`)
- **Vhost RabbitMQ**: um por aplicação, nome curto (ex: `identityhub`)

## 2. Layout do kustomize

```
manifests/<app>/
├── base/
│   ├── apps/<componente>/   # deployment, service, kustomization, env files
│   ├── rabbitmq/            # vhost, user, filas
│   └── ...
└── overlays/
    ├── staging/
    └── production/
```

- Overlays carregam `images:` (tag CalVer), `replicas:`, `secretGenerator behavior: replace`
- **Generators de env vars**: SEMPRE `envs:`, NUNCA `files:` (gotcha: `files:` cria 1 chave com nome inválido como env var, `envFrom` ignora silenciosamente)

## 3. ArgoCD + Image Updater

- App-of-apps no repo `iac/argocd-apps`
- Image Updater anota a Application com regex CalVer e write-back via Git commit (atualiza `overlays/<env>/kustomization.yaml`)
- O write-back sai como commit no repo de manifests, ArgoCD detecta e sincroniza

## 4. Operadores

Usamos um operador por dependência. Cada app roda sua própria instância (postgres, minio, mariadb, redis) — exceção: RabbitMQ é cluster compartilhado, isolamento por vhost.

| Operador | Dependência | Padrão de secret |
|----------|-------------|------------------|
| Zalando | PostgreSQL | `<user>.<cluster>.credentials.postgresql.acid.zalan.do` (chaves: `username`, `password`) — gerenciado pelo operador, referenciar direto |
| RabbitMQ | RabbitmqCluster + Topology | `<app>-rabbitmq` (chaves: `username`, `password`) — criado por nós via `secretGenerator.literals` |
| Minio | Bucket por aplicação | gerenciado pelo operador |
| MariaDB | DB por aplicação | gerenciado pelo operador |
| ot-container-kit | Redis cluster | gerenciado pelo operador |

Princípio: o **nome** do secret é estável entre ambientes (definido em `base/`), só o **valor** muda (overlay com `behavior: replace`).

## 5. Topology RabbitMQ via CRDs

Quando a app gerencia a topologia via K8s (não via SCS auto-bind):

- Exchange `<app>.<flow>` (topic), Queue `<app>.<flow>.<group>`, Binding com `routingKey: "#"`
- DLX único `DLX` (topic) compartilhado entre flows da app
- DLQ `<queue>.dlq`, binding com `routingKey: <destination>` (combina com `x-dead-letter-routing-key` do main queue)
- Main queue: `arguments.x-dead-letter-exchange: DLX` + `x-dead-letter-routing-key: <destination>`

Espelha o que o SCS faria com `auto-bind-dlq` no default — mas com K8s como source of truth.

## 6. CI: Dagger em Go no GitLab

- Pipelines em Go com Daggerverse modules: `maven` (Java), `uv` (Python), `npm` (Angular)
- Calcula CalVer no Dagger (`YYYY.MM.DD.${CI_PIPELINE_ID}`)
- Build → push imagem (Jib) → bump pom version → commit (acionado pelo Image Updater write-back)
- Gotcha: `BumpAndCommitVersions` não funciona em multi-módulo Maven (filhos herdam versão via `<parent>`); usar `versions:set` direto + `CommitAndPush` separado

## 7. Interface com `basis-spring-app`

Convenção da Basis: prefixo das ConfigurationProperties da app é sempre `application.*`, não o nome da app.

- Spring relaxed binding: `application.opnsense.base-url` ← `APPLICATION_OPNSENSE_BASE_URL`
- Para infra Spring puro: `spring.datasource.*` ← `SPRING_DATASOURCE_*`, `spring.rabbitmq.*` ← `SPRING_RABBITMQ_*`
- **Não** redeclarar defaults Spring (ex: `port: 5672` em rabbitmq)
- **Não** criar env var customizado se relaxed binding cobre (ex: `RABBITMQ_HOST` → use `SPRING_RABBITMQ_HOST`)

Regra prática para deployment.yaml:
- `envFrom` (ConfigMap/Secret) para o conjunto de chaves `APPLICATION_*` da app
- `env:` explícito quando precisa `secretKeyRef` de operador (ex: postgres credentials)

## References disponíveis

- [`references/rabbitmq-topology-pattern.md`](references/rabbitmq-topology-pattern.md) — Padrão Exchange/Queue/Binding limpos + Policy pra DLX/routing-key/TTL, DLX único compartilhado, migração de args→Policy
- [`references/kustomize-base-example.md`](references/kustomize-base-example.md) — Layout completo de `base/` + overlays, `envs:` em generators, hash suffix vs `disableNameSuffixHash`
- [`references/operator-secret-cheatsheet.md`](references/operator-secret-cheatsheet.md) — Padrão de Secret para Postgres-Zalando, RabbitMQ topology, Minio, MariaDB, Redis-otk, com snippets de `valueFrom`
- [`references/argocd-image-updater.md`](references/argocd-image-updater.md) — Application yaml + anotações Image Updater, regex CalVer, fluxo end-to-end e promote
- [`references/dagger-pipeline-example.md`](references/dagger-pipeline-example.md) — `main.go` comentado, Daggerverse modules, gotchas (multi-módulo Maven, bump-and-commit, OCI labels)

Snippets em `references/` são auto-contidos (cópias, não ponteiros) pra não quebrarem com refactors.
