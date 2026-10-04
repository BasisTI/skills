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

Os dois temas da Basis usam Carlito e Inter Tight, servidas pelo app: acrescente
`@fontsource/carlito` e `@fontsource/inter-tight` às `devDependencies`, `target/classes/static/fonts`
ao `mkdir -p` e um `cp` dos `.woff2` ao `build`. O comando completo está em
[`tema-interno.md`](tema-interno.md#fontes-servidas-pelo-app).

Pontos:
- `mkdir -p` antes do tailwind: garante o destino antes do `generate-resources` (target/classes ainda não existe)
- Output dos vendored JS direto via `cp` — sem complicar com webpack/esbuild
- HTMX e List.js vêm do `node_modules` e são servidos pelo próprio app; o layout referencia `@{/js/htmx.min.js}`, nunca uma URL de CDN

## `src/frontend/input.css`

```css
@import "tailwindcss";
@plugin "daisyui" { themes: false; }   /* tira do bundle os temas embutidos */
@plugin "daisyui/theme" {
  name: "basis-interno";
  default: true;
  color-scheme: light;
  /* … tokens completos em basis-web-frontend/references/tema-interno.md … */
}

@source "../main/resources/templates/<modulo>/**/*.html";

@theme {
  --color-basis-navy: #071A2E;
  --color-basis-laranja: #F68B1F;
}

/* Customização HTMX */
.htmx-indicator { display: none; }
.htmx-request .htmx-indicator { display: flex; }
.htmx-request.htmx-indicator { display: flex; }
```

O `input.css` do tema interno também leva as fontes, as sobrescritas de contraste do DaisyUI,
o CSS do menu lateral e o da espera de tela: tudo em [`tema-interno.md`](tema-interno.md).

### Variante para app pública

App sem login troca o tema `basis-interno` pelo `basis-publico`, e o resto do arquivo fica
igual:

```css
@import "tailwindcss";
@plugin "daisyui";
@plugin "daisyui/theme" {
  name: "basis-publico";
  default: true;
  color-scheme: light;
  /* … tokens completos em basis-web-frontend/references/tema-publico.md … */
}

@source "../main/resources/templates/**/*.html";
```

Com `@import "tailwindcss" source(none);` no lugar da primeira linha, o Tailwind varre **só** o
que o `@source` aponta. Sem isso ele varre também a pasta do módulo inteira — `docs/`,
`.agents/`, planos em Markdown — e gera classe citada em texto: no colaboradados, exemplos
`text-base-content/60` de uma skill entravam no CSS e reprovavam o `ContrasteDoTemaTest`, e o
CSS caiu de ~304 KB para ~125 KB com o `source(none)` (TG-193). O preço é o caminho do `@source`
precisar estar certo: com o `source(none)`, um caminho errado gera um CSS sem as classes dos
templates em vez de um CSS que funciona por acaso.

Tema definido com `@plugin "daisyui/theme"` **não** entra na lista `themes:` do
`@plugin "daisyui"` — quem tenta declarar nos dois lugares recebe o tema padrão sem erro
nenhum, que é o modo de falha mais caro de perceber.

`@source` é relativo ao input.css — de `src/frontend/`, sobe 1 nível e desce até `src/main/resources/templates/`. Tailwind usa esse caminho pra detectar classes utilizadas e tree-shake o CSS final. Com o `input.css` em outro lugar o caminho muda: em `static/css/input.css` é `../../templates/**/*.html`. O colaboradados tinha `../templates/...` apontando para o vazio, e só funcionava porque o Tailwind varria o módulo inteiro.

**Comentário também gera classe.** O scanner lê qualquer palavra dos arquivos varridos, inclusive dentro de `<!-- -->` e `/* */`: "the new tab" num comentário do template faz o DaisyUI gerar o componente `.tab`.

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
- **HTMX/List.js por CDN** (`unpkg`, `cdnjs`) — app interno costuma rodar em rede fechada, e a tela quebra sem internet; além de colocar um terceiro no caminho de renderização. Vendorizar e versionar junto com o app
- **Tema fora do `input.css`** — o `basis-interno` e o `basis-publico` são blocos `@plugin "daisyui/theme"`; sem o bloco, o `data-theme` do layout não encontra o tema e a página cai no padrão do DaisyUI — sem erro de build, só a cor errada
- **Fonte da marca vinda de CDN** — em app pública, é requisição a terceiro carregando o IP de quem preenche o formulário; em app interna, rede fechada derruba a fonte. A fonte é servida pelo próprio app, como o resto
- **`/fonts/**` fora do `permitAll`** — a fonte cai na regra geral do `SecurityFilterChain`, e o usuário com um papel fora dela recebe 403 e vê a tela na fonte de sistema, sem erro
