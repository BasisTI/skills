# Classificar o que o SGO devolveu

A distinção entre "tenta de novo" e "não adianta" é o que separa um retry útil de um laço enchendo
o painel de quem opera — e, no sentido inverso, de um pedido perdido por um `502`.

## 1. A classificação é pelo corpo

Um `400` do Jira pode ser duas coisas opostas: **regra de negócio dele** (resposta legítima e
definitiva para aquele caso) ou **defeito seu de mapeamento** (que vai reprovar todas as chamadas
seguintes). Tratar os dois igual esconde o segundo atrás do primeiro.

E o Jira responde `200` com corpo de erro, o que faz do código HTTP um sinal ainda menos
confiável.

```json
{ "errorMessages": ["O CPF informado já está cadastrado."], "errors": {} }
{ "errorMessages": [], "errors": { "customfield_13757": "Field is required." } }
```

- **`errorMessages` presente** → regra de negócio, dirigida a quem usa. A mensagem do Jira é
  melhor que qualquer texto seu.
- **`errors` presente** → erro **por campo**, e erro por campo é **sempre defeito seu**: o
  usuário não escolhe em que customfield o valor dele vai.

## 2. A tabela

| Resposta | Natureza | Alerta | Mensagem ao usuário |
|---|---|---|---|
| `400` com `errorMessages` | permanente | não | **a do Jira** |
| `400` com `errors` por campo | permanente | **sim** | nenhuma (texto genérico) |
| `401` / `403` | **transitória** | **sim** | nenhuma |
| `404` | permanente | **sim** | nenhuma |
| `429` | transitória | não | nenhuma |
| `5xx` | transitória | não | nenhuma |
| timeout, conexão recusada, DNS | transitória | **sim** | nenhuma |
| `200` com corpo de erro | conforme o corpo (linhas 1–2) | | |
| `4xx` sem corpo interpretável | permanente | **sim** | nenhuma |
| falha antes de sair (payload não montou) | permanente | **sim** | nenhuma |

**`permanente` e `alertar` são eixos independentes.** Um `401` é transitório **e** merece alerta,
porque a credencial quebrou e nada vai passar até alguém agir. Um `400` com `errorMessages` é
permanente e não merece alerta nenhum — é o sistema funcionando.

**`401` como transitório é deliberado.** A credencial quebrou, alguém vai renová-la, e descartar
enquanto isso perde trabalho por problema de operação.

**Falha antes de sair não se retenta.** Se o payload não pôde ser montado — opção que o catálogo
não resolve, data que produz duração negativa — retentar não muda nada, e a entrada ficaria presa
na fila até estourar o teto sem ninguém saber por quê.

## 3. O que registrar, e o que nunca

```java
/// Só os nomes dos campos. O valor recusado é dado da pessoa, e este texto vai para o log.
private static String camposCom(JsonNode corpo) {
    List<String> campos = new ArrayList<>();
    corpo.path("errors").propertyNames().forEach(campos::add);
    return String.join(", ", campos);
}
```

- Nomeie **campos**, nunca valores.
- Na falha de rede, ponha a **mensagem da exceção** no motivo: `connection refused` e
  `read timed out` pedem providências diferentes, e o nome da classe sozinho não distingue. Ela
  é endereço e diagnóstico, não dado de ninguém.
- Na falha de **busca**, faça o contrário: **não** registre a mensagem. Um `400` por JQL
  malformada devolve a JQL no corpo, e a JQL pode ter dado pessoal dentro.

## 4. Quem classifica falha não pode falhar

O corpo nem sempre é JSON: HTML de proxy, página de erro do servidor de aplicação, resposta
truncada. O `catch` do parse é engolido de propósito.

```java
private @Nullable JsonNode interpretar(@Nullable String corpo) {
    if (corpo == null || corpo.isBlank()) return null;
    try {
        return mapper.readTree(corpo);
    } catch (RuntimeException e) {
        return null;   // não é JSON e não vai virar
    }
}
```

