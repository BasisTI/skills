#!/usr/bin/env bash
# Reconcilia, numa tela só, as condições que precisam ser verdadeiras ao mesmo tempo
# para o isolamento multi-tenant por RLS existir de fato.
#
#   verificar-isolamento.sh <container> <db> <role-dona> <role-app>
#
# Somente leitura: consulta catálogo do Postgres, não altera nada.
#
# Existe porque cada peça, olhada isolada, parece certa. As policies aparecem no `\d`,
# a role existe, a coluna tenant_id está lá — e mesmo assim vaza, porque a app conecta
# como dona. O valor deste script é imprimir as peças juntas, já confrontadas.

set -uo pipefail

[ $# -eq 4 ] || {
  echo "uso: $(basename "$0") <container> <db> <role-dona> <role-app>" >&2
  echo "ex.: $(basename "$0") basis-ponto-postgres basis_ponto_db ponto ponto_app" >&2
  exit 2
}

CONTAINER=$1
DB=$2
DONA=$3
APP=$4

psql_q() { docker exec "$CONTAINER" psql -U "$DONA" -d "$DB" -X -tAF'|' -c "$1" 2>&1; }

docker exec "$CONTAINER" true 2>/dev/null || {
  echo "container '$CONTAINER' não responde" >&2; exit 2
}

problemas=0

echo "══ role da aplicação: $APP"

linha=$(psql_q "SELECT rolname, rolsuper, rolbypassrls FROM pg_roles WHERE rolname = '$APP';")
if [ -z "$linha" ]; then
  echo "  🔴 a role '$APP' não existe — a aplicação está conectando como outra coisa"
  problemas=$((problemas + 1))
else
  IFS='|' read -r _ super bypass <<< "$linha"
  if [ "$super" = "t" ]; then
    echo "  🔴 é SUPERUSER — escapa de toda policy, inclusive com FORCE"
    problemas=$((problemas + 1))
  else
    echo "  🟢 não é superuser"
  fi
  if [ "$bypass" = "t" ]; then
    echo "  🔴 tem BYPASSRLS — escapa de toda policy"
    problemas=$((problemas + 1))
  else
    echo "  🟢 não tem BYPASSRLS"
  fi
fi

donas=$(psql_q "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname='public' AND c.relkind='r' AND pg_get_userbyid(c.relowner) = '$APP';")
if [ "${donas:-0}" != "0" ]; then
  echo "  🔴 é dona de $donas tabela(s) — o Postgres não aplica policy ao dono sem FORCE"
  problemas=$((problemas + 1))
else
  echo "  🟢 não é dona de nenhuma tabela"
fi

echo
echo "══ tabelas com coluna tenant_id"

tabelas=$(psql_q "
  SELECT c.relname,
         c.relrowsecurity,
         c.relforcerowsecurity,
         pg_get_userbyid(c.relowner),
         (SELECT count(*) FROM pg_policies p WHERE p.schemaname='public' AND p.tablename=c.relname)
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r'
     AND EXISTS (SELECT 1 FROM information_schema.columns col
                  WHERE col.table_schema='public' AND col.table_name=c.relname
                    AND col.column_name='tenant_id')
   ORDER BY 1;")

if [ -z "$tabelas" ]; then
  echo "  nenhuma tabela com tenant_id — este banco não é single-table multi-tenant"
else
  printf '  %-28s %-4s %-6s %-8s %s\n' TABELA RLS FORCED POLICIES DONO
  while IFS='|' read -r nome rls forced dono npol; do
    [ -n "$nome" ] || continue
    marca="🟢"
    if [ "$rls" != "t" ] || [ "$forced" != "t" ] || [ "$npol" = "0" ]; then
      marca="🔴"; problemas=$((problemas + 1))
    fi
    printf '  %s %-26s %-4s %-6s %-8s %s\n' "$marca" "$nome" "$rls" "$forced" "$npol" "$dono"
  done <<< "$tabelas"
fi

echo
echo "══ policies que existem e não isolam"

# Contar policy não basta: `USING (true)` conta como 1 e permite tudo. É o achado
# que a leitura do `\d` e a contagem ingênua deixam passar — por isso a inspeção
# olha a expressão, não a quantidade.
abertas=$(psql_q "
  SELECT tablename || ' / ' || policyname || ' → ' || coalesce(qual, '(sem USING)')
    FROM pg_policies
   WHERE schemaname='public'
     AND (qual IS NULL OR btrim(qual) = 'true');")

if [ -n "$abertas" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    echo "  🔴 $p"
    echo "       policy permissiva sem predicado — conta como policy e não filtra nada"
    problemas=$((problemas + 1))
  done <<< "$abertas"
else
  echo "  🟢 nenhuma"
fi

echo
echo "══ policies sem missing_ok (quebram o fluxo pré-autenticação)"

frageis=$(psql_q "
  SELECT tablename || ' / ' || policyname
    FROM pg_policies
   WHERE schemaname='public'
     AND qual LIKE '%current_setting%'
     AND qual NOT LIKE '%, true)%';")

if [ -n "$frageis" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    echo "  🔴 $p — current_setting sem missing_ok lança erro com a variável indefinida"
    problemas=$((problemas + 1))
  done <<< "$frageis"
else
  echo "  🟢 nenhuma"
fi

echo
echo "══ policies pré-autenticação (buracos deliberados — confira o alcance)"

# Policies permissivas são OR: uma que casa com "tenant indefinido" abre a tabela
# inteira para todo caminho que esqueceu de definir o contexto.
preauth=$(psql_q "
  SELECT tablename || ' / ' || policyname || ' → ' || coalesce(qual, '')
    FROM pg_policies
   WHERE schemaname='public'
     AND permissive = 'PERMISSIVE'
     AND qual LIKE '%IS NULL%'
     AND qual LIKE '%current_setting%';")

if [ -n "$preauth" ]; then
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    echo "  🟡 $p"
  done <<< "$preauth"
  echo "       policies permissivas se somam (OR). Sem tenant definido, a tabela"
  echo "       inteira fica visível — inclusive para código que só esqueceu o contexto."
else
  echo "  🟢 nenhuma"
fi

echo
echo "══ tabelas sem tenant_id (confira se alguma deveria ter)"
psql_q "
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname)
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r'
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns col
                      WHERE col.table_schema='public' AND col.table_name=c.relname
                        AND col.column_name='tenant_id');" | sed 's/^/  /'
echo "  ↑ varredura de RLS não enxerga tabela que deveria ter tenant_id e não tem."

echo
echo "─────────────────────────────────────────────"
if [ "$problemas" -gt 0 ]; then
  echo "🔴 $problemas problema(s). O isolamento NÃO está garantido pelo banco."
  exit 1
fi

echo "🟢 Estrutura correta. Falta a prova de comportamento, que este script não faz:"
echo
echo "   docker exec -e PGPASSWORD=<senha> $CONTAINER psql -U $APP -d $DB -X \\"
echo "     -c \"SELECT count(*) FROM <tabela>;\" \\"
echo "     -c \"SET app.current_tenant='1'; SELECT count(*) FROM <tabela>;\" \\"
echo "     -c \"SET app.current_tenant='2'; INSERT INTO <tabela> (tenant_id, ...) VALUES (1, ...);\""
echo
echo "   esperado: 0 sem erro · só o tenant 1 · new row violates row-level security policy"
