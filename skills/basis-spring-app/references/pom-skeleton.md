# pom.xml: skeleton multi-módulo Basis

Template padrão pra um app Basis com Maven multi-módulo, Spring Boot 4.x, Modulith, Jib pra imagens, frontend-maven-plugin opcional.

## Parent pom (raiz do repo)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>4.0.5</version>
        <relativePath/>
    </parent>

    <groupId>br.com.basis</groupId>
    <artifactId><app></artifactId>
    <version>0.0.1-SNAPSHOT</version>   <!-- Substituído por CalVer no CI -->
    <packaging>pom</packaging>

    <modules>
        <module><app>-domain</module>
        <module><app>-core</module>
        <module><app>-ingress</module>   <!-- opcional, se houver -->
    </modules>

    <properties>
        <java.version>25</java.version>
        <spring-modulith.version>2.0.5</spring-modulith.version>
        <spring-cloud.version>2025.1.1</spring-cloud.version>
        <testcontainers.version>1.21.4</testcontainers.version>
    </properties>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.springframework.modulith</groupId>
                <artifactId>spring-modulith-bom</artifactId>
                <version>${spring-modulith.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
            <dependency>
                <groupId>org.springframework.cloud</groupId>
                <artifactId>spring-cloud-dependencies</artifactId>
                <version>${spring-cloud.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
            <dependency>
                <groupId>br.com.basis</groupId>
                <artifactId><app>-domain</artifactId>
                <version>${project.version}</version>
            </dependency>
            <dependency>
                <groupId>org.testcontainers</groupId>
                <artifactId>testcontainers-bom</artifactId>
                <version>${testcontainers.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <build>
        <plugins>
            <!-- Garante que sub-módulos são instalados antes do reactor terminar
                 (necessário pra Jib resolver dependências entre módulos no mesmo build) -->
            <plugin>
                <artifactId>maven-install-plugin</artifactId>
                <executions>
                    <execution>
                        <id>install-during-verify</id>
                        <phase>verify</phase>
                        <goals><goal>install</goal></goals>
                    </execution>
                </executions>
            </plugin>
            <!-- Jib config compartilhada: imagem base, plataforma, user não-root -->
            <plugin>
                <groupId>com.google.cloud.tools</groupId>
                <artifactId>jib-maven-plugin</artifactId>
                <version>3.5.1</version>
                <configuration>
                    <skip>true</skip>           <!-- desliga no parent; ativa por módulo -->
                    <from>
                        <image>eclipse-temurin:25-jre-noble</image>
                        <platforms>
                            <platform>
                                <architecture>amd64</architecture>
                                <os>linux</os>
                            </platform>
                        </platforms>
                    </from>
                    <container>
                        <creationTime>USE_CURRENT_TIMESTAMP</creationTime>
                        <user>1000</user>      <!-- não rodar como root -->
                    </container>
                    <pluginExtensions>
                        <pluginExtension>
                            <implementation>com.google.cloud.tools.jib.maven.extension.springboot.JibSpringBootExtension</implementation>
                        </pluginExtension>
                    </pluginExtensions>
                </configuration>
                <dependencies>
                    <dependency>
                        <groupId>com.google.cloud.tools</groupId>
                        <artifactId>jib-spring-boot-extension-maven</artifactId>
                        <version>0.1.0</version>
                    </dependency>
                </dependencies>
            </plugin>
        </plugins>
    </build>
</project>
```

## Módulo `<app>-domain`

Pure Java, sem Spring runtime — eventos, value objects, exceções de domínio. Usado por `core` e `ingress`.

```xml
<dependencies>
    <!-- Modulith events module só -->
    <dependency>
        <groupId>org.springframework.modulith</groupId>
        <artifactId>spring-modulith-events-api</artifactId>
    </dependency>
</dependencies>
```

Não tem main class, não tem Spring Boot starter. Empacota como JAR comum.

## Módulo `<app>-core` (executável)

Stack típico de um app Basis web autenticado:

```xml
<dependencies>
    <!-- Domain interno -->
    <dependency>
        <groupId>br.com.basis</groupId>
        <artifactId><app>-domain</artifactId>
    </dependency>

    <!-- Spring Boot starters -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-actuator</artifactId>      <!-- OBRIGATÓRIO -->
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-jdbc</artifactId>     <!-- JDBC > JPA -->
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-thymeleaf</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-security</artifactId>      <!-- se autenticada -->
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-oauth2-client</artifactId> <!-- Keycloak -->
    </dependency>

    <!-- Modulith -->
    <dependency>
        <groupId>org.springframework.modulith</groupId>
        <artifactId>spring-modulith-starter-core</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.modulith</groupId>
        <artifactId>spring-modulith-starter-jdbc</artifactId>      <!-- event publisher -->
    </dependency>

    <!-- SCS -->
    <dependency>
        <groupId>org.springframework.cloud</groupId>
        <artifactId>spring-cloud-starter-stream-rabbit</artifactId>
    </dependency>

    <!-- DB driver + Flyway -->
    <dependency>
        <groupId>org.postgresql</groupId>
        <artifactId>postgresql</artifactId>
        <scope>runtime</scope>
    </dependency>
    <dependency>
        <groupId>org.flywaydb</groupId>
        <artifactId>flyway-database-postgresql</artifactId>
    </dependency>

    <!-- Tests -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-test</artifactId>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.springframework.modulith</groupId>
        <artifactId>spring-modulith-starter-test</artifactId>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>postgresql</artifactId>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>rabbitmq</artifactId>
        <scope>test</scope>
    </dependency>
</dependencies>

<build>
    <plugins>
        <plugin>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-maven-plugin</artifactId>
        </plugin>
        <!-- Jib: ativa neste módulo, herda config do parent, define imagem destino -->
        <plugin>
            <groupId>com.google.cloud.tools</groupId>
            <artifactId>jib-maven-plugin</artifactId>
            <configuration>
                <skip>false</skip>
                <to>
                    <image>basis-registry.basis.com.br/<app>/core</image>
                </to>
            </configuration>
        </plugin>
        <!-- frontend-maven-plugin SE houver build de frontend (Tailwind) -->
        <plugin>
            <groupId>com.github.eirslett</groupId>
            <artifactId>frontend-maven-plugin</artifactId>
            <version>2.0.0</version>
            <executions>
                <execution>
                    <id>install-node-and-npm</id>
                    <goals><goal>install-node-and-npm</goal></goals>
                    <configuration>
                        <nodeVersion>${node.version}</nodeVersion>
                    </configuration>
                </execution>
                <execution>
                    <id>npm-install</id>
                    <goals><goal>npm</goal></goals>
                    <configuration><arguments>install</arguments></configuration>
                </execution>
                <execution>
                    <id>build-frontend</id>
                    <goals><goal>npm</goal></goals>
                    <phase>generate-resources</phase>
                    <configuration><arguments>run build</arguments></configuration>
                </execution>
            </executions>
        </plugin>
    </plugins>
</build>
```

Ver [`frontend-build.md`](frontend-build.md) pra setup do `package.json`.

## Convenções

- Versão CalVer no CI: `mvn versions:set -DnewVersion=YYYY.MM.DD.<pipelineId>` (ver a skill `basis-k8s-deploy`, referência `dagger-pipeline-example.md`, no repo `basis-skills`)
- Versão local em desenvolvimento: `0.0.1-SNAPSHOT` no parent, herdado pelos filhos
- `<app>-domain` sem Spring runtime — força separação domínio/infra
- Jib é skipado no parent e ativado só nos módulos que viram imagem
- `maven-install-plugin` no `verify` é necessário pra Jib achar deps cross-module

## Anti-padrões

- **`spring-boot-maven-plugin` sem skip no parent** — tenta empacotar o pom como executável, falha
- **Jib `<skip>false</skip>` em `<app>-domain`** — não tem main class, build quebra
- **`spring-boot-devtools` em produção** — incluir só em dev profile via `<scope>provided</scope>` ou `<optional>true</optional>`
- **Esquecer `spring-boot-starter-actuator`** — probes K8s caem em 404 (ver [`actuator.md`](actuator.md))
