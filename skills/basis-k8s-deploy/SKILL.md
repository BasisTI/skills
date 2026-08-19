---
name: basis-k8s-deploy
description: >-
  Use when deploying or configuring a Basis application on Kubernetes — kustomize
  base+overlays layout, ArgoCD with Image Updater, CalVer image tags, operator-managed
  dependencies (Postgres/RabbitMQ/Minio/MariaDB/Redis) and their secret patterns. Activate
  for any change under iac/argocd-apps/manifests/, ArgoCD app definitions, or when wiring
  secrets/env vars from K8s into a Spring app. Prefer `basis-ci-gitlab` for anything on the
  GitLab side — pipeline, `ci/pipeline.toml`, Dagger, Sonar, merge requests, branch and
  commit conventions, and how the image gets built and promoted. The boundary is the image
  in the registry carrying its production tag; before that, `basis-ci-gitlab`, from there
  on, this skill.
---

# Basis Kubernetes Deploy

Padrões da Basis para infra/deploy de aplicações no K8s. Pareada com `basis-spring-app` (esta documenta o lado ops; aquela documenta o lado dev).

## 1. Convenções globais

- **Registry**: `basis-registry.basis.com.br/<app>/<componente>`
- **Tag CalVer**: `YYYY.MM.DD.Seq` — `Seq` é o `CI_PIPELINE_IID` do GitLab: contador **por projeto**, contíguo. Não é o `CI_PIPELINE_ID`, que é global da instância. A tag de produção leva o prefixo `production-`
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

## 6. Onde a CI termina e o deploy começa

A fronteira é a **imagem no registry com a tag de produção** (`production-<calver>`). Quem a
coloca lá é o job `promote-production` da pipeline; daí em diante quem age é o Image Updater
(§3).

Tudo do lado GitLab — `ci/pipeline.toml`, o template compartilhado, as funções do
orchestrator Dagger, Sonar, MR, convenção de branch e de commit — está em **`basis-ci-gitlab`**.

Sintoma que atravessa a fronteira e engana: *"a versão nova não subiu em produção"*. Antes de
investigar Application ou sync, confirme que a imagem existe no registry com a tag esperada.
Quase sempre o `promote` não rodou, ou a tag não casa com o `allow-tags` da Application.

## 7. Interface com `basis-spring-app`

Convenção da Basis: prefixo das ConfigurationProperties da app é sempre `application.*`, não o nome da app.

- Spring relaxed binding: `application.opnsense.base-url` ← `APPLICATION_OPNSENSE_BASE_URL`
- Para infra Spring puro: `spring.datasource.*` ← `SPRING_DATASOURCE_*`, `spring.rabbitmq.*` ← `SPRING_RABBITMQ_*`
- **Não** redeclarar defaults Spring (ex: `port: 5672` em rabbitmq)
- **Não** criar env var customizado se relaxed binding cobre (ex: `RABBITMQ_HOST` → use `SPRING_RABBITMQ_HOST`)

Regra prática para deployment.yaml:
- `envFrom` (ConfigMap/Secret) para o conjunto de chaves `APPLICATION_*` da app
- `env:` explícito quando precisa `secretKeyRef` de operador (ex: postgres credentials)

## 8. Ingress e DNS

Duas coisas que o Ingress precisa ter e falham em silêncio quando faltam — e uma terceira
que ele **não** deve ter, porque a plataforma já resolve.

- **`ingressClassName: traefik`.** É a única IngressClass que existe no cluster —
  `kubectl get ingressclass` devolve uma linha só. Não há alternativa a escolher, e qualquer
  outro valor é aceito pela API sem reclamar e nunca é atendido: o `kubectl get ingress`
  mostra o recurso normal, o `ADDRESS` fica vazio e nada roteia. Vale para erro de digitação
  e para replace que concatenou em vez de substituir: a API aceita qualquer string, e o
  sintoma chega como "o app está fora", não como manifesto inválido
- **`create-aws-record: "true"` nas annotations** sempre que o host tiver de resolver de fora.
  É por essa annotation que o **external-dns** cria o registro na zona da AWS. Sem ela o
  Ingress está correto e o nome não resolve — o sintoma chega como "o DNS não propagou", que
  manda investigar o lado errado por um bom tempo
- **Não declare `tls:` nem annotation de cert-manager.** HTTPS é automático e todos os
  sistemas rodam nele. O **cert-manager** emite um certificado curinga do ambiente pelo
  `ClusterIssuer letsencrypt-route53` (desafio DNS-01 na Route53), e um `TLSStore` chamado
  `default` o registra como certificado padrão do Traefik. O controller termina TLS para
  qualquer host servido, sem o Ingress pedir nada:

  ```bash
  kubectl get clusterissuer                                    # letsencrypt-route53
  kubectl get certificate -A | grep default-certificate        # o curinga, READY=True
  kubectl get tlsstore -n kube-system default -o jsonpath='{.spec}'
  ```

  Nada disso mora neste repositório — é plataforma, montada uma vez por cluster. Onde um
  Ingress de aplicação tem `tls:`, foi decisão pontual daquele serviço (certificado próprio,
  host fora do curinga); não é o padrão e não é para copiar

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <app>
  namespace: <app>
  annotations:
    create-aws-record: "true"      # o host precisa resolver de fora
spec:                              # sem bloco tls: — o HTTPS vem do certificado padrão
  ingressClassName: traefik
  rules:
    - host: <app>.basis.com.br     # staging: <app>.stg.basis.com.br
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <app>
                port:
                  name: http
```

**De onde copiar:** `manifests/foundation/overlays/production/apps/editor-bpmn/ingress.yaml`.

Copie o Ingress daí, não do app que você estava usando de modelo para outra coisa.
Referência boa para uma parte do manifesto não é referência boa para o resto dele — foi
assim, herdando o Ingress de um app cujo *deployment* servia de exemplo, que nasceram os
dois erros desta seção.

## References disponíveis

- [`references/rabbitmq-topology-pattern.md`](references/rabbitmq-topology-pattern.md) — Padrão Exchange/Queue/Binding limpos + Policy pra DLX/routing-key/TTL, DLX único compartilhado, migração de args→Policy
- [`references/kustomize-base-example.md`](references/kustomize-base-example.md) — Layout completo de `base/` + overlays, `envs:` em generators, hash suffix vs `disableNameSuffixHash`
- [`references/operator-secret-cheatsheet.md`](references/operator-secret-cheatsheet.md) — Padrão de Secret para Postgres-Zalando, RabbitMQ topology, Minio, MariaDB, Redis-otk, com snippets de `valueFrom`
- [`references/argocd-image-updater.md`](references/argocd-image-updater.md) — Application yaml + anotações Image Updater, regex CalVer, fluxo end-to-end e promote

Snippets em `references/` são auto-contidos (cópias, não ponteiros) pra não quebrarem com refactors.
