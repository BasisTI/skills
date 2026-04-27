# Actuator (obrigatório)

Spring Boot Actuator é **obrigatório** em toda app Basis — é como K8s sabe que a app está viva e pronta pra receber tráfego.

## Dependência (pom.xml)

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

Sem essa dep, os endpoints `/actuator/health/liveness` e `/actuator/health/readiness` retornam 404 — as probes do K8s falham e o pod entra em crash loop.

## Endpoints essenciais (auto-configurados)

Quando o starter está no classpath, Spring Boot expõe por padrão:

- `GET /actuator/health` — status global (UP/DOWN agregado)
- `GET /actuator/health/liveness` — usado pelo `livenessProbe` do K8s
- `GET /actuator/health/readiness` — usado pelo `readinessProbe` do K8s
- `GET /actuator/info` — info estática

As probes `liveness` e `readiness` são auto-habilitadas quando Spring Boot detecta ambiente Kubernetes (variáveis `KUBERNETES_SERVICE_HOST`).

Em dev local, pode forçar:
```yaml
management:
  endpoint:
    health:
      probes:
        enabled: true
      show-details: always   # opcional, mostra status de cada HealthIndicator
```

## Health groups (liveness vs readiness)

- **Liveness**: a aplicação está rodando? Falha → K8s mata e restarta o pod. NÃO incluir checks de dependências externas (DB, Rabbit) — uma indisponibilidade temporária do banco não deve matar o pod.
- **Readiness**: a aplicação está pronta pra receber requests? Falha → K8s tira do load balancer. Incluir DB, Rabbit, etc. — se DB cai, o pod fica vivo mas para de receber tráfego.

Spring Boot já agrupa corretamente por padrão (DB e Rabbit indicators ficam em readiness). Custom indicators que escrevem em sistemas externos: anotar com `@Component` e Spring inclui automaticamente em readiness.

Override explícito (raro):
```yaml
management:
  endpoint:
    health:
      group:
        readiness:
          include: db, rabbit, ldap
```

## Integração com deployment K8s

```yaml
livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: http
  initialDelaySeconds: 30
  periodSeconds: 20
readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
```

`initialDelaySeconds: 30` — espera o Spring Boot terminar de inicializar antes de começar a probar (evita flapping no startup).

## Segurança

Actuator endpoints precisam ser permitidos antes do `authenticated()` no SecurityConfig (pra K8s conseguir chamar sem token):

```java
.authorizeHttpRequests(auth -> auth
    .requestMatchers("/actuator/health/**").permitAll()
    .requestMatchers("/**").hasAnyRole(ALL_ROLES)
)
```

Outros endpoints actuator (`/actuator/metrics`, `/actuator/info`, etc.) por default só expõem `health` e `info` via web. Pra expor mais (ex: prometheus):

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health, info, prometheus, metrics
```

## Métricas Prometheus (opcional, recomendado)

Adicionar:
```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

Endpoint `/actuator/prometheus` fica disponível. Configurar scrape no Prometheus do cluster apontando pro service da app.

## Anti-padrões

- **App sem actuator + probe configurada no K8s** — pod em crash loop forever, deploy falha silencioso (probe sempre 404)
- **Liveness incluindo dependências externas** — flap de DB derruba a app inteira (mata pod, perde estado em memória, perde conexões SCS)
- **Expor `*` em web.exposure.include** — vaza endpoints sensíveis (`/actuator/env`, `/actuator/heapdump`) sem auth se SecurityConfig permite `permitAll()` em `/actuator/**`
- **`/actuator/**` permitAll** — só `/actuator/health/**` deve ser público; resto requer auth