Use um mapeador **próprio** aqui: o que se lê é corpo de erro de terceiro, e a forma dele não
pode depender de como a sua aplicação serializa as respostas dela.

E a falha já classificada precisa atravessar o `throw` **sem ser reclassificada** — senão um
`200` com corpo de erro, ao ser repropagado, é lido pelo código HTTP e vira "deu certo". Uma
exceção própria carregando o veredito resolve.

## 5. Backoff

```java
Duration espera(int tentativasJaFeitas) {
    Duration espera = intervaloInicial;                    // 1m
    for (int i = 0; i < tentativasJaFeitas; i++)
        espera = espera.multipliedBy(fator);               // 2
    return espera;
}
```

Com 1 minuto e fator 2, seis tentativas cobrem pouco mais de uma hora — tempo suficiente para uma
indisponibilidade curta passar. **Os números são ponto de partida declarado**, não medição: sem
histórico de quedas reais não há como calibrá-los, e o lugar de ajustá-los é o yaml.

Contagem **por etapa**, não por saga: as três chamadas falham de forma independente, e uma que já
passou não deve consumir tentativa da seguinte.

## 6. Parar de tentar não é descartar

A distinção mais importante do estado, e a que costuma faltar no primeiro desenho:

| Estado | O que significa | O que quem opera faz |
|---|---|---|
| pendente, com próxima tentativa | está tentando sozinho | espera |
| pendente, **sem** próxima tentativa | acabaram as tentativas automáticas | resolve o impedimento e manda tentar de novo |
| descartado | falha permanente; não volta | comunica, ou corrige e recria |
| concluído | terminou | nada |

Esgotar o teto **mantém o registro guardado** e continua no estado anterior — o pedido não foi
recusado, ele parou. Descartar aqui diria a quem espera que foi recusado por um problema que é
seu.

Modelado como tipo selado, isso vira:

```java
public sealed interface SituacaoEnvio {
    record Pendente(Etapa etapa, int tentativas, boolean aguardandoIntervencao) implements SituacaoEnvio {}
    record Concluido(String chave, Instant em) implements SituacaoEnvio {}
    record Descartado(String motivo, @Nullable String mensagemAoUsuario) implements SituacaoEnvio {}
}
```

`aguardandoIntervencao` não estava no esboço da spec: apareceu ao implementar, porque "está
tentando sozinho" e "parou e espera alguém" pedem ações opostas de quem olha a lista, e sem o
campo os dois casos aparecem iguais.

## 7. A exceção da última etapa

Quando a saga tem uma etapa final que **não invalida o que já foi feito** — anexos numa
ocorrência que já está completa e utilizável —, falha permanente ali **não descarta**.

Descartar marcaria o pedido como recusado enquanto a ocorrência está na fila, funcionando; e uma
rotina de expurgo apagaria o dado depois, com o registro de pé no SGO. A etapa para de tentar e
espera intervenção, como quem esgota o teto.

É a única exceção à linha "permanente → descarta", e ela precisa estar escrita, porque parece
inconsistência para quem lê o código depois.

## 8. Alertar, quando não há canal de alerta

Sem canal montado, o alerta é um log em nível de erro — e isso é uma decisão, não uma omissão:

```java
if (falha.alertar()) {
    // O alerta é este log em nível de erro: não há canal montado, e inventar um aqui seria
    // infraestrutura escondida dentro de uma regra de negócio.
    log.error("Envio de {} exige atenção: {}", envio.candidatura(), falha.motivo());
}
```

O que aparece em produção, quando funciona, é isto:

```
ERROR ... EnvioSgoInterno : Envio de beca3328-… exige atenção: SGO recusou campos do payload (HTTP 400): customfield_13757
ERROR ... EnvioSgoInterno : Envio de 5140116e-… parou na etapa PENDENTE após 6 tentativas: SGO indisponível (HTTP 503)
```

Duas linhas, dois problemas diferentes, e as duas dizem o que fazer sem exigir que alguém abra o
código. A primeira é sua e urgente; a segunda é do SGO e espera.
