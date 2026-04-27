# Frontend build (Tailwind + DaisyUI + HTMX)

Padrão Basis pra apps web com Thymeleaf + HTMX + Tailwind v4 + DaisyUI. Build orquestrado por `frontend-maven-plugin`.

## Princípio: gerados não vão pra `src/`

Todo arquivo gerado pelo build (CSS compilado pelo Tailwind, JS vendored copiado do `node_modules`) escreve direto pra `target/classes/static/...`. Vai parar no jar via classpath, mas não polui o working tree nem o git.

Apenas `src/main/resources/static/images/` é versionado (assets manuais — logos, ícones).

## Layout

```
<app>-core/
├── pom.xml                              # com frontend-maven-plugin
├── package.json                         # build script
├── package-lock.json
├── src/
│   ├── frontend/
│   │   └── input.css                    # FONTE Tailwind/DaisyUI
│   └── main/
│       └── resources/
│           ├── static/
│           │   └── images/              # único subdir tracked aqui
│           └── templates/
│               └── monitoring/...html
└── target/
    └── classes/static/                  # gerado pelo build
        ├── css/style.css
        └── js/{htmx.min.js,list.min.js}
```

`input.css` fica em `src/frontend/` — fora do classpath. Se ficasse em `src/main/resources/`, o jar incluiria também o source não-compilado.

## `package.json`

```json
{
  "name": "<app>-frontend",
  "version": "0.1.0",
  "description": "Frontend build for <app> monitoring UI",
  "private": true,
  "scripts": {
    "build": "mkdir -p ./target/classes/static/css ./target/classes/static/js && tailwindcss -i ./src/frontend/input.css -o ./target/classes/static/css/style.css && npm run copy-js",
    "copy-js": "cp ./node_modules/htmx.org/dist/htmx.min.js ./target/classes/static/js/htmx.min.js && cp ./node_modules/list.js/dist/list.min.js ./target/classes/static/js/list.min.js"
  },
  "devDependencies": {
    "@tailwindcss/cli": "^4.0.0",
    "daisyui": "^5.5.9",
    "htmx.org": "^2.0.0",
    "list.js": "^2.3.1",
    "tailwindcss": "^4.0.0"
  }
}
```

Pontos:
- `mkdir -p` antes do tailwind: garante o destino antes do `generate-resources` (target/classes ainda não existe)
- Output dos vendored JS direto via `cp` — sem complicar com webpack/esbuild
- Sem aspas em `JAVA_TOOL_OPTIONS` em outros lugares — JVM trata diferente, evita

## `src/frontend/input.css`

```css
@import "tailwindcss";
@plugin "daisyui" {
  themes: light --default, dark --prefersdark, caramellatte;
}

@source "../main/resources/templates/<modulo>/**/*.html";

@theme {
  --color-basis-blue: #003366;
}

/* Customização HTMX */
.htmx-indicator { display: none; }
.htmx-request .htmx-indicator { display: flex; }
.htmx-request.htmx-indicator { display: flex; }
```

`@source` é relativo ao input.css — de `src/frontend/`, sobe 1 nível e desce até `src/main/resources/templates/`. Tailwind usa esse caminho pra detectar classes utilizadas e tree-shake o CSS final.

## `pom.xml`: frontend-maven-plugin

```xml
<properties>
    <node.version>v24.14.0</node.version>
</properties>

<build>
    <plugins>
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

Plugin baixa node localmente em `<app>-core/node/` (não usa node global do sistema). Roda `npm install` e `npm run build` na fase `generate-resources`, antes de `process-resources` que copia `src/main/resources/` pra `target/classes/`.

## `.gitignore`

```gitignore
# Node
node_modules/
node/

# Frontend gerado (Tailwind output + JS copiados do node_modules)
<app>-core/src/main/resources/static/*
!<app>-core/src/main/resources/static/images/
```

Padrão `static/*` ignora todos os arquivos diretamente em `static/`. Negação `!images/` reabre só esse subdir. Como kustomize ignora arquivos cujo parent foi excluído por nome simples, esse padrão funciona porque ignoramos com `*` (children), não `static/` (a pasta inteira).

## Como rodar local

```bash
cd <app>-core
mvn generate-resources       # gera CSS+JS em target/classes/static/
mvn spring-boot:run          # serve com os assets prontos
```

Pra desenvolvimento iterativo do CSS (watch mode), rodar tailwind separado em outro terminal:

```bash
cd <app>-core
npx tailwindcss -i ./src/frontend/input.css -o ./target/classes/static/css/style.css --watch
```

E garantir que o Spring Boot serve `target/classes/static` mesmo com hot-reload (devtools cuida disso).

## Anti-padrões

- **CSS gerado em `src/main/resources/static/`** — vira commit no git, conflitos de merge, polui PR
- **`input.css` em `src/main/resources/static/css/`** — entra no jar (fonte exposta no classpath)
- **`@source` apontando pra path absoluto** — quebra pra qualquer pessoa que clone em outro local
- **Usar Webpack/Vite/esbuild só pra copiar 2 JS** — overengineering; `cp` resolve
- **Esquecer `mkdir -p`** — Tailwind não cria parent dirs, build falha em primeira execução pós-`mvn clean`
