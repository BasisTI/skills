# Padrão de Topologia RabbitMQ (Operator)

Padrão Basis para declarar topologia RabbitMQ em K8s via CRDs do Topology Operator.

## Princípio: declaração ≠ comportamento

Argumentos de fila (`x-dead-letter-exchange`, `x-dead-letter-routing-key`, `x-message-ttl`, etc.) são **imutáveis** depois que a fila é criada. Mudar qualquer um exige `delete + recreate`, perdendo mensagens.

**Solução: Policy.** Uma Policy é aplicada no servidor como overlay sobre filas/exchanges que casam com um pattern. Mudar a Policy é mutável e propaga sem recriar fila.

Por isso: **Queue declara só identidade** (nome, durable, autoDelete). **Policy declara comportamento** (DLX, routing, TTL, lazy, max-length, etc.).

Doc oficial: <https://www.rabbitmq.com/kubernetes/operator/using-topology-operator#queues-policies>

## Pattern de fluxo (1 fluxo = 1 main queue)

```
producer → exchange (topic) ─[#]─→ main queue (group=core)
                                        │
                                        │ dead-letter (rk = exchange name)
                                        ▼
                                      DLX (topic, compartilhada)
                                        │
                                        │ binding rk = exchange name
                                        ▼
                                    main queue.dlq
```

## Conjunto mínimo de manifests

### 1. Exchange + Queue + Binding (declaração limpa, sem `arguments`)

```yaml
# filas/onboarding.yaml
apiVersion: rabbitmq.com/v1beta1
kind: Exchange
metadata:
  name: identity-hub-onboarding
spec:
  name: identity-hub.onboarding
  type: topic
  autoDelete: false
  durable: true
  rabbitmqClusterReference:
    name: rabbitmq
    namespace: rabbitmq
  vhost: identityhub
---
apiVersion: rabbitmq.com/v1beta1
kind: Queue
metadata:
  name: identity-hub-onboarding-core
spec:
  name: identity-hub.onboarding.core
  autoDelete: false
  durable: true
  rabbitmqClusterReference:
    name: rabbitmq
    namespace: rabbitmq
  vhost: identityhub
---
apiVersion: rabbitmq.com/v1beta1
kind: Binding
metadata:
  name: identity-hub-onboarding-core-binding
spec:
  source: identity-hub.onboarding
  destination: identity-hub.onboarding.core
  destinationType: queue
  routingKey: "#"
  rabbitmqClusterReference:
    name: rabbitmq
    namespace: rabbitmq
  vhost: identityhub
```

### 2. DLX único + DLQs + bindings (`filas/dlx.yaml`)

```yaml
apiVersion: rabbitmq.com/v1beta1
kind: Exchange
metadata:
  name: dlx
spec:
  name: DLX
  type: topic
  autoDelete: false
  durable: true
  rabbitmqClusterReference:
    name: rabbitmq
    namespace: rabbitmq
  vhost: identityhub
---
apiVersion: rabbitmq.com/v1beta1
kind: Queue
metadata:
  name: identity-hub-onboarding-core-dlq
spec:
  name: identity-hub.onboarding.core.dlq
  autoDelete: false
  durable: true
  rabbitmqClusterReference:
    name: rabbitmq
    namespace: rabbitmq
  vhost: identityhub
---
apiVersion: rabbitmq.com/v1beta1
kind: Binding
metadata:
  name: identity-hub-onboarding-core-dlq-binding
spec:
  source: DLX
  destination: identity-hub.onboarding.core.dlq
  destinationType: queue
  routingKey: identity-hub.onboarding
  rabbitmqClusterReference:
    name: rabbitmq
    namespace: rabbitmq
  vhost: identityhub
# … repete Queue + Binding por flow
```

### 3. Policies (`filas/politicas.yaml`)

Per-queue (DLX + routing-key) — uma por main queue:

