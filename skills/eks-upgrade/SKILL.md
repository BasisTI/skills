---
name: eks-upgrade
description: Upgrade de versão do Kubernetes num cluster EKS — control plane, nodegroups gerenciados, addons da AWS e os componentes que ficam fora do addon manager. Use quando alguém disser "atualizar o cluster", "subir o EKS para a 1.x", "upgrade do EKS", "qual versão do addon é compatível", "os nodes continuam na versão antiga", "o drain travou", "vou trocar o node group", "registrar o que foi atualizado", "relatório do upgrade"; ao planejar janela de manutenção de cluster; ou quando DNS/CoreDNS quebra logo depois de um upgrade. Precisa de `$EKS_KUBECTL_CONTEXT` e `$CLUSTER_NAME`, que vêm do prompt, do `AGENTS.md`/`CLAUDE.md` do repositório ou do ambiente — nunca adivinhados. Prefira esta à `basis-k8s-deploy` quando o assunto for ciclo de vida do cluster e não deploy de aplicação, porque o sintoma engana: pod que não sobe depois do upgrade parece problema de manifesto e é de node, de addon ou de AZ.
---

# Upgrade de cluster EKS

Upgrade de EKS não é um comando. São **quatro planos que sobem separados e se desencontram**:
control plane, kubelets dos nodes, addons gerenciados pela AWS e os componentes que vivem no
cluster sem passar pelo addon manager. "Atualizei o cluster" quase sempre quer dizer que só o
primeiro subiu — e o desencontro entre eles não dá erro na hora, dá erro depois, no pod que
não sobe.

Duas regras que não se negociam: **uma minor por vez** (de 1.34 para 1.36 passa-se pela 1.35),
e **não existe downgrade**. Depois que o control plane sobe, o caminho é para frente.

## Quando usar

Alguém diz: *"preciso atualizar o cluster para a 1.35"*, *"os nodes continuam na versão
antiga"*, *"o drain travou"*, *"o DNS parou depois do upgrade"*.

Esta skill **não** cobre deploy de aplicação (`basis-k8s-deploy`), criação de cluster, nem
nodes gerenciados por Karpenter — o procedimento de workers aqui é o de **managed node group**.

## Os hábitos que resolvem

**1. Fotografe os quatro planos antes de tocar em qualquer um.** O erro caro não é escolher a
versão errada, é subir o control plane sem saber que um addon está incompatível ou que um PDB
vai travar o drain três horas depois, com o cluster já em versão mista.

**2. Deixe a AWS dizer o que vai quebrar, antes de quebrar.** O `list-insights` de
`UPGRADE_READINESS` testa skew de kubelet, skew de kube-proxy, compatibilidade de addon e uso
de AMI Amazon Linux 2 — de graça e sem risco. Rodar isso é mais barato que descobrir no meio
da janela.

**3. Quando alguém apontar uma causa, teste do lugar certo.** Boa parte do diagnóstico
pós-upgrade se perde porque o teste é feito a partir do host do node, e o tráfego que quebrou
é o de pod. São caminhos diferentes no netfilter; um passa enquanto o outro falha.

## 0. Parâmetros — `$EKS_KUBECTL_CONTEXT` e `$CLUSTER_NAME`

A skill precisa de dois valores e **não descobre nenhum dos dois sozinha**:

| Variável | O que é |
|---|---|
| `$CLUSTER_NAME` | Nome do cluster no EKS, como aparece em `aws eks list-clusters` |
| `$EKS_KUBECTL_CONTEXT` | Nome do contexto no kubeconfig, como aparece em `kubectl config get-contexts` |
| `$EKS_REGION` | Opcional. Sem ela, vale a região do perfil da AWS em uso |

Resolva nesta ordem, parando na primeira que responder:

