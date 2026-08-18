# Drenar node com operator que gerencia PDB e StatefulSet

Quando um operator (Zalando `postgres-operator`, RabbitMQ, Kafka, MariaDB) governa o
workload, o drain trava por um motivo que não está no node: **o PodDisruptionBudget não
permite evicção, e apagar o PDB não adianta porque o operator o recria em segundos**. O
nodegroup fica em `Degraded` com `PodEvictionFailure` e a janela de manutenção evapora.

A saída não é `--force` — isso mata o pod que o PDB existia para proteger, com o banco no ar.
A saída é desligar o workload de propósito, na ordem certa, e deixar o operator reconciliar
depois.

## Ordem de desligamento

```bash
# 1. Identificar o que existe
kubectl get postgresql -A                 # os CRs que o operator gerencia
kubectl get pdb -A
kubectl get sts -A | grep -i postgres

# 2. Desligar o operator PRIMEIRO — enquanto ele estiver de pé, recria tudo que for apagado
kubectl scale deployment <operator> -n <namespace-do-operator> --replicas=0

# 3. Zerar os StatefulSets (com o operator desligado, vai-se direto no STS)
kubectl scale sts <nome-do-sts> -n <namespace> --replicas=0

# 4. Esperar os pods terminarem graciosamente — banco precisa de shutdown limpo
kubectl get pods -n <namespace> -w

# 5. Só agora apagar os PDBs; sem operator de pé, eles não voltam
kubectl delete pdb <pdb> -n <namespace>
```

O passo 2 antes do 3 e do 5 é o ponto todo. Na ordem inversa o operator recria StatefulSet e
PDB antes de o drain chegar no node, e o sintoma é idêntico a "o PDB não deixa" — só que agora
com um culpado invisível.

## Manutenção

Sem pods de banco e sem PDB, o drain passa:

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# ou, para o nodegroup inteiro
aws eks update-nodegroup-version --cluster-name "$CLUSTER_NAME" --nodegroup-name <nodegroup> --force
```

Aqui `--force` é legítimo: o workload que ele atropelaria já foi desligado de propósito.

## Religar — e a restrição de AZ

**Volume EBS é preso à AZ.** O pod só agenda em node da mesma zona do volume; sem node lá, ele
fica `Pending` com `volume node affinity conflict` e a leitura fácil ("o operator está com
problema") é errada. Confirme a topologia **antes** de religar:

```bash
kubectl get nodes --label-columns=topology.kubernetes.io/zone
```

Um node em cada AZ que tem volume. Só então:

```bash
kubectl scale deployment <operator> -n <namespace-do-operator> --replicas=1
```

O operator reconcilia os CRs e recria StatefulSets, PDBs e pods — que remontam os EBS
existentes. Não recrie StatefulSet à mão: ele vai brigar com o que o operator escreve.

```bash
kubectl get pods -n <namespace> -w
```

## Verificação

- Todos os membros do cluster de banco `Running` e `Ready`, não só o primário.
- Replicação em dia (para o Zalando: `kubectl get postgresql -A` com status `Running`).
- Os PDBs de volta, recriados pelo operator — se não voltaram, o operator não reconciliou.
- Um pod de aplicação conectando de fato. Banco `Ready` com Service apontando para lugar
  nenhum é um estado possível.
