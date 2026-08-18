#!/usr/bin/env bash
#
# gerar-relatorio.sh — relatório do upgrade, por diferença entre dois snapshots.
#
# Não fala com a AWS nem com o cluster: lê os dois arquivos gravados por
# `coletar-estado-eks.sh --snapshot` e escreve um .md com o que mudou de fato.
#
# Uso:
#   coletar-estado-eks.sh --cluster X --context Y --snapshot antes.txt     # antes da janela
#   ... executar o upgrade ...
#   coletar-estado-eks.sh --cluster X --context Y --snapshot depois.txt    # depois da janela
#   gerar-relatorio.sh --antes antes.txt --depois depois.txt [-o relatorio.md]
#
# Sem -o, o nome sai de cluster + data: relatorio-upgrade-<cluster>-<AAAAMMDD>.md
#
# O que o script preenche é o que ele consegue provar. O que depende de quem esteve na
# janela — horário, quem executou, o que deu errado — sai como marcador a preencher.

set -u

ANTES=""
DEPOIS=""
SAIDA=""

while [ $# -gt 0 ]; do
  case "$1" in
    --antes)     ANTES="${2:-}";  shift 2 ;;
    --depois)    DEPOIS="${2:-}"; shift 2 ;;
    -o|--output) SAIDA="${2:-}";  shift 2 ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

: "${ANTES:?--antes não informado (snapshot gravado antes do upgrade)}"
: "${DEPOIS:?--depois não informado (snapshot gravado depois do upgrade)}"
[ -r "$ANTES" ]  || { echo "não consigo ler $ANTES" >&2;  exit 1; }
[ -r "$DEPOIS" ] || { echo "não consigo ler $DEPOIS" >&2; exit 1; }

declare -A A_META B_META A_NG B_NG A_ADDON B_ADDON
A_KUBELET=""; B_KUBELET=""
A_INSIGHT_RUINS=""; B_INSIGHT_RUINS=""
A_PDB=""; B_PDB=""

carregar() {
  local arquivo="$1" lado="$2" tipo k v1 v2 v3 v4
  while IFS=$'\t' read -r tipo k v1 v2 v3 v4; do
    case "$tipo" in
      \#*|"") continue ;;
      meta)     if [ "$lado" = A ]; then A_META[$k]="$v1"; else B_META[$k]="$v1"; fi ;;
      cp)       if [ "$lado" = A ]; then A_META[cp]="$v1";  else B_META[cp]="$v1";  fi ;;
      kubelet)  if [ "$lado" = A ]; then A_KUBELET+="$k ($v1 nodes) "; else B_KUBELET+="$k ($v1 nodes) "; fi ;;
      nodegroup) if [ "$lado" = A ]; then A_NG[$k]="$v1|$v2|$v3|$v4"; else B_NG[$k]="$v1|$v2|$v3|$v4"; fi ;;
      addon)    if [ "$lado" = A ]; then A_ADDON[$k]="$v1"; else B_ADDON[$k]="$v1"; fi ;;
      pdb)      if [ "$lado" = A ]; then A_PDB+="$k "; else B_PDB+="$k "; fi ;;
      insight)  [ "$k" = PASSING ] && continue
                if [ "$lado" = A ]; then A_INSIGHT_RUINS+="$k: $v1"$'\n'; else B_INSIGHT_RUINS+="$k: $v1"$'\n'; fi ;;
    esac
  done < "$arquivo"
}

carregar "$ANTES" A
carregar "$DEPOIS" B
A_KUBELET="${A_KUBELET% }"; B_KUBELET="${B_KUBELET% }"

CLUSTER="${B_META[cluster]:-${A_META[cluster]:-?}}"
if [ -z "$SAIDA" ]; then
  SAIDA="relatorio-upgrade-${CLUSTER}-$(date -u +%Y%m%d).md"
fi

campo() { echo "$1" | cut -d'|' -f"$2"; }   # 1=version 2=releaseVersion 3=amiType 4=status

