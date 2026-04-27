# Operadores: secrets gerenciados — cheatsheet

Cada dependência (Postgres, RabbitMQ, etc.) é provisionada por um Operator. Cada operator usa uma convenção pra o nome do Secret de credenciais. Esta tabela é a "cola" pra referenciar esses secrets corretamente nos `deployment.yaml`.

## Padrão geral

| Operador | Quem cria o Secret | Nome estável entre ambientes? | Onde referenciar |
|----------|--------------------|--------------------------------|-------------------|
| Zalando Postgres | Operator | Sim | `base/` |
| RabbitMQ Topology (User CR) | Topology Operator (consumindo Secret nosso) | Sim (nome do User CR) | `base/` |
| Minio | Operator | Sim | `base/` |
| MariaDB | Operator | Sim | `base/` |
| Redis (otk) | Operator | Sim | `base/` |

Como o NOME é estável, `deployment.yaml` (no `base/`) referencia direto. Apenas o VALOR muda por ambiente — gerenciado por quem provisiona (manualmente em overlay quando aplicável).

## Zalando Postgres

CR do operator: `acid.zalan.do/v1/postgresql`. Nome do cluster: `data-<app>-cluster`. Operator cria um Secret por usuário do cluster.

**Nome do Secret:**
```
<usuario>.<cluster>.credentials.postgresql.acid.zalan.do
```

Exemplo (identity-hub):
```
identityhub.identityhub-owner-user.data-identity-hub-cluster.credentials.postgresql.acid.zalan.do
```

> Nota: `<usuario>` e `<cluster>` são valores literais do CR; o nome resultante é longo mas previsível.

**Chaves do Secret:** `username`, `password`.

**Uso no deployment:**
```yaml
- name: SPRING_DATASOURCE_USERNAME
  valueFrom:
    secretKeyRef:
      name: identityhub-identityhub-owner-user.data-identity-hub-cluster.credentials.postgresql.acid.zalan.do
      key: username
- name: SPRING_DATASOURCE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: identityhub-identityhub-owner-user.data-identity-hub-cluster.credentials.postgresql.acid.zalan.do
      key: password
- name: SPRING_DATASOURCE_URL
  value: "jdbc:postgresql://data-<app>-cluster:5432/<app>"
```

URL: o Service do cluster Postgres tem nome `data-<app>-cluster` (mesmo nome do CR), porta 5432.

## RabbitMQ (cluster compartilhado + Topology Operator)

Cluster `RabbitmqCluster` em `rabbitmq` namespace é compartilhado entre apps. Cada app cria seu Vhost + User no realm dele via Topology Operator.

**O Secret é criado por NÓS** (não pelo operator), via `secretGenerator` no overlay:

```yaml
# overlays/<env>/kustomization.yaml
secretGenerator:
  - name: <app>-rabbitmq
    behavior: replace
    literals:
      - username=<app>-<env>
      - password=<senha-real>
    options:
      disableNameSuffixHash: true       # nome estável!
```

**O Topology Operator consome esse Secret** via `User.spec.importCredentialsSecret`:

```yaml
# base/rabbitmq/rabbitmq-user.yaml
apiVersion: rabbitmq.com/v1beta1
kind: User
metadata:
  name: <app>
  namespace: rabbitmq
spec:
  importCredentialsSecret:
    name: <app>-rabbitmq            # mesmo nome do nosso Secret
    namespace: <app>                # ns onde o Secret vive
  rabbitmqClusterReference:
    name: rabbitmq
    namespace: rabbitmq
```

> Gotcha: o Secret precisa ter chaves `username` e `password` separadas. Se você usar `secretGenerator.files:` pondo um properties inteiro, o Secret terá UMA chave com o nome do arquivo (não-funcional). Use `literals:` ou `envs:`.

**Uso no deployment:**
```yaml
- name: SPRING_RABBITMQ_USERNAME
  valueFrom:
    secretKeyRef:
      name: <app>-rabbitmq
      key: username
- name: SPRING_RABBITMQ_PASSWORD
  valueFrom:
    secretKeyRef:
      name: <app>-rabbitmq
      key: password
- name: SPRING_RABBITMQ_HOST
  value: "rabbitmq.rabbitmq.svc.cluster.local"
- name: SPRING_RABBITMQ_VIRTUAL_HOST
  value: <vhost>
```

## Minio (operator-minio)

Tenant cria buckets e usuário admin. Secret padrão `<tenant>-env-configuration`.

**Chaves:** `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`.

**Uso no deployment** (típico — confirmar via `kubectl describe tenant <name>`):
```yaml
- name: MINIO_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: <tenant>-env-configuration
      key: MINIO_ROOT_USER
- name: MINIO_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: <tenant>-env-configuration
      key: MINIO_ROOT_PASSWORD
- name: MINIO_ENDPOINT
  value: "http://minio.<tenant-ns>.svc.cluster.local:9000"
```

## MariaDB (mariadb-operator)

CR `MariaDB` com `spec.passwordSecretKeyRef` aponta pra Secret. Operator também cria credenciais root e por user (CRDs `User`/`Database`/`Grant`).

**Nome do Secret root**: `<mariadb>-root` (ou definido por `spec.rootPasswordSecretKeyRef`)
**Chaves:** `password`, opcional `username`.

**Uso no deployment** (substitua pelo nome real do user CR):
```yaml
- name: SPRING_DATASOURCE_USERNAME
  valueFrom:
    secretKeyRef:
      name: <user-cr-name>
      key: username
- name: SPRING_DATASOURCE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: <user-cr-name>
      key: password
- name: SPRING_DATASOURCE_URL
  value: "jdbc:mariadb://<mariadb>:3306/<db>"
```

## Redis (ot-container-kit)

CR `RedisCluster` ou `RedisStandalone`. Operator cria Secret se `spec.kubernetesConfig.redisSecret` aponta pra um.

Padrão: criar Secret `<app>-redis-secret` no overlay (literals) e referenciar tanto no CR quanto no deployment.

```yaml
# overlay
secretGenerator:
  - name: <app>-redis-secret
    literals:
      - password=<senha>
    options:
      disableNameSuffixHash: true
```

**Uso no deployment:**
```yaml
- name: SPRING_DATA_REDIS_HOST
  value: "<app>-redis.<app-ns>.svc.cluster.local"
- name: SPRING_DATA_REDIS_PORT
  value: "6379"
- name: SPRING_DATA_REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: <app>-redis-secret
      key: password
```

## Princípio de design

Quando o operator GERENCIA o Secret (Postgres, Minio, MariaDB nativo): só consumimos. Nome do Secret é determinístico — referência fica no `base/`.

Quando NÓS criamos o Secret pra alimentar o operator (RabbitMQ User, Redis password): usar `disableNameSuffixHash: true` pra garantir nome estável; valor vem do overlay com `behavior: replace`.

Em ambos os casos, **`deployment.yaml` no `base/` referencia o Secret pelo nome canônico** — o que muda entre staging e production é só o VALOR.

## Anti-padrões

- **Referenciar Secret com hash suffix** (sem `disableNameSuffixHash: true`) — quebra a cada commit que muda o conteúdo
- **`secretGenerator.files:`** pra Secret consumido por operator — vira 1 chave com filename inválido (ver kustomize-base-example.md)
- **Hardcodar valor de Secret no `base/`** — vaza credencial em diff, mistura ambientes
- **Repetir definição do Secret em cada overlay** — usar `behavior: replace` e só ter o conteúdo diferente
- **Nome do Secret em base diferente do que operator/overlay produz** — silenciosamente broken (deployment monta env var vazio ou pod fica em CreateContainerConfigError)
