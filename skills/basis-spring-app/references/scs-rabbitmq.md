# Mensageria assíncrona: Spring Cloud Stream + RabbitMQ

Padrão Basis pra integração assíncrona via RabbitMQ usando Spring Cloud Stream (SCS) com bindings funcionais.

## Functional bindings

Cada consumer é um `Consumer<T>` ou `Function<T,U>` registrado como `@Bean`. SCS conecta automaticamente.

```java
@Bean
Consumer<Onboarding> onboarding(ProcessoService service) {
    return event -> service.processar(event);
}
```

Convenção de nome: `<beanName>-in-0` (consumer) / `<beanName>-out-0` (producer).

```yaml
spring:
  cloud:
    stream:
      function:
        definition: onboarding;emailCreation;offboarding
      bindings:
        onboarding-in-0:
          destination: identity-hub.onboarding   # exchange
          group: core                            # queue suffix → identity-hub.onboarding.core
        emailCreation-in-0:
          destination: identity-hub.email-creation
          group: core
```

A queue criada (ou consumida) tem o nome `<destination>.<group>`. O uso de `group` é obrigatório.

## K8s é dono da topologia em staging/production


### Configuração padrão

Filas, exchanges, DLX, DLQ, bindings, Policies → todos em CRDs do RabbitMQ Topology Operator.

SCS NÃO redeclara nada, `application.yml`:
```yaml
spring:
  cloud:
    stream:
      rabbit:
        bindings:
          default:
            consumer:
              bind-queue: false       # main exchange→main queue: K8s
              auto-bind-dlq: false    # DLX/DLQ/binding: K8s
```

Vantagens:
- Topologia versionada no repo de manifests, revisável
- Mudanças runtime via Policy (DLX, TTL, routing-key) sem delete+recreate
- Mesma topologia entre dev (se quiser) e prod

Ver `basis-k8s-deploy/references/rabbitmq-topology-pattern.md`.

### Configuração para dev local: SCS dono

SCS cria tudo automaticamente quando a app sobe, quando o perfil `dev` é ativado, `application-dev.yml`:

```yaml
spring:
  cloud:
    stream:
      rabbit:
        bindings:
          default:
            consumer:
              bind-queue: true        # main exchange→main queue: SCS
              auto-bind-dlq: true     # DLX/DLQ/binding: SCS
```

Defaults SCS quando `auto-bind-dlq: true`:
- DLX name: `<prefix>DLX` (default `DLX`) — pode ser overrideado por `dead-letter-exchange`
- DLX type: `direct` (NÃO configurável)
- DLQ name: `<queue>.dlq`
- DLQ binding routing-key: o `destination`
- Main queue ganha `x-dead-letter-exchange` + `x-dead-letter-routing-key` automaticamente

Doc: <https://docs.spring.io/spring-cloud-stream-binder-rabbit/reference/rabbit_overview/>

Vantagens:
- Zero infra extra em dev (só docker-compose com rabbit)
- Útil pra prototipagem e testes locais

Limitação: DLX é DIRECT (não topic) — múltiplos fluxos compartilhando DLX único só funcionam por causa do routing-key default = destination. Para ambiente dev local não é problema.

## Retry e DLQ

Spring AMQP retry no consumer (não confundir com SCS retry):

```yaml
spring:
  rabbitmq:
    listener:
      simple:
        retry:
          enabled: true
          initial-interval: 2000     # 2s
          multiplier: 4
          max-interval: 30000        # 30s
          max-retries: 4             # depois → DLQ
        default-requeue-rejected: false
```

Comportamento:
- Falha no consumer → SCS/AMQP tenta `max-retries` vezes com backoff exponencial
- Esgotou → mensagem é nack-ada → main queue dead-letters → DLX → DLQ correspondente
- Mensagem fica na DLQ até ser inspecionada/retried/expirar (TTL via Policy)

## Inspeção de DLQ + Retry manual

Padrão pra dar visibilidade ao admin:

```java
public interface DlqInspectionService {
    Map<String, Integer> contarPorDlq();
    List<DlqMensagemView> listar(String dlqName, int limit);
    List<DlqMensagemView> listarTodas(int limit);
}
```

Retry manual: republicar a mensagem na exchange original (preservando headers).

```java
public interface RetryService {
    void retryProcesso(UUID processoId, Optional<Long> dlqDeliveryTag);
}
```

Implementação base usa `RabbitTemplate.convertAndSend(exchange, "", payload, postProcessor)` com headers preservados.

## Anti-padrões

- **Sem `group`** em consumer-side — queue anonymous, mensagens perdidas em redeploy
- **DLX type=fanout no dev local** — SCS cria como direct e dá conflito na declaração
- **Mixing K8s + SCS topology** — type/args conflict no startup
- **Retry sem max** — loop infinito, DLQ nunca chega
- **`auto-bind-dlq: true` + topology K8s** — SCS tenta redeclarar DLX/DLQ, falha
