# Carrega TAIGA_BASE_URL, TAIGA_USERNAME e TAIGA_PASSWORD de um arquivo de
# configuração para o shell atual, sem imprimir valor nenhum.
#
# Para ser LIDO com `source`, não executado (precisa exportar no shell que chama):
#   source scripts/taiga-env.sh <arquivo>
#
# Aceita as duas formas em que a credencial costuma estar:
#   - lista de ambiente de um compose.yaml:   - TAIGA_USERNAME=valor
#   - arquivo .env:                           TAIGA_USERNAME=valor
# Aspas simples ou duplas em volta do valor são removidas. Outras variáveis
# do arquivo são ignoradas.
#
# Qual arquivo usar nesta máquina vem do AGENTS.md ou de quem pediu. Nunca
# rode `cat`, `grep` sem filtro ou `env` para "conferir": isso põe a senha no
# log. Conferir é ver os nomes que este script lista.

_taiga_env_arquivo="${1:-}"
if [ -z "$_taiga_env_arquivo" ] || [ ! -r "$_taiga_env_arquivo" ]; then
  printf 'taiga-env: informe um arquivo legível (compose.yaml ou .env)\n' >&2
  unset _taiga_env_arquivo
  return 2 2>/dev/null || exit 2
fi

_taiga_env_carregadas=""
while IFS= read -r _taiga_env_linha || [ -n "$_taiga_env_linha" ]; do
  # tira "- " de lista YAML e espaços à esquerda
  _taiga_env_linha="${_taiga_env_linha#"${_taiga_env_linha%%[![:space:]]*}"}"
  _taiga_env_linha="${_taiga_env_linha#- }"
  case "$_taiga_env_linha" in
    TAIGA_BASE_URL=*|TAIGA_USERNAME=*|TAIGA_PASSWORD=*)
      _taiga_env_nome="${_taiga_env_linha%%=*}"
      _taiga_env_valor="${_taiga_env_linha#*=}"
      _taiga_env_valor="${_taiga_env_valor%\"}"; _taiga_env_valor="${_taiga_env_valor#\"}"
      _taiga_env_valor="${_taiga_env_valor%\'}"; _taiga_env_valor="${_taiga_env_valor#\'}"
      export "$_taiga_env_nome=$_taiga_env_valor"
      _taiga_env_carregadas="$_taiga_env_carregadas $_taiga_env_nome"
      ;;
  esac
done < "$_taiga_env_arquivo"

printf 'taiga-env: carregadas:%s\n' "${_taiga_env_carregadas:- nenhuma}" >&2
unset _taiga_env_arquivo _taiga_env_linha _taiga_env_nome _taiga_env_valor _taiga_env_carregadas
