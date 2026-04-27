# Kustomize: layout base + overlays

Layout padrão Basis pra um app com kustomize. Estrutura permite que tudo o que muda entre ambientes fique nos overlays, e o resto seja compartilhado em `base/`.

## Layout completo

```
manifests/<app>/
├── base/
│   ├── kustomization.yaml          # raiz da base
│   ├── apps/
│   │   ├── core/
│   │   │   ├── kustomization.yaml
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── config-env-vars.properties      # ConfigMap source
│   │   │   └── secret-env-vars.properties      # Secret source (placeholders)
│   │   └── ingress/                # outro componente
│   ├── postgres/                   # CRDs do operator
│   │   ├── kustomization.yaml
│   │   └── postgresql.yaml
│   └── rabbitmq/                   # vhost + user + filas
│       ├── kustomization.yaml
│       ├── vhost.yaml
│       ├── rabbitmq-user.yaml
│       └── filas/
│           ├── kustomization.yaml
│           ├── <flow1>.yaml        # Exchange + Queue + Binding
│           ├── <flow2>.yaml
│           ├── dlx.yaml            # DLX único + DLQs + bindings
│           └── politicas.yaml      # Policies (ver rabbitmq-topology-pattern.md)
└── overlays/
    ├── staging/
    │   ├── kustomization.yaml
    │   └── apps/
    │       ├── core/
    │       │   ├── ingress.yaml                # ingress por ambiente
    │       │   └── secret-env-vars.properties  # valores reais staging
    │       └── ingress/ingress.yaml
    └── production/
        ├── kustomization.yaml
        └── apps/
            ├── core/{ingress.yaml, secret-env-vars.properties}
            └── ingress/ingress.yaml
```

## `base/apps/core/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
configMapGenerator:
  - name: <app>-core-conf
    envs:                            # SEMPRE 'envs', NUNCA 'files' (gotcha)
      - config-env-vars.properties
secretGenerator:
  - name: <app>-core-secret
    envs:
      - secret-env-vars.properties
```

**Gotcha crítico**: `envs:` faz parsing key=value linha-a-linha; `files:` põe o arquivo inteiro como UMA chave (com nome inválido pra env var, contendo dot e dash) — `envFrom` ignora silenciosamente, env vars nunca chegam no container.

## `base/apps/core/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <app>-core
  labels:
    app.kubernetes.io/component: server
    app.kubernetes.io/name: <app>-core
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/component: server
      app.kubernetes.io/name: <app>-core
  template:
    metadata:
      labels:
        app.kubernetes.io/component: server
        app.kubernetes.io/name: <app>-core
    spec:
      containers:
        - name: <app>-core
          image: basis-registry.basis.com.br/<app>/core:latest   # tag substituída por overlay
          imagePullPolicy: Always
          env:
            # Spring profile + valores que vêm de Secrets gerenciados por operadores
            - name: SPRING_PROFILES_ACTIVE
              value: prod
            - name: SPRING_DATASOURCE_URL
              value: "jdbc:postgresql://data-<app>-cluster:5432/<app>"
            - name: SPRING_DATASOURCE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: <app>-<app>-owner-user.data-<app>-cluster.credentials.postgresql.acid.zalan.do
                  key: username
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: <app>-<app>-owner-user.data-<app>-cluster.credentials.postgresql.acid.zalan.do
                  key: password
            - name: SPRING_RABBITMQ_HOST
              value: "rabbitmq.rabbitmq.svc.cluster.local"
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
            - name: SPRING_RABBITMQ_VIRTUAL_HOST
              value: <app>
          envFrom:
            - configMapRef:
                name: <app>-core-conf       # kustomize injeta hash suffix
            - secretRef:
                name: <app>-core-secret
          ports:
            - containerPort: 8080
              name: http
              protocol: TCP
          livenessProbe:
            failureThreshold: 5
            httpGet:
              path: /actuator/health/liveness
              port: http
            initialDelaySeconds: 30
            periodSeconds: 20
          readinessProbe:
            failureThreshold: 3
            httpGet:
              path: /actuator/health/readiness
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
          resources:
            limits:
              cpu: 1000m
              memory: 1Gi
            requests:
              cpu: 250m
              memory: 512Mi
