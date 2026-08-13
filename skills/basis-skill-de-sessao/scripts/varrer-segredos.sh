#!/usr/bin/env bash
# Varre um dossiê de sessão atrás de segredo e de dado interno antes da publicação.
#
#   varrer-segredos.sh <arquivo> [arquivo...]
#
# Somente leitura: aponta, não corrige. Sai com 1 se houver achado de bloqueio.
#
# A varredura NÃO substitui a leitura humana. Ela pega o que tem forma reconhecível;
# senha em português no meio de uma frase, nome de cliente e caminho de share interno
# não têm forma. Por isso o passo humano é obrigatório mesmo com saída limpa.

set -uo pipefail

[ $# -ge 1 ] || { echo "uso: $(basename "$0") <arquivo> [arquivo...]" >&2; exit 2; }

bloqueios=0
revisoes=0

# nome|severidade|regex estendida
PADROES=(
  'chave privada|BLOQUEIA|BEGIN [A-Z ]*PRIVATE KEY'
  'ansible-vault|BLOQUEIA|\$ANSIBLE_VAULT;'
  'JWT|BLOQUEIA|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  'PAT do GitLab|BLOQUEIA|glpat-[A-Za-z0-9_-]{16,}'
  'PAT do GitHub|BLOQUEIA|gh[pousr]_[A-Za-z0-9]{16,}'
  'chave AWS|BLOQUEIA|AKIA[0-9A-Z]{16}'
  'token Slack|BLOQUEIA|xox[baprs]-[A-Za-z0-9-]{10,}'
  'credencial em URL|BLOQUEIA|[a-zA-Z][a-zA-Z0-9+.-]*://[^/[:space:]:]+:[^/[:space:]@]+@'
  'cabeçalho de autorização|BLOQUEIA|[Aa]uthorization: *(Bearer|Basic) +[A-Za-z0-9._~+/=-]{8,}'
  'certificado em kubeconfig|BLOQUEIA|client-(certificate|key)-data:'
  'atribuição de senha ou token|BLOQUEIA|(senha|password|passwd|secret|token|api[_-]?key)["'"'"' ]*[:=][ "'"'"']*[^ "'"'"'<>,;)]{6,}'
  'hostname interno|REVISAR|[A-Za-z0-9_-]+\.basis\.com\.br'
  'IP privado|REVISAR|(^|[^0-9.])(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)[0-9]{1,3}\.[0-9]{1,3}'
  'e-mail|REVISAR|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
  'caminho de casa|REVISAR|/home/[a-z][a-z0-9_-]*/'
  'bloco base64 longo|REVISAR|[A-Za-z0-9+/]{80,}={0,2}'
)

for arquivo in "$@"; do
  [ -f "$arquivo" ] || { echo "não é arquivo: $arquivo" >&2; exit 2; }
  echo "══ $arquivo"
  achou_algo=0

  for entrada in "${PADROES[@]}"; do
    IFS='|' read -r nome severidade regex <<< "$entrada"
    mapfile -t hits < <(grep -nEo "$regex" "$arquivo" 2>/dev/null | head -8)
    # grep -c imprime 0 e sai com 1 quando não casa; capturar sem deixar o status abortar
    total=$(grep -cE "$regex" "$arquivo" 2>/dev/null) || true
    total=${total:-0}
    [ "$total" -eq 0 ] && continue
    achou_algo=1

    if [ "$severidade" = "BLOQUEIA" ]; then
      bloqueios=$((bloqueios + 1))
      marca="🔴 BLOQUEIA"
    else
      revisoes=$((revisoes + 1))
      marca="🟡 REVISAR "
    fi

    echo "  $marca $nome — $total ocorrência(s)"
    for h in "${hits[@]}"; do
      linha="${h%%:*}"
      trecho="${h#*:}"
      if [ "$severidade" = "BLOQUEIA" ]; then
        # o relatório da varredura também é um artefato: mascarar o valor, porque
        # senão a saída vira o mesmo vazamento que o script existe para impedir
        trecho="${trecho:0:12}…[mascarado, ${#trecho} caracteres]"
      elif [ ${#trecho} -gt 42 ]; then
        trecho="${trecho:0:42}…"
      fi
      echo "      linha $linha: $trecho"
    done
    [ "$total" -gt 8 ] && echo "      … e mais $((total - 8))"
  done

  [ "$achou_algo" -eq 0 ] && echo "  nenhum padrão conhecido encontrado"
  echo
done

echo "─────────────────────────────────────────────"
echo "bloqueios: $bloqueios · revisões: $revisoes"
echo
if [ "$bloqueios" -gt 0 ]; then
  echo "🔴 NÃO PUBLIQUE. Remova os achados de bloqueio e rode de novo."
  echo "   Se o valor for essencial ao ensinamento, substitua por marcador:"
  echo "   <TOKEN>, <SENHA>, host.exemplo.interno, 203.0.113.10 (TEST-NET-3)."
  exit 1
fi
if [ "$revisoes" -gt 0 ]; then
  echo "🟡 Sem bloqueio, mas há dado interno. Decida item a item o que é essencial"
  echo "   ao ensinamento e o que é acidente do ambiente — este é o passo humano."
fi
echo
echo "Saída limpa não é atestado. Senha em prosa, nome de cliente e caminho de share"
echo "interno não têm forma reconhecível. Leia o material antes de publicar."
