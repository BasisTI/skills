# Troca de família de AMI: nodegroup novo, nunca in-place

Subir a versão do Kubernetes dentro da mesma família de AMI é rotina —
`update-nodegroup-version` resolve. **Trocar a família** (`AL2_x86_64` →
`AL2023_x86_64_STANDARD`, ou qualquer mudança de `amiType`) é outra operação, e fazer isso
mudando o nodegroup existente já produziu incidente.

## O mecanismo

O AL2 usa `iptables-legacy`; o AL2023 usa `iptables-nft`. Quando o node é substituído dentro
do mesmo nodegroup em cima de estado que veio da família anterior, o kernel pode ficar com
**tabelas legacy carregadas ao mesmo tempo que o kube-proxy escreve regras em nft**. As duas
pilhas não conversam: são caminhos distintos no netfilter, e a legacy tem precedência em
partes do fluxo.

O efeito prático é assimétrico, e é o que faz o diagnóstico demorar:

| Caminho | Chain de entrada | Resultado |
|---|---|---|
| Pod → ClusterIP (via veth) | `PREROUTING` | **Quebra** — o DNAT do Service não acontece |
| Host do node → ClusterIP | `OUTPUT` | Funciona normalmente |

Quem testa de dentro do node conclui que a rede está boa. Quem está dentro de um pod não
resolve nome nenhum, porque o CoreDNS também não alcança o ClusterIP da API — fica em loop
`waiting for Kubernetes API` e o cluster parece ter perdido o DNS.

## Diagnóstico

No node suspeito (via SSM ou debug pod com `--privileged`):

```bash
# Tabelas legacy carregadas no kernel. Em node AL2023 limpo, isto vem vazio.
cat /proc/net/ip_tables_names
```

Saída com `nat` e `mangle` num node AL2023 é a assinatura. Agrava o quadro que **não há
binário `iptables-legacy` no host AL2023** — não dá para inspecionar nem para limpar as
tabelas que estão atrapalhando. Não existe conserto no node; existe node novo.

Confirmação pelo lado do sintoma, sem entrar no node:

```bash
# o ClusterIP da API — não presuma o valor, ele depende do service CIDR do cluster
API_IP=$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}')

# de dentro de um pod agendado no node suspeito
kubectl run netcheck --rm -it --restart=Never --image=busybox:1.36 \
  --overrides="{\"spec\":{\"nodeName\":\"<node>\"}}" -- \
  wget -qO- --timeout=5 --no-check-certificate "https://${API_IP}:443/version"
```

Falha aqui e sucesso no mesmo teste rodado no host fecham o diagnóstico.

## Roteiro de substituição

1. **Crie um nodegroup novo** com o `amiType` de destino, já na versão alvo do Kubernetes.
   Nodes novos nascem sem estado residual. É também a única oportunidade de anexar launch
   template — nodegroup criado sem um não aceita depois.
2. **Confirme que o novo nodegroup tem node em todas as AZs** que os volumes EBS exigem, antes
   de mover qualquer workload com estado:
   ```bash
   kubectl get nodes --label-columns=topology.kubernetes.io/zone
   ```
3. **Se algum addon estiver self-managed, adote-o antes** — em especial o VPC CNI. Node novo
   com `aws-node` em versão incompatível repete a falha de rede por outro motivo, e os dois
   sintomas são idênticos por fora.
4. **Drene os nodes antigos**, um a um, verificando entre eles. Se um operator gerencia PDB e
   StatefulSet, siga [`drain-com-postgres-operator.md`](drain-com-postgres-operator.md).
   ```bash
   kubectl cordon <node-antigo>
   kubectl drain <node-antigo> --ignore-daemonsets --delete-emptydir-data
   ```
5. **Valide antes de destruir.** DNS resolvendo de dentro de um pod nos nodes novos, pods sem
   `Pending`/`CrashLoopBackOff`, e a aplicação respondendo. Enquanto o nodegroup antigo existe,
   há rollback.
6. **Delete o nodegroup antigo.**
   ```bash
   aws eks delete-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name <antigo>
   ```

## O que não funciona

- **`aws eks update-nodegroup-version` mudando o `amiType`.** Além do estado residual, o
  comando não substitui node que já esteja na mesma `releaseVersion` — sai `Successful` sem
  ter trocado nada, e a conclusão errada é "atualizei e continua quebrado".
- **Limpar as tabelas legacy no node.** O binário para fazer isso não existe no AL2023.
- **Reiniciar o node.** O estado é do kernel do node; a instância é a mesma.
