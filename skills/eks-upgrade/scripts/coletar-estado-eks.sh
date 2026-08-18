#!/usr/bin/env bash
#
# coletar-estado-eks.sh — fotografia read-only de um cluster EKS antes do upgrade.
#
# Executa apenas `aws eks list-*/describe-*` e `kubectl get`. Não muta cluster.
#
# Uso:
#   coletar-estado-eks.sh --cluster <nome> --context <ctx> [--target 1.35] [--region <regiao>]
#                         [--snapshot <arquivo>]
#
# Cada flag cai na variável de ambiente correspondente quando omitida:
#   --cluster  -> $CLUSTER_NAME
#   --context  -> $EKS_KUBECTL_CONTEXT
#   --region   -> $EKS_REGION (senão, a região do perfil da AWS em uso)
#   --target   -> $EKS_TARGET_VERSION (senão, a próxima minor depois do control plane)
#
# --snapshot grava o estado num arquivo (único efeito de escrita do script). Rode uma vez
# antes do upgrade e outra depois, e passe os dois arquivos para gerar-relatorio.sh.
#
# Sem `set -e` de propósito: erro de comando é dado de diagnóstico, não motivo para
# abortar a coleta. A linha que falhar sai marcada com (!).

set -u
export AWS_PAGER=""

CLUSTER="${CLUSTER_NAME:-}"
CONTEXTO="${EKS_KUBECTL_CONTEXT:-}"
REGIAO="${EKS_REGION:-}"
ALVO="${EKS_TARGET_VERSION:-}"
SNAPSHOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --cluster)  CLUSTER="${2:-}";  shift 2 ;;
    --context)  CONTEXTO="${2:-}"; shift 2 ;;
    --region)   REGIAO="${2:-}";   shift 2 ;;
    --target)   ALVO="${2:-}";     shift 2 ;;
    --snapshot) SNAPSHOT="${2:-}"; shift 2 ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

: "${CLUSTER:?CLUSTER_NAME não informado — use --cluster ou exporte CLUSTER_NAME. Para listar: aws eks list-clusters}"
: "${CONTEXTO:?EKS_KUBECTL_CONTEXT não informado — use --context ou exporte EKS_KUBECTL_CONTEXT. Para listar: kubectl config get-contexts}"

REG=()
[ -n "$REGIAO" ] && REG=(--region "$REGIAO")

linha() { printf '%-14s %s\n' "$1" "$2"; }
ALERTAS=()
SNAP=""
snap() { local IFS=$'\t'; SNAP+="$*"$'\n'; }

# --- control plane ---------------------------------------------------------
if ! CP=$(aws eks describe-cluster --name "$CLUSTER" "${REG[@]}" --query 'cluster.version' --output text 2>&1) \
   || [ -z "$CP" ] || [ "$CP" = "None" ]; then
  echo "(!) não foi possível descrever o cluster '$CLUSTER': $CP" >&2
  echo "    confira o nome (aws eks list-clusters), a região e as credenciais." >&2
  exit 1
fi

NOTA_ALVO=""
if [ -z "$ALVO" ]; then
  ALVO="${CP%%.*}.$(( ${CP##*.} + 1 ))"
  NOTA_ALVO=" (sugerido)"
fi

snap meta momento "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
snap meta cluster "$CLUSTER"
snap meta regiao "${REGIAO:-default}"
snap meta alvo "$ALVO"
snap cp version "$CP"

linha "CLUSTER" "$CLUSTER${REGIAO:+  [$REGIAO]}"
linha "CONTROL PLANE" "$CP  ->  alvo $ALVO$NOTA_ALVO"

# --- kubelets --------------------------------------------------------------
if ! KUBELETS=$(kubectl --context "$CONTEXTO" get nodes \
     -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' 2>&1); then
  linha "KUBELETS" "(!) kubectl falhou: $(echo "$KUBELETS" | head -1)"
else
  primeira=1
  while read -r qtd ver; do
    [ -z "$ver" ] && continue
    rotulo=$([ "$primeira" -eq 1 ] && echo "KUBELETS" || echo "")
    linha "$rotulo" "$ver ($qtd nodes)"
    primeira=0
    snap kubelet "$ver" "$qtd"
    # v1.34.2-eks-xxx -> 1.34
    minor=$(echo "$ver" | sed 's/^v//' | cut -d. -f1,2)
    [ "$minor" != "$CP" ] && ALERTAS+=("kubelet em $minor com control plane em $CP — skew de versão")
  done < <(echo "$KUBELETS" | sort | uniq -c)
fi

# --- nodegroups ------------------------------------------------------------
if ! NGS=$(aws eks list-nodegroups --cluster-name "$CLUSTER" "${REG[@]}" --query 'nodegroups[]' --output text 2>&1); then
  linha "NODEGROUPS" "(!) $(echo "$NGS" | head -1)"
elif [ -z "$NGS" ]; then
  linha "NODEGROUPS" "nenhum managed node group (Fargate ou Karpenter?)"
else
  primeira=1
  for ng in $NGS; do
    IFS=$'\t' read -r ver rel ami st < <(aws eks describe-nodegroup \
      --cluster-name "$CLUSTER" --nodegroup-name "$ng" "${REG[@]}" \
      --query 'nodegroup.[version,releaseVersion,amiType,status]' --output text 2>/dev/null)
    rotulo=$([ "$primeira" -eq 1 ] && echo "NODEGROUPS" || echo "")
    linha "$rotulo" "$ng  ${ami:-?}  ${ver:-?}  ${rel:-?}  ${st:-?}"
    primeira=0
    snap nodegroup "$ng" "${ver:-?}" "${rel:-?}" "${ami:-?}" "${st:-?}"
    case "${ami:-}" in
      AL2_*) ALERTAS+=("$ng usa $ami — mudar para AL2023 exige NODEGROUP NOVO, não update in-place (references/migracao-familia-ami.md)") ;;
    esac
    [ "${st:-}" != "ACTIVE" ] && ALERTAS+=("$ng em status ${st:-?} — resolva antes de atualizar")
  done