1. **O prompt.** *"Atualize o cluster `X`, contexto `Y`, alvo 1.35."*
2. **`AGENTS.md` / `CLAUDE.md` do repositório de trabalho.** É onde o valor deve morar quando
   o cluster é sempre o mesmo — veja o bloco abaixo.
3. **Variável de ambiente exportada** (`$CLUSTER_NAME`, `$EKS_KUBECTL_CONTEXT`, `$EKS_REGION`).
4. **Pergunte.** `aws eks list-clusters` e `kubectl config get-contexts` servem para **montar a
   pergunta**, não para escolher. Um único resultado não é confirmação: kubeconfig com um
   contexto só é comum em quem tem vários clusters e troca de arquivo.

Bloco para colar no `AGENTS.md` do repositório (`CLAUDE.md` como symlink para ele):

```markdown
## Cluster EKS

- `CLUSTER_NAME`: `<nome-do-cluster>`
- `EKS_KUBECTL_CONTEXT`: `<contexto>`   <!-- o que `kubectl config get-contexts` imprime; costuma ser o ARN do cluster -->
- `EKS_REGION`: `<regiao>`
```

**Cuidado com região.** `aws eks list-clusters` só enxerga a região corrente. Cluster em outra
região não aparece na lista — e a ausência parece "não existe" em vez de "você está olhando
para o lugar errado". Se o usuário afirma que o cluster existe e a lista vem vazia, a hipótese
é região, não nome.

## 1. Pré-voo

Pré-requisitos, uma vez: `which aws kubectl`; `~/.aws/config` e `~/.aws/credentials` existindo
(ou credencial por SSO/perfil já ativa); `$KUBECONFIG` apontando para arquivo existente e, se a
variável não existir, `~/.kube/config` presente.

Todo o levantamento numa passada:

```bash
scripts/coletar-estado-eks.sh --cluster "$CLUSTER_NAME" --context "$EKS_KUBECTL_CONTEXT" \
  --target 1.35 --snapshot antes.txt
```

Imprime, lado a lado, versão do control plane e alvo, versões dos kubelets, nodegroups com
`amiType`/`version`/`releaseVersion`, cada addon com versão atual → versão default do alvo, os
PDBs que hoje não permitem nenhuma disrupção, e os insights que não estão `PASSING`. Read-only.

**Grave o snapshot agora**, mesmo que o upgrade fique para outro dia. É a linha de base do
relatório final (passo 6) e não dá para reconstruí-la depois — o estado anterior deixa de
existir no instante em que o control plane sobe.

Antes de seguir, quatro conferências:

**Alvo é uma minor à frente, e está em suporte.**

```bash
aws eks describe-cluster-versions \
  --query 'clusterVersions[?versionStatus==`STANDARD_SUPPORT`].[clusterVersion,endOfStandardSupportDate]' \
  --output table
```

**Insights de prontidão, todos `PASSING`.** É o único check que pega API removida na versão
alvo antes de o control plane subir:

```bash
aws eks list-insights --cluster-name "$CLUSTER_NAME" --filter categories=UPGRADE_READINESS \
  --query 'insights[].[insightStatus.status,name,id]' --output text

# no que não estiver PASSING — a coluna id é a que entra aqui:
aws eks describe-insight --cluster-name "$CLUSTER_NAME" --id <insight-id> \
  --query 'insight.[name,insightStatus.reason,recommendation,resources]'
```

**PDBs.** `kubectl --context "$EKS_KUBECTL_CONTEXT" get pdb -A` — PDB não atrapalha agora, ele
trava o drain lá na frente, com o cluster já em versão mista. Se houver operator gerenciando
PDB (Postgres, RabbitMQ, Kafka), resolva antes: `references/drain-com-postgres-operator.md`.

**Componentes fora do addon manager.** Não aparecem em `list-addons` e ninguém avisa quando
ficam incompatíveis: `aws-load-balancer-controller` (Helm), external-dns, cert-manager,
ingress controllers. A matriz de compatibilidade sai do release do próprio projeto — para o
ALB controller, <https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases>.

