# ArgoCD + Image Updater (CalVer)

Padrão Basis pra deploy contínuo: ArgoCD sincroniza manifests de Git, Image Updater monitora o registry e atualiza tags via commit no repo de manifests.

## Convenção de versão: CalVer

Formato: `YYYY.MM.DD.<Seq>` onde `Seq` é o `CI_PIPELINE_ID` do GitLab — globalmente único, monotonicamente crescente, não-contíguo.

Exemplos:
- `2026.04.23.11`
- `2026.04.24.187`
- `2026.04.25.4`

Vantagens:
- Lex/string sort = ordem cronológica → ArgoCD Image Updater "latest strategy" funciona naturalmente
- Não há ambiguidade temporal (semver não diz quando)
- O `Seq` único permite múltiplos builds no mesmo dia sem colisão

## ArgoCD Application

Uma Application por (app, ambiente). Vivem em `argocd-applications/<env>/applications/<app>.yaml`.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app>-<env>
  namespace: argocd
  annotations:
    argocd-image-updater.argoproj.io/git-branch: main
    argocd-image-updater.argoproj.io/image-list: |
      core=basis-registry.basis.com.br/<app>/core,
      ingress=basis-registry.basis.com.br/<app>/ingress
    argocd-image-updater.argoproj.io/core.allow-tags: regexp:^\d{4}\.\d{2}\.\d{2}[-.]\d+$
    argocd-image-updater.argoproj.io/core.update-strategy: latest
    argocd-image-updater.argoproj.io/ingress.allow-tags: regexp:^\d{4}\.\d{2}\.\d{2}[-.]\d+$
    argocd-image-updater.argoproj.io/ingress.update-strategy: latest
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/write-back-target: kustomization
spec:
  destination:
    name: ''
    namespace: <app>
    server: https://<cluster-host>:6443
  source:
    path: manifests/<app>/overlays/<env>
    repoURL: https://gitlab.basis.com.br/basis/iac/argocd-apps.git
    targetRevision: HEAD
  project: infraestrutura
  syncPolicy:
    automated:
      prune: true
      selfHeal: false
    syncOptions:
      - CreateNamespace=true
```

## Anotações do Image Updater explicadas

| Anotação | Função |
|----------|--------|
| `image-list: <alias>=<image>,…` | Lista imagens monitoradas. Alias é referenciado nas demais anotações |
| `<alias>.allow-tags: regexp:^\d{4}\.\d{2}\.\d{2}[-.]\d+$` | Filtro: aceita só tags CalVer (separador `.` ou `-`) |
| `<alias>.update-strategy: latest` | Pega a tag mais recente que casa o regex (ordem lex) |
| `git-branch: main` | Branch do repo de manifests onde o write-back commita |
| `write-back-method: git` | Atualiza Git (commit + push), não diretamente o cluster |
| `write-back-target: kustomization` | Atualiza o `images:` block do `kustomization.yaml` (não anota direto na Application) |

## Fluxo end-to-end

```
[Push código]
    ↓
[GitLab CI dispara Dagger pipeline]
    ↓
[Dagger build + push imagem para registry com tag CalVer YYYY.MM.DD.<CI_PIPELINE_ID>]
    ↓
[Image Updater (rodando no cluster) detecta nova tag matching regex]
    ↓
[Commit em iac/argocd-apps na branch main alterando overlays/<env>/kustomization.yaml]
    ↓
[ArgoCD detecta diff no Git → sync → kustomize build → kubectl apply]
    ↓
[Pods novos sobem com nova imagem]
```

Não há intervenção humana entre push de código e pod novo no cluster (em staging). Em production, geralmente promote manual via Image Updater para production target.

## Promote staging → production

Padrão Basis: Image Updater do staging atualiza com tag mais recente; promote pra production é controlado.

Duas opções:

**A) Tag específica em production**: Application de production com `update-strategy: digest` ou tag manual no kustomization. Promote = commit manual ou via Dagger task `Promote` (ver `dagger-pipeline-example.md`).

**B) Lag controlado**: Image Updater de production com filtro de tag mais restritivo (ex: só tags com prefix `release-` ou que passaram em staging). Atualização automática mas com delay garantido.

Padrão atual identity-hub: A — production overlay pinned manualmente, image updater só ativo em staging implicitamente (mesmo regex, mas dev controla via git).

## Verificar status

```bash
# Ver Application
kubectl -n argocd get application <app>-<env> -o yaml

# Ver últimos events do Image Updater
kubectl -n argocd logs deploy/argocd-image-updater --tail=100 | grep <app>

# Forçar sync
argocd app sync <app>-<env>
```

## Anti-padrões

- **Tag `latest` em produção** — Image Updater não consegue ordenar; deploy não-determinístico
- **Regex muito permissiva** (`.*`) — pode pegar tags de teste, hot-fix, anything → deploy de coisa não-validada
- **`write-back-method: argocd`** (anotação direta na Application) — não atualiza o repo de manifests; `git pull && kustomize build` localmente mostra estado inconsistente
- **`automated.selfHeal: true`** sem cuidado — desfaz mudanças manuais legítimas (ex: scale 0 pra manutenção). Padrão Basis: `selfHeal: false`
- **Branch `develop` em vez de `main` para write-back** — depende do projeto, mas precisa bater com o que ArgoCD lê em `targetRevision: HEAD`
- **CalVer sem `Seq`** (`YYYY.MM.DD`) — colisão em múltiplos builds no mesmo dia, push é rejeitado ou sobrescreve