fi

# --- addons ----------------------------------------------------------------
if ! ADDONS=$(aws eks list-addons --cluster-name "$CLUSTER" "${REG[@]}" --query 'addons[]' --output text 2>&1); then
  linha "ADDONS" "(!) $(echo "$ADDONS" | head -1)"
elif [ -z "$ADDONS" ]; then
  linha "ADDONS" "nenhum addon gerenciado — componentes self-managed não são cobertos aqui"
else
  primeira=1
  for addon in $ADDONS; do
    atual=$(aws eks describe-addon --cluster-name "$CLUSTER" --addon-name "$addon" "${REG[@]}" \
      --query 'addon.addonVersion' --output text 2>/dev/null)
    # shellcheck disable=SC2016  # as crases são sintaxe de literal do JMESPath, não do shell
    default=$(aws eks describe-addon-versions --addon-name "$addon" --kubernetes-version "$ALVO" "${REG[@]}" \
      --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion' \
      --output text 2>/dev/null)
    if [ -z "$default" ] || [ "$default" = "None" ]; then
      destino="(!) sem versão default publicada para $ALVO"
    elif [ "$atual" = "$default" ]; then
      destino="(em dia)"
    else
      destino="-> $default"
    fi
    rotulo=$([ "$primeira" -eq 1 ] && echo "ADDONS" || echo "")
    linha "$rotulo" "$(printf '%-22s %-26s %s' "$addon" "${atual:-?}" "$destino")"
    primeira=0
    snap addon "$addon" "${atual:-?}" "${default:-?}"
  done
fi

# --- PDBs que travam drain -------------------------------------------------
PDBS=$(kubectl --context "$CONTEXTO" get pdb -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" "}{.status.disruptionsAllowed}{"\n"}{end}' 2>/dev/null \
  | awk '$2 == 0 {print $1}')
if [ -n "$PDBS" ]; then
  primeira=1
  for p in $PDBS; do
    rotulo=$([ "$primeira" -eq 1 ] && echo "PDB BLOQ." || echo "")
    linha "$rotulo" "$p (0 disrupções permitidas)"
    primeira=0
    snap pdb "$p" 0
  done
  ALERTAS+=("há PDB sem folga — o drain vai travar (references/drain-com-postgres-operator.md)")
else
  linha "PDB BLOQ." "nenhum PDB com 0 disrupções permitidas"
fi

# --- upgrade insights ------------------------------------------------------
if ! INS=$(aws eks list-insights --cluster-name "$CLUSTER" "${REG[@]}" \
     --filter categories=UPGRADE_READINESS \
     --query 'insights[].[insightStatus.status,name,id]' --output text 2>&1); then
  linha "INSIGHTS" "(!) $(echo "$INS" | head -1)"
else
  total=$(echo "$INS" | grep -c .)
  ruins=$(echo "$INS" | grep -cv '^PASSING')
  while IFS=$'\t' read -r st nome id; do
    [ -z "$st" ] && continue
    snap insight "$st" "$nome" "$id"
  done < <(echo "$INS")
  if [ "$ruins" -eq 0 ]; then
    linha "INSIGHTS" "UPGRADE_READINESS: $total PASSING"
  else
    primeira=1
    while IFS=$'\t' read -r st nome id; do
      [ "$st" = "PASSING" ] && continue
      rotulo=$([ "$primeira" -eq 1 ] && echo "INSIGHTS" || echo "")
      linha "$rotulo" "$st — $nome  (id $id)"
      primeira=0
    done < <(echo "$INS")
    ALERTAS+=("$ruins insight(s) fora de PASSING — aws eks describe-insight --cluster-name $CLUSTER --id <id>")
  fi
fi

# --- alertas ---------------------------------------------------------------
if [ ${#ALERTAS[@]} -gt 0 ]; then
  echo
  printf '%s\n' "${ALERTAS[@]}" | sort -u | sed 's/^/ALERTA  /'
fi

# --- snapshot --------------------------------------------------------------
if [ -n "$SNAPSHOT" ]; then
  if printf '# coletar-estado-eks snapshot v1\n%s' "$SNAP" > "$SNAPSHOT"; then
    echo
    echo "snapshot gravado em $SNAPSHOT"
  else
    echo "(!) não foi possível gravar o snapshot em $SNAPSHOT" >&2
  fi
fi