## 2. Control plane

```bash
aws eks update-cluster-version --name "$CLUSTER_NAME" --kubernetes-version <alvo>
```

A saída traz `.update.id`, que é como se acompanha:

```bash
aws eks describe-update --name "$CLUSTER_NAME" --update-id <update-id> \
  --query 'update.[status,type,errors]'
```

Espere `Successful` antes de tocar nos workers. Leva dezenas de minutos e **não tem volta** —
se o pré-voo foi pulado, é aqui que a decisão vira irreversível.

## 3. Workers

Levante o que existe:

```bash
aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups[]' --output text

aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name <nodegroup> \
  --query 'nodegroup.[version,releaseVersion,amiType,status]' --output text
```

`amiType` é o campo que decide o caminho:

> **Troca de família de AMI é nodegroup novo, nunca update in-place.** Sair de `AL2_x86_64`
> para `AL2023_x86_64_STANDARD` mudando o nodegroup existente deixa estado residual de
> netfilter no kernel dos nodes e quebra o tráfego de pod → ClusterIP, com o tráfego do host
> continuando a funcionar e mascarando a causa. O roteiro está em
> `references/migracao-familia-ami.md`. Também não dá para adicionar launch template a um
> nodegroup que foi criado sem um — é outro motivo para nodegroup novo.

Mesma família de AMI, só subindo a versão:

```bash
aws eks update-nodegroup-version \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name <nodegroup> \
  --kubernetes-version <alvo>
```

Três coisas que o comando não diz:

- **Ele não substitui node que já esteja na mesma `releaseVersion`.** Sai `Successful` sem ter
  trocado nada. Se o objetivo era renovar os nodes (e não subir versão), o caminho é
  `--force`, ou nodegroup novo.
- **`--force` atropela a evicção.** Ele conclui o rolling mesmo quando um PDB impede o drain —
  ou seja, mata pod que o PDB existia para proteger. Legítimo depois de desligar o workload de
  propósito; perigoso como primeira tentativa. Prefira resolver o PDB.
- **O ASG precisa de folga.** O rolling sobe node novo antes de drenar o velho; sem capacidade
  ou sem subnet em alguma AZ, o update fica em `Degraded`.

Acompanhe do mesmo jeito que o control plane, com `describe-update --nodegroup-name`.

## 4. Addons

```bash
aws eks list-addons --cluster-name "$CLUSTER_NAME" --query 'addons[]' --output text

# versão instalada hoje
aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name <addon> \
  --query 'addon.addonVersion' --output text

# a versão default para a versão alvo do Kubernetes
aws eks describe-addon-versions --addon-name <addon> --kubernetes-version <alvo> \
  --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion' \
  --output text
```

**Não use `addonVersions[0]`.** O primeiro elemento é a mais recente, não a default — para o
`coredns` na 1.34, `[0]` devolve `v1.13.2-eksbuild.11` enquanto a default é
`v1.12.4-eksbuild.18`. Para ver o leque inteiro, `addons[].addonVersions[].addonVersion`.

```bash
aws eks update-addon --cluster-name "$CLUSTER_NAME" \
  --addon-name <addon> \
  --addon-version <versao> \
  --resolve-conflicts PRESERVE
```

**`--resolve-conflicts` é a escolha que apaga trabalho.** `OVERWRITE` devolve o addon à
configuração padrão da AWS e leva junto o que foi editado à mão — Corefile do CoreDNS com
`log`, `health { lameduck 5s }` ou zona de stub, tolerations e recursos ajustados no
kube-proxy. `PRESERVE` mantém o que foi mudado. Antes de decidir, olhe o que existe hoje:

```bash
kubectl --context "$EKS_KUBECTL_CONTEXT" -n kube-system get configmap coredns -o yaml
```