```

## `base/apps/core/secret-env-vars.properties` (placeholder)

Define a SHAPE — quais env vars existem. Os valores reais vêm dos overlays.

```properties
APPLICATION_AD_BIND_DN=REPLACE_IN_OVERLAY
APPLICATION_AD_BIND_PASSWORD=REPLACE_IN_OVERLAY
APPLICATION_MAILCOW_URL=REPLACE_IN_OVERLAY
APPLICATION_MAILCOW_API_KEY=REPLACE_IN_OVERLAY
# ...
```

## `base/apps/core/config-env-vars.properties`

Valores não-sensíveis comuns a todos os ambientes:

```properties
JAVA_TOOL_OPTIONS=-Duser.timezone=America/Sao_Paulo -XX:MaxRAMPercentage=75.0
TZ=America/Sao_Paulo
```

## `overlays/<env>/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: <app>
resources:
  - ../../base
  - apps/core/ingress.yaml
images:
  - name: basis-registry.basis.com.br/<app>/core
    newTag: 2026.04.23.11           # CalVer; Image Updater commita aqui
replicas:
  - count: 1
    name: <app>-core
secretGenerator:
  # Credenciais de operadores que NÓS criamos (não gerenciados pelo operator)
  - name: <app>-rabbitmq
    behavior: replace
    literals:
      - username=<app>-staging
      - password=<senha-real>
    options:
      disableNameSuffixHash: true   # nome estável, referenciável pelo deployment
  # Substitui placeholders do base
  - name: <app>-core-secret
    behavior: replace
    envs:
      - apps/core/secret-env-vars.properties
```

## `overlays/<env>/apps/core/secret-env-vars.properties`

Valores reais do ambiente:

```properties
APPLICATION_AD_BIND_DN=CN=svc-<app>,OU=ServiceAccounts,DC=basis,DC=com,DC=br
APPLICATION_AD_BIND_PASSWORD=<senha-real>
APPLICATION_MAILCOW_URL=https://mail.basisti.com.br
APPLICATION_MAILCOW_API_KEY=<chave-real>
# ...
```

## Validação

```bash
kustomize build manifests/<app>/overlays/staging > /dev/null
kustomize build manifests/<app>/overlays/production > /dev/null
```

Se retorna sem erro, o YAML renderizado é válido em sintaxe. Não valida semântica K8s — pra isso, `kubectl apply --dry-run=server` ou kubeconform.

## Boas práticas

- **`disableNameSuffixHash: true`** em secrets gerenciados por operadores externos (RabbitMQ, postgres-zalando) → nome estável que outros recursos referenciam por nome
- **Hash suffix mantido** em ConfigMap/Secret de env vars do app → mudanças no conteúdo invalidam o hash, kustomize atualiza referência no Deployment, força rollout (env vars novos chegam ao pod)
- **Não usar `replicas: 0`** em base; defina por overlay quando precisar zerar (manutenção, migration)
- **Image em `base` com tag `latest`**; overlay com tag CalVer → Image Updater só mexe no overlay

## Anti-padrões

- `files:` em config/secret generators (ver gotcha acima)
- Hardcoded credentials em base — sempre placeholders, valor real em overlay
- Secret gerenciado pelo operador no `base/` com `disableNameSuffixHash: false` — kustomize muda nome a cada commit, deployment quebra referência
- Overlay duplicando recurso inteiro pra trocar 1 campo — usar `patchesStrategicMerge` ou `patches`
- `kustomization.yaml` no root sem `apiVersion`/`kind` — algumas ferramentas reclamam, build pode falhar silenciosamente
