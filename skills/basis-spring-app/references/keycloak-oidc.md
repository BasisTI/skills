# Autenticação: Keycloak via OIDC

Padrão Basis pra apps web autenticadas. Keycloak no realm `basis`, fluxo OIDC com Spring Security, autorização por **client roles** (não realm roles).

## Dependências (pom.xml)

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-oauth2-client</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security</artifactId>
</dependency>
```

## Configuração yml — registration sempre se chama `keycloak`

```yaml
spring:
  security:
    oauth2:
      client:
        registration:
          keycloak:
            client-id: <app>-admin   # nome do client no realm
            client-secret: secret    # override por env: SPRING_SECURITY_OAUTH2_CLIENT_REGISTRATION_KEYCLOAK_CLIENT_SECRET
            scope: openid, profile, email
        provider:
          keycloak:
            issuer-uri: https://sso.apps.basis.com.br/realms/basis
```

Por que `keycloak`: nome curto, idêntico em todo projeto Basis. Spring Security cria o login URL automaticamente em `/oauth2/authorization/keycloak`.

## Constantes de role (`SecurityConstants.java`)

Roles ficam declaradas como constantes pra evitar typo:

```java
package br.com.basis.<app>.infrastructure;

public class SecurityConstants {
    public static final String ROLE_PREFIX = "ROLE_";
    public static final String USER_ROLE = "<APP>_USER";
    public static final String ADMIN_ROLE = "<APP>_ADMIN";
    public static final String[] ALL_ROLES = {USER_ROLE, ADMIN_ROLE};

    // Keycloak constants
    public static final String KC_RESOURCE_ACCESS_ATTR = "resource_access";
    public static final String KC_ROLES_ATTR = "roles";

    private SecurityConstants() {}
}
```

Convenção: roles prefixadas com nome curto da app (`KS_USER`, `KS_ADMIN`, `IH_USER`, etc.) — evita colisão entre apps que compartilham realm.

## SecurityConfig com mapeamento de client roles

Por padrão Spring Security usa **realm roles** do Keycloak. Pra mapear **client roles** (`resource_access.<clientId>.roles`), customize o `OidcUserService`:

```java
package br.com.basis.<app>.infrastructure;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.client.oidc.userinfo.OidcUserRequest;
import org.springframework.security.oauth2.client.oidc.userinfo.OidcUserService;
import org.springframework.security.oauth2.client.userinfo.OAuth2UserService;
import org.springframework.security.oauth2.core.oidc.user.DefaultOidcUser;
import org.springframework.security.oauth2.core.oidc.user.OidcUser;
import org.springframework.security.web.SecurityFilterChain;

import java.util.Collection;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import static br.com.basis.<app>.infrastructure.SecurityConstants.*;
import static org.springframework.security.oauth2.core.oidc.StandardClaimNames.PREFERRED_USERNAME;
import static org.springframework.security.oauth2.core.oidc.StandardClaimNames.SUB;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health/**", "/css/**", "/js/**",
                                 "/images/**", "/favicon.ico").permitAll()
                .requestMatchers("/**").hasAnyRole(ALL_ROLES)
                .anyRequest().authenticated()
            )
            .oauth2Login(oauth2 -> oauth2
                .userInfoEndpoint(userInfo -> userInfo
                    .oidcUserService(this.oidcUserService())
                )
            )
            .csrf(AbstractHttpConfigurer::disable);

        return http.build();
    }

    private OAuth2UserService<OidcUserRequest, OidcUser> oidcUserService() {
        OidcUserService delegate = new OidcUserService();

        return userRequest -> {
            OidcUser oidcUser = delegate.loadUser(userRequest);
            Set<GrantedAuthority> authorities = new HashSet<>(oidcUser.getAuthorities());

            Map<String, Object> resourceAccess = oidcUser.getAttribute(KC_RESOURCE_ACCESS_ATTR);
            String clientId = userRequest.getClientRegistration().getClientId();
            if (resourceAccess != null && resourceAccess.containsKey(clientId)) {
                @SuppressWarnings("unchecked")
                Map<String, Object> clientResource = (Map<String, Object>) resourceAccess.get(clientId);
                @SuppressWarnings("unchecked")
                Collection<String> roles = (Collection<String>) clientResource.get(KC_ROLES_ATTR);
                if (roles != null) {
                    authorities.addAll(roles.stream()
                        .map(r -> new SimpleGrantedAuthority(ROLE_PREFIX + r))
                        .toList());
                }
            }

            return new DefaultOidcUser(
                authorities,
                oidcUser.getIdToken(),
                oidcUser.getUserInfo(),
                oidcUser.hasClaim(PREFERRED_USERNAME) ? PREFERRED_USERNAME : SUB
            );
        };
    }
}
```

Pontos-chave:
- Permite `/actuator/health/**` e estáticos sem auth (probes K8s + assets)
- `hasAnyRole(ALL_ROLES)` autoriza só usuários com pelo menos uma role da app
- `oauth2Login` ativa fluxo OIDC redirect com Keycloak
- O `oidcUserService` customizado lê `resource_access.<clientId>.roles` (formato Keycloak para client roles), prefixa com `ROLE_` e adiciona ao `Authentication`
- `nameAttributeKey` = `preferred_username` quando disponível, senão `sub` — usa o login no `Principal#getName()`

## Por que client roles, não realm roles

| Aspecto | Realm roles | Client roles |
|---------|-------------|--------------|
| Escopo | Compartilhadas no realm `basis` | Isoladas por client (app) |
| Colisão | Roles `ADMIN` de apps diferentes se misturam | `<APP>_ADMIN` é claramente específico |
| Migração | Mudança numa app afeta todas | Cada app evolui independente |
| Mapping | Spring usa por padrão | Requer custom `OidcUserService` (acima) |

Padrão Basis: **client roles**.

## Configuração necessária no Keycloak

No realm `basis`, criar um Client com:
- Client ID: `<app>-admin` (ou `<app>-<componente>` se houver mais de um)
- Client authentication: ON (gera client-secret)
- Authentication flow: Standard flow (authorization code)
- Valid redirect URIs: `https://<app>.apps.basis.com.br/login/oauth2/code/keycloak`
- Em "Client roles": criar `<APP>_USER`, `<APP>_ADMIN`, etc.
- Atribuir roles aos usuários via "Users → <user> → Role mapping → Client roles → <client>"

## Override de secrets em prod

`spring.security.oauth2.client.registration.keycloak.client-secret` ← `SPRING_SECURITY_OAUTH2_CLIENT_REGISTRATION_KEYCLOAK_CLIENT_SECRET`

Vem do Secret K8s via `envFrom` ou `valueFrom.secretKeyRef`. Em dev, fica `secret` no yml (Keycloak local docker-compose).

## Checagem por role no template Thymeleaf

```html
<div sec:authorize="hasRole('<APP>_ADMIN')">
    <a href="/admin">Painel administrativo</a>
</div>
```

Requer `thymeleaf-extras-springsecurity6`:

```xml
<dependency>
    <groupId>org.thymeleaf.extras</groupId>
    <artifactId>thymeleaf-extras-springsecurity6</artifactId>
</dependency>
```