**VPC CNI self-managed não aparece em `list-addons`.** Se o `aws-node` foi instalado por
manifesto ou Helm, ele não é addon gerenciado e o upgrade simplesmente não o alcança — fica
para trás e a incompatibilidade aparece como falha de rede em node novo. Adote como addon
gerenciado (`aws eks create-addon --addon-name vpc-cni --resolve-conflicts OVERWRITE`) antes
do upgrade dos workers.

## 5. Verificação pós-upgrade

```bash
CTX="$EKS_KUBECTL_CONTEXT"

# 1. todos os kubelets na versão alvo — uma linha só é o resultado esperado
kubectl --context "$CTX" get nodes \
  -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' | sort -u

# 2. node em cada AZ que os volumes EBS exigem
kubectl --context "$CTX" get nodes --label-columns=topology.kubernetes.io/zone

# 3. nada parado
kubectl --context "$CTX" get pods -A --field-selector=status.phase!=Running | head -20

# 4. DNS respondendo DE DENTRO DE UM POD — não do host do node
kubectl --context "$CTX" -n kube-system get pods -l k8s-app=kube-dns
kubectl --context "$CTX" run dnstest --rm -it --restart=Never --image=busybox:1.36 -- \
  nslookup kubernetes.default.svc.cluster.local
```

O passo 4 é o que separa "subiu" de "funciona". Um pod que resolve `kubernetes.default` provou
o caminho pod → ClusterIP → CoreDNS → ClusterIP da API. Nenhum comando rodado por SSH no node
prova isso.

## 6. Registrar o que foi feito

O relatório sai **por diferença entre dois snapshots**, não de memória. Por isso a coleta do
passo 1 tem que ser gravada antes de a janela começar:

```bash
# antes de tocar em qualquer coisa
scripts/coletar-estado-eks.sh --cluster "$CLUSTER_NAME" --context "$EKS_KUBECTL_CONTEXT" \
  --target <alvo> --snapshot antes.txt

# ... upgrade ...

# depois da verificação do passo 5
scripts/coletar-estado-eks.sh --cluster "$CLUSTER_NAME" --context "$EKS_KUBECTL_CONTEXT" \
  --snapshot depois.txt

scripts/gerar-relatorio.sh --antes antes.txt --depois depois.txt
# -> relatorio-upgrade-<cluster>-<AAAAMMDD>.md
```

O `.md` já vem preenchido com o que os snapshots provam: versão do Kubernetes antes e depois,
kubelets, node groups (versão, `releaseVersion`, `amiType` e o que aconteceu com cada um),
addons com situação por addon, PDBs no estado final e insights que continuam fora de
`PASSING`. **Troca de família de AMI é detectada e comentada** — distinguindo a substituição
por node group novo, que é o caminho certo, da troca dentro do mesmo node group, que é o
anti-padrão e ganha o aviso de validar DNS de dentro de um pod.

O que os snapshots não sabem sai como `<!-- preencher -->`: janela, quem executou,
indisponibilidade percebida, ocorrências, componentes fora do addon manager e pendências.
São poucas linhas e são justamente as que ninguém lembra uma semana depois.

Se esqueceu o snapshot "antes", o relatório ainda sai — só que a coluna de origem vira
adivinhação. Nesse caso, escreva o relatório à mão a partir dos `describe-update` que ficaram
no histórico, e diga no texto que a linha de base foi reconstruída.

## Assinatura — sintoma e causa