# --- corpo -----------------------------------------------------------------
{
echo "# Upgrade do cluster \`$CLUSTER\`"
echo
echo "| | |"
echo "|---|---|"
echo "| Cluster | \`$CLUSTER\` |"
echo "| Região | \`${B_META[regiao]:-?}\` |"
echo "| Coleta antes | ${A_META[momento]:-?} |"
echo "| Coleta depois | ${B_META[momento]:-?} |"
echo "| Relatório gerado em | $(date -u +%Y-%m-%dT%H:%M:%SZ) |"
echo
echo "Horários em UTC. As linhas marcadas com \`<!-- preencher -->\` não saem dos snapshots:"
echo "dependem de quem esteve na janela."
echo
echo "## Kubernetes"
echo
if [ "${A_META[cp]:-?}" = "${B_META[cp]:-?}" ]; then
  echo "Control plane permaneceu em **${B_META[cp]:-?}** — o upgrade de versão não aconteceu"
  echo "ou a janela cobriu apenas workers/addons."
else
  echo "Control plane: **${A_META[cp]:-?} → ${B_META[cp]:-?}**"
fi
echo
echo "| | Antes | Depois |"
echo "|---|---|---|"
echo "| Control plane | ${A_META[cp]:-?} | ${B_META[cp]:-?} |"
echo "| Kubelets | ${A_KUBELET:-?} | ${B_KUBELET:-?} |"
echo

# --- nodegroups ------------------------------------------------------------
echo "## Node groups"
echo
echo "| Node group | Versão | Release | AMI type | O que aconteceu |"
echo "|---|---|---|---|---|"
TROCA_AMI_INPLACE=0
AMIS_ANTES=""; AMIS_DEPOIS=""
for ng in "${!A_NG[@]}"; do AMIS_ANTES+="$(campo "${A_NG[$ng]}" 3)"$'\n'; done
for ng in "${!B_NG[@]}"; do AMIS_DEPOIS+="$(campo "${B_NG[$ng]}" 3)"$'\n'; done
AMIS_ANTES=$(echo "$AMIS_ANTES" | sed '/^$/d' | sort -u)
AMIS_DEPOIS=$(echo "$AMIS_DEPOIS" | sed '/^$/d' | sort -u)
for ng in $(printf '%s\n%s\n' "${!A_NG[*]}" "${!B_NG[*]}" | tr ' ' '\n' | sort -u); do
  [ -z "$ng" ] && continue
  a="${A_NG[$ng]:-}"; b="${B_NG[$ng]:-}"
  if [ -z "$a" ]; then
    echo "| \`$ng\` | $(campo "$b" 1) | $(campo "$b" 2) | $(campo "$b" 3) | **criado** |"
    continue
  fi
  if [ -z "$b" ]; then
    echo "| \`$ng\` | $(campo "$a" 1) | $(campo "$a" 2) | $(campo "$a" 3) | **removido** |"
    continue
  fi
  av=$(campo "$a" 1); bv=$(campo "$b" 1)
  ar=$(campo "$a" 2); br=$(campo "$b" 2)
  aa=$(campo "$a" 3); ba=$(campo "$b" 3)
  if [ "$aa" != "$ba" ]; then
    obs="**troca de família de AMI no mesmo node group**"
    TROCA_AMI_INPLACE=1
  elif [ "$av" != "$bv" ]; then
    obs="versão atualizada"
  elif [ "$ar" != "$br" ]; then
    obs="nodes substituídos (mesma minor)"
  else
    obs="sem mudança"
  fi
  ver=$([ "$av" = "$bv" ] && echo "$bv" || echo "$av → $bv")
  rel=$([ "$ar" = "$br" ] && echo "$br" || echo "$ar → $br")
  ami=$([ "$aa" = "$ba" ] && echo "$ba" || echo "$aa → $ba")
  echo "| \`$ng\` | $ver | $rel | $ami | $obs |"
done
echo
if [ "$TROCA_AMI_INPLACE" = 1 ]; then
  echo "> **A família de AMI mudou dentro do mesmo node group.** É o caminho que deixa estado"
  echo "> residual de netfilter no kernel dos nodes e quebra o tráfego de pod → ClusterIP, com o"
  echo "> tráfego do host continuando a funcionar e mascarando a causa. Valide o DNS de dentro de"
  echo "> um pod antes de encerrar a janela e considere substituir por node group novo."
  echo "> Ver \`references/migracao-familia-ami.md\`."
  echo
elif [ "$AMIS_ANTES" != "$AMIS_DEPOIS" ]; then
  echo "> Houve **troca de família de AMI** na frota — de \`$(echo "$AMIS_ANTES" | paste -sd, -)\`"
  echo "> para \`$(echo "$AMIS_DEPOIS" | paste -sd, -)\`, por node group novo, que é o caminho certo."
  echo "> Confirme antes de fechar a janela: node group antigo drenado e deletado, node em cada AZ"
  echo "> que tem volume EBS, e DNS resolvendo de dentro de um pod nos nodes novos."
  echo "> Ver \`references/migracao-familia-ami.md\`."
  echo
fi

# --- addons ----------------------------------------------------------------
echo "## Addons gerenciados"
echo
echo "| Addon | Antes | Depois | Situação |"
echo "|---|---|---|---|"
ATUALIZADOS=0
for ad in $(printf '%s\n%s\n' "${!A_ADDON[*]}" "${!B_ADDON[*]}" | tr ' ' '\n' | sort -u); do
  [ -z "$ad" ] && continue
  a="${A_ADDON[$ad]:-}"; b="${B_ADDON[$ad]:-}"
  if [ -z "$a" ];   then echo "| \`$ad\` | — | $b | **adotado como gerenciado** |"; continue; fi
  if [ -z "$b" ];   then echo "| \`$ad\` | $a | — | **removido** |"; continue; fi
  if [ "$a" = "$b" ]; then
    echo "| \`$ad\` | $a | $b | sem mudança |"
  else
    echo "| \`$ad\` | $a | $b | **atualizado** |"
    ATUALIZADOS=$((ATUALIZADOS + 1))
  fi
done
echo
echo "$ATUALIZADOS addon(s) atualizado(s)."
echo
echo "### Componentes fora do addon manager"
echo
echo "Não aparecem nos snapshots e ninguém avisa quando ficam incompatíveis — declare o que"
echo "foi conferido (ALB controller, external-dns, cert-manager, ingress controller):"
echo
echo "<!-- preencher: componente | versão | compatível com a versão nova? -->"
echo

# --- prontidão -------------------------------------------------------------
echo "## Prontidão e pendências"
echo
if [ -n "$A_INSIGHT_RUINS" ]; then
  echo "Insights fora de \`PASSING\` **antes** da janela:"
  echo
  echo "$A_INSIGHT_RUINS" | sed '/^$/d;s/^/- /'
  echo
else
  echo "Antes da janela, todos os insights de \`UPGRADE_READINESS\` estavam \`PASSING\`."
  echo
fi
if [ -n "$B_INSIGHT_RUINS" ]; then
  echo "Insights fora de \`PASSING\` **depois** da janela — pendência aberta:"
  echo
  echo "$B_INSIGHT_RUINS" | sed '/^$/d;s/^/- /'
  echo
else
  echo "Depois da janela, todos os insights de \`UPGRADE_READINESS\` estão \`PASSING\`."
  echo
fi
if [ -n "$B_PDB" ]; then
  echo "PDBs sem folga no estado final (voltaram, como esperado, se um operator os recria):"
  echo
  for p in $B_PDB; do echo "- \`$p\`"; done
  echo
fi

# --- o que só a pessoa sabe ------------------------------------------------
cat <<'EOF'
## Janela

| | |
|---|---|
| Início (UTC) | <!-- preencher --> |
| Fim (UTC) | <!-- preencher --> |
| Executado por | <!-- preencher --> |
| Indisponibilidade percebida | <!-- preencher: houve? por quanto tempo? em qual serviço? --> |

## Ocorrências

<!-- preencher: o que não saiu como planejado, o que travou, o que precisou de --force,
     e o que foi feito. Se nada ocorreu, escrever "nenhuma" — ausência de seção lê-se
     como esquecimento, não como janela limpa. -->

## Verificação pós-upgrade

- [ ] Kubelets todos na versão alvo
- [ ] Node em cada AZ que tem volume EBS
- [ ] DNS resolvendo **de dentro de um pod**
- [ ] Nenhum pod em `Pending` ou `CrashLoopBackOff`
- [ ] Aplicações respondendo (verificado por quem usa, não só por métrica interna)

## Pendências

<!-- preencher: node group antigo ainda a deletar, addon deixado para a próxima janela,
     componente fora do addon manager a atualizar, próxima minor. -->
EOF
} > "$SAIDA"

echo "relatório gravado em $SAIDA"