```yaml
apiVersion: rabbitmq.com/v1beta1
kind: Policy
metadata:
  name: policy-identity-hub-onboarding-core
spec:
  name: policy-identity-hub-onboarding-core
  pattern: "^identity-hub\\.onboarding\\.core$"
  applyTo: queues
  definition:
    dead-letter-exchange: DLX
    dead-letter-routing-key: identity-hub.onboarding
  priority: 10
  rabbitmqClusterReference:
    name: rabbitmq
    namespace: rabbitmq
  vhost: identityhub
```

Global (TTL nas DLQs) — uma só, pega todas as DLQs do vhost:

```yaml
apiVersion: rabbitmq.com/v1beta1
kind: Policy
metadata:
  name: policy-identity-hub-dlq-ttl
spec:
  name: policy-identity-hub-dlq-ttl
  pattern: "^.*\\.dlq$"
  applyTo: queues
  definition:
    message-ttl: 259200000   # 3 dias em ms — evita acumulo infinito
  priority: 10
  rabbitmqClusterReference:
    name: rabbitmq
    namespace: rabbitmq
  vhost: identityhub
```

## Convenções de nome

| Recurso | Padrão | Exemplo |
|---------|--------|---------|
| Exchange por fluxo | `<app>.<flow>` (topic) | `identity-hub.onboarding` |
| Main queue | `<app>.<flow>.<group>` | `identity-hub.onboarding.core` |
| DLX (única por vhost) | `DLX` (topic) | `DLX` |
| DLQ | `<main-queue>.dlq` | `identity-hub.onboarding.core.dlq` |
| Routing key da DLX→DLQ | `<exchange-do-fluxo>` | `identity-hub.onboarding` |
| Per-queue policy | `policy-<main-queue-com-dashes>` | `policy-identity-hub-onboarding-core` |
| DLQ TTL policy | `policy-<app>-dlq-ttl` | `policy-identity-hub-dlq-ttl` |

## Migração de "args na queue" para Policy

Quando um sistema legado tem `arguments.x-dead-letter-exchange` ou `x-dead-letter-routing-key` direto na Queue:

1. Tirar o bloco `arguments` da Queue YAML
2. Criar Policy equivalente (per-queue, pattern `^<queue-name>$`)
3. **Uma vez**: deletar a fila no RabbitMQ (args imutáveis exigem delete+recreate inicial)
4. Sync ArgoCD: operator recria a Queue limpa, Policy aplica os atributos
5. Daí em diante, mudanças no DLX/routing-key/TTL são só `kubectl apply` da Policy

```bash
# Migração inicial (uma vez)
kubectl -n <app> scale deploy/<app> --replicas=0
RMQ_POD=$(kubectl -n rabbitmq get pod -l app.kubernetes.io/name=rabbitmq -o jsonpath='{.items[0].metadata.name}')
kubectl -n rabbitmq exec "$RMQ_POD" -c rabbitmq -- rabbitmqctl delete_queue --vhost <vhost> <main-queue>
# argocd sync (recria queue limpa + aplica Policy)
kubectl -n <app> scale deploy/<app> --replicas=1
```

## Interação com Spring Cloud Stream

Topologia gerenciada por K8s = SCS NÃO redeclara nada:

```yaml
spring:
  cloud:
    stream:
      rabbit:
        bindings:
          default:
            consumer:
              bind-queue: false      # K8s já fez o binding main-exchange→main-queue
              auto-bind-dlq: false   # K8s já fez DLX, DLQ e binding
```

A app só consome de `<destination>.<group>` que já existe.

Em dev (sem K8s), inverte: `bind-queue: true`, `auto-bind-dlq: true` — SCS cria filas/DLQ automaticamente.

## Anti-padrões

- **`arguments` direto na Queue** → imutável. Use Policy.
- **DLX por fluxo** (`dlx.<flow>` × N) → desnecessário. Uma DLX `DLX` topic compartilhada com routing-keys diferentes resolve.
- **Sem TTL na DLQ** → DLQ acumula indefinidamente. Sempre policy global de TTL (3 dias é razoável).
- **Mistura de SCS auto-bind-dlq + topologia K8s** → SCS tenta redeclarar DLX como `direct`, K8s tem como `topic` → falha de type mismatch no startup.