| Observação | O que significa |
|---|---|
| CoreDNS em `CrashLoopBackOff` ou em loop `waiting for Kubernetes API`, e um `curl` ao ClusterIP da API funciona quando rodado no host do node | Estado residual de netfilter depois de troca de família de AMI. Tráfego de pod entra por `PREROUTING`, o do host por `OUTPUT` — só o primeiro quebra. `references/migracao-familia-ami.md` |
| Pod com volume EBS fica `Pending` depois da substituição de node, com `volume node affinity conflict` | Volume é preso à AZ e não existe node naquela AZ. Só resolve subindo node lá — não é problema de scheduler |
| Drain não termina; nodegroup em `Degraded` com `PodEvictionFailure` | PDB bloqueando. Se um operator o recria, desligue o operator antes: `references/drain-com-postgres-operator.md` |
| `update-nodegroup-version` sai `Successful` e os nodes continuam na versão antiga | Já estavam na mesma `releaseVersion`; o comando não teve o que fazer |
| Addon volta ao comportamento padrão e a configuração some | `--resolve-conflicts OVERWRITE` |
| Control plane na versão nova, aplicação quebrando em chamada de API | API removida na minor — era o que o insight de `UPGRADE_READINESS` apontava antes |
| Node novo `Ready`, pods nele sem rede | CNI ainda subindo, ou `aws-node` self-managed em versão velha |

## Ferramentas que mentem

- **`aws eks describe-cluster --query cluster.version`** responde pelo control plane e é lido
  como "a versão do cluster". Não diz nada sobre os kubelets. A pergunta "em que versão está o
  cluster?" tem duas respostas e elas divergem no meio do upgrade.
- **Teste de conectividade a partir do host do node.** Passa enquanto o de pod falha, porque
  são caminhos diferentes no netfilter. Todo teste de rede pós-upgrade tem que sair de um pod.
- **`addonVersions[0]`.** É a mais recente, não a default nem necessariamente a recomendada
  para a sua versão.
- **`kubectl get nodes` mostrando `Ready`.** O node fica `Ready` antes de o CNI estar pronto
  para atender pod. Durante rolling, `Ready` não é sinal de que pode drenar o próximo.
- **`aws eks list-clusters` vazio.** Quase sempre é região errada, não cluster inexistente.

## Erros a evitar

**Pular duas minors.** O EKS recusa, mas o erro chega depois de o pré-voo já ter dado
confiança de que estava tudo certo.

**Subir o control plane com insight em `WARNING`.** Não tem volta, e o insight é justamente o
aviso do que vai quebrar.

**Usar `--force` como primeira tentativa quando o drain trava.** Ele resolve o sintoma matando
o pod que o PDB protegia.

**Atualizar nodegroup para trocar família de AMI.** É o erro que já custou um incidente inteiro
de DNS. Nodegroup novo.

**Deixar os componentes fora do addon manager para depois.** Ninguém avisa, e eles quebram
depois que a janela fechou.

**Fechar a janela sem gravar o snapshot inicial.** Sem linha de base, o relatório vira
lembrança — e a pergunta que aparece dali a seis meses ("de que versão a gente veio? o node
group velho chegou a ser deletado?") não tem mais resposta verificável.

## Scripts

| Script | Muta? | Uso |
|---|---|---|
| `scripts/coletar-estado-eks.sh` | Não; com `--snapshot`, grava só o arquivo indicado | Fotografia dos quatro planos numa passada, com atual → alvo lado a lado |
| `scripts/gerar-relatorio.sh` | Grava só o `.md` de saída | Relatório do que mudou, por diferença entre dois snapshots |

Nenhum dos dois muta cluster nem fala com a AWS para escrever — `coletar-estado-eks.sh` só
chama `aws eks list-*/describe-*` e `kubectl get`, e `gerar-relatorio.sh` não sai do disco.
Todo comando de mutação desta skill está no corpo do `SKILL.md`, explícito, para ser executado
com aprovação.

## References

- [`references/migracao-familia-ami.md`](references/migracao-familia-ami.md) — Por que trocar
  de família de AMI exige nodegroup novo, o mecanismo do estado residual de netfilter, o
  diagnóstico e o roteiro de substituição.
- [`references/drain-com-postgres-operator.md`](references/drain-com-postgres-operator.md) —
  Drenar node com operator que gerencia PDB e StatefulSet: ordem de desligamento, a restrição
  de AZ do EBS e a ordem de religamento.
