---
name: basis-skill-de-sessao
description: Converte o registro de uma sessão de agente em atualização de skill — seja skill nova, seja acréscimo a uma skill que já existe. Serve para sessão de incidente, de revisão de código, de planejamento e de debug. Use quando o usuário disser "vamos virar skill", "aproveitar aquela sessão", "documentar como a gente resolveu", "isso aqui devia estar na skill"; depois de uma revisão de MR que apontou padrão repetível; ou logo após fechar nota de incidente, quando o diagnóstico ainda está fresco. Também para revisar skill já escrita, conferindo se ela guarda os becos sem saída e não só o caminho feliz.
---

# Skill a partir de sessão

Uma sessão de agente registra o que a documentação final descarta: o **caminho**. As teorias
erradas, as ferramentas que mentiram, os comandos que não provaram nada, e as decisões de
projeto com o motivo ainda anexado. A nota de incidente guarda a causa raiz; o MR guarda o
diff aprovado. Como se chega neles partindo do sintoma só existe no transcript.

O sinal de que estamos perdendo esse material está no próprio repositório: a
`basis-relatorio-incidente` nasceu de uma sessão de incidente do mailcow e capturou apenas
a metade da escrita. O diagnóstico daquela investigação — o pivô de `whois` nos handles
RIPE, os indícios de registro fraudulento, o tuning do fail2ban — não virou skill nenhuma.

## Uma sessão rende vários destinos

**Este é o ponto que mais se erra.** A pergunta não é "que skill esta sessão vira", é "para
onde vai cada achado". Uma sessão só costuma produzir três ou quatro achados de naturezas
diferentes, e forçá-los numa skill só produz uma skill que não serve para ninguém.

Exemplo real, de uma sessão de planejamento no `ponto`:

| Achado | Destino |
|---|---|
| `@RestControllerAdvice` num app que serve HTML faz exceção de negócio injetar JSON no DOM | `basis-spring-app` — vale para qualquer app Spring nosso |
| Uma exceção própria mapeada no handler global vale mais que anotação por endpoint com lista de opt-out, que duplica o `SecurityConfig` | `basis-spring-app` |
| RLS é decorativa quando a aplicação conecta como dono da tabela: o Postgres não aplica policy ao dono sem `FORCE ROW LEVEL SECURITY` | Skill nova de multi-tenant — não existe hoje |
| Migration nova copiada da mais recente reintroduz vazamento, porque a `CREATE TABLE` mais nova era a sem RLS | Skill nova de multi-tenant |
| Cadastros de referência vão em `modulos.funcionario`, não em `configuracao` | `AGENTS.md` do repositório — decisão deste projeto |
| Ainda não existe tela de listagem no repositório | Nada. É estado do dia, não conhecimento |

**Esta skill produz rascunho, não versão final.** A extração é mecânica; o roteamento, a
generalização e a limpeza são humanos. Publicar o que sai daqui sem essas passadas é gerar
lixo em escala e vazar segredo junto.

## Fluxo

```
localizar → extrair dossiê → LIMPAR SEGREDO → rotear achados → generalizar → redigir → validar
                                    ↑                ↑
                          revisão humana        um destino por achado,
                            obrigatória         não um destino por sessão
```

## Tipos de sessão e o que cada um rende

| Tipo | Rende bem | Rende mal |
|---|---|---|
| **Incidente** | Conhecimento negativo, ferramentas que mentem, tabela de assinatura | Padrão de código |
| **Revisão de código** | Regra de padrão com o contraexemplo junto, lacuna nas skills atuais | Procedimento de diagnóstico |
| **Planejamento / arquitetura** | Critério de decisão com o porquê, armadilha estrutural | Comando, script |
| **Debug** | O primeiro salto que falha, o controle que separa causa de sintoma | Regra geral |

A sessão de **revisão de código** é a mais subestimada e a de melhor rendimento por linha.
Quando a revisão é feita contra as skills — *"revise o MR e verifique o que estiver fora das
skills basis"* — cada achado já nasce endereçado: ou o código violou uma regra que a skill
tem, e não há o que fazer; ou violou uma regra que a skill **deveria** ter, e isso é a
lacuna. Revisão desse tipo é o jeito mais barato de descobrir o que falta nas skills.

## 1. Localizar a sessão

Os transcripts ficam em `~/.claude/projects/<slug-do-cwd>/<sessionId>.jsonl`, um arquivo
JSONL por sessão. O `slug` é o caminho absoluto com `/` trocado por `-`. Para o Codex os transcripts ficam em
`~/.codex/sessions/<ano>/<mes>/<dia?/rollout-<timestamp>-<sessionId>.jsonl` para relacionar com o projeto pode
usar o cwd no `jsonl`.

```bash
scripts/extrair-sessao.py --listar               # tudo, mais recente primeiro
scripts/extrair-sessao.py --listar mailcow       # filtra por título ou diretório
```

A listagem usa o registro `ai-title`, que é o resumo que o próprio agente deu à sessão —
costuma ser o jeito mais rápido de achar a investigação certa. Confirme pelo diretório e
pela contagem de prompts antes de seguir.

Se o usuário não souber qual sessão foi, pergunte pelo sintoma e filtre por ele. Não
adivinhe: extrair a sessão errada custa uma rodada inteira de revisão.

## 2. Extrair o dossiê

```bash
scripts/extrair-sessao.py <sessionId|caminho.jsonl> -o dossie.md
```

Somente leitura. O dossiê separa o material em cinco partes:

| Seção do dossiê | Vira o quê |
|---|---|
| 1. Prompts do relator | A `description` de skill nova — as frases de gatilho |
| 2. Becos sem saída | Conhecimento negativo, em skill nova ou como acréscimo |
| 3. Comandos em ordem | O script de coleta de evidência |
| 4. Conclusões do agente | **A maior parte dos achados.** Tabela de assinatura em sessão de diagnóstico; regra, mecanismo e contraexemplo em sessão de revisão; critério de decisão em sessão de planejamento |
| 5. Arquivos tocados | O passo de correção, e em que camada |

Em sessão de revisão de código e de planejamento, a seção 4 é quase tudo — é onde estão as
conclusões já redigidas, com o porquê ainda anexado. As seções 2 e 3 rendem mais em sessão
de incidente e de debug.

Detalhe de leitura que importa: registros `user` no JSONL são **duas coisas** — prompt de
pessoa e resultado de ferramenta. Em 60 transcripts medidos, 13.848 eram saída de ferramenta
contra 1.177 prompts reais. O discriminador confiável é a ausência da chave `toolUseResult`;
o formato do `content` varia e não serve. O script já faz isso, mas quem for ler o transcript
a mão precisa saber. Detalhes em `references/formato-transcript.md`.

## 3. Limpar segredo — obrigatório, com revisão humana

```bash
scripts/varrer-segredos.sh dossie.md
```

Sai com 1 se houver achado de bloqueio: chave privada, `$ANSIBLE_VAULT`, JWT, PAT de GitLab
ou GitHub, credencial em URL, cabeçalho de autorização, certificado de kubeconfig,
atribuição de senha. Marca como revisão o que é dado interno sem ser segredo: hostname
`.basis.com.br`, IP privado, e-mail, caminho de casa, base64 longo.

**Saída limpa não é atestado.** Senha em prosa, nome de cliente e caminho de share interno
não têm forma reconhecível por regex. A leitura humana é obrigatória mesmo com varredura
zerada — o script pega o que tem forma, a pessoa pega o resto.

O julgamento é item a item, e o piloto do mailcow mostra por quê. A varredura acusou dois
e-mails:

- `abuseereport@gmail.com` — **fica**. O typo em `abusee` num abuse-mailbox de bloco /22 é
  justamente o indício de LIR fraudulento que a skill ensina a reconhecer. Remover destrói
  o ensinamento.
- `nupemec@envio.tjmt.jus.br` — **sai**. É endereço de cliente, acidente do ambiente,
  irrelevante para o diagnóstico.

Nenhum script decide essa diferença. Quando o valor for essencial ao ensinamento mas não
puder sair como está, troque por marcador: `<TOKEN>`, `<SENHA>`, `host.exemplo.interno`,
`203.0.113.10` (TEST-NET-3, reservada para documentação).

## 4. Rotear os achados

Liste os achados **antes** de decidir formato. Um achado é uma afirmação que sobrevive fora
daquele dia: uma regra, uma armadilha, um critério de decisão. Para cada um, o destino sai
de uma pergunta só — **para quem isso vale?**

| Vale para | Destino | Formato |
|---|---|---|
| Qualquer app Basis daquele tipo | Skill existente (`basis-spring-app`, `basis-java-code-standards`, `basis-k8s-deploy`, `basis-web-frontend`) | Acréscimo em seção existente |
| Uma classe de sistema sem skill nossa | Skill nova | Skill completa |
| Este repositório | `AGENTS.md` do projeto, com `CLAUDE.md` como symlink | Nota de decisão |
| Aquele dia | Nada | Descarta |

Duas armadilhas de roteamento:

**Não crie skill nova quando cabe acréscimo.** Skill nova custa instalação, entrada no
lockfile, sincronização em todos os repositórios e mais uma `description` competindo pelo
gatilho. Se o achado é sobre Spring e existe `basis-spring-app`, ele entra lá. Skill nova só
quando a classe de problema não tem casa — multi-tenant com RLS, por exemplo, não é assunto
da `basis-spring-app` nem da `basis-k8s-deploy`.

**Não empurre para a skill o que é decisão de projeto.** "Cadastros de referência vão em
`modulos.funcionario`" vale para este repositório, não para a Basis. Isso é `AGENTS.md`, e
misturar as duas coisas é como a skill começa a mentir para os outros projetos.

**Um MR por destino.** Uma sessão que rende três destinos rende três MRs, revisáveis por
pessoas diferentes e mergeáveis em ritmos diferentes. Juntar tudo num MR só obriga quem
revisa a opinar sobre Spring, sobre multi-tenant e sobre organização de módulo ao mesmo
tempo — e é assim que revisão vira carimbo.

## 5. Generalizar — a passada de domínio

O dossiê é N=1. Uma sessão descreve **um** caso, e skill que trata acidente específico como
regra é pior que skill nenhuma, porque dá confiança errada.

Antes de redigir, responda três perguntas com quem conhece o domínio:

1. **O que aqui é a classe do problema e o que é este caso?** O selector com typo é o caso;
   "Service dark com pods verdes" é a classe. A skill se organiza pela classe.
2. **O que faltou nesta sessão que a próxima vai encontrar?** É o que vira
   `references/<long-tail>.md`. Não sai do transcript — sai do conhecimento de quem revisa.
3. **O que era peculiaridade do ambiente naquele dia?** Versão, host, janela de manutenção.
   Sai, ou vira nota datada.

Se não houver ninguém para essa passada, entregue o rascunho marcado como rascunho. Não
publique.

## 6. Redigir

### Acréscimo em skill existente

O caso mais comum. O formato é o da skill de destino, não o desta. Regra prática: **uma
regra, um mecanismo, um contraexemplo** — nessa ordem, e curto.

```markdown
- **<A regra, em imperativo.>** <O mecanismo, uma frase — por que quebra, não que quebra.>
  <Contraexemplo real, reduzido ao mínimo que ainda mostra o problema.>
```

Regra sem mecanismo vira superstição; mecanismo sem contraexemplo não gruda. Achado de
revisão já traz os três — o código que violou está no diff, e o motivo está na conclusão do
agente.

Três cuidados:

- **Entre na seção que já trata do assunto.** Achado de tratamento de exceção vai onde a
  `basis-spring-app` já fala de web e erro, não numa seção nova no fim.
- **Verifique se contradiz o que já está escrito.** Se contradiz, o MR é de correção e o
  texto antigo sai — não se acumulam duas orientações opostas na mesma skill.
- **Lembre da propagação.** Mudança no canônico não chega sozinha ao lockfile de ninguém.
  Hoje são seis repositórios consumindo as skills, e cada um precisa de `skills update`.

### Skill nova

Anatomia completa, com modelo para copiar, em `references/anatomia-skill.md`. O resumo:

- **`description`** — o gatilho. Monte com as frases dos prompts do relator, não com
  vocabulário de documentação. Inclua **roteamento negativo** quando houver skill vizinha
  que confunde: "prefira esta à `X`, porque o sintoma que engana é justamente o que a `X`
  examina". É a parte que mais decide se a skill dispara na hora certa.
- **Os dois ou três hábitos que resolvem** — antes do procedimento. Vêm dos becos sem
  saída: o controle contra observação negativa, testar hipótese em vez de discutir.
- **Procedimento numerado**, com o passo de coleta de evidência primeiro.
- **Tabela de assinatura** sintoma → significado.
- **Conhecimento negativo em seção própria**: as ferramentas que mentem e como.
- **Fechamento**: prevenção, alerta que teria pego, e o que retirar do runbook.

Disciplina de saída, que também é economia de contexto: relatório abaixo de 30 linhas,
veredito de uma linha, saída bruta só se pedirem.

### Nota de decisão no `AGENTS.md` do projeto

Para o que vale só naquele repositório. Registre a decisão **com a alternativa recusada e o
motivo** — sem isso, a próxima pessoa reabre a discussão do zero, ou pior, desfaz a decisão
sem saber que era decisão. `CLAUDE.md` como symlink para o `AGENTS.md`, no padrão já usado
em `infraestrutura/ansible`.

## 7. Script de coleta de evidência

*Só quando o destino é skill de diagnóstico. Acréscimo de padrão de código não leva script —
leva regra e contraexemplo.*

A seção 3 do dossiê é a lista de comandos que a pessoa rodou. Procure o subconjunto que,
executado de uma vez, teria dado o mesmo veredito num passo só — esse é o script.

O salto de qualidade está em **converter falha de percepção humana em checagem mecânica**.
Não basta reimprimir a saída dos comandos: se durante a investigação alguém demorou a ver
algo, o script tem que mostrar esse algo já reconciliado. Comparar duas strings longas lado
a lado esconde um typo de um caractere; imprimir o valor procurado junto dos valores que
existem de fato torna o typo impossível de não ver.

Regras do script:

- **Read-only por padrão.** Mutação só depois de aprovação explícita, e num passo separado.
- **Declare o que muta** numa tabela no fim da skill, script a script.
- Sem `set -e` silencioso engolindo o diagnóstico; o erro do comando **é** o dado.
- Nada de caminho absoluto de máquina — é o risco de portabilidade já registrado.

Skill com script muda a conta do `allowed-tools`: passa a haver execução, e `read-only`
deixa de ser convenção para virar coisa a garantir por permissão e RBAC.

## 8. Correção na camada certa

*Só quando o destino é skill de diagnóstico.*

Se a sessão terminou em correção, a skill precisa dizer **onde** corrigir, e aqui o nosso
ambiente tem uma armadilha que a referência externa não tem.

Corrigir o objeto vivo estanca; corrigir o manifesto é o que permanece. Só que o
comportamento é **assimétrico entre ambientes**:

- **Produção** está com `selfHeal: true` — o ArgoCD reverte o `kubectl patch` em minutos,
  não no próximo deploy.
- **Staging** está com `selfHeal: false` — o patch sobrevive, mascara o problema e some na
  próxima sincronização.

O mesmo comando tem dois comportamentos. Skill de diagnóstico nossa que não diga isso
produz correção confiante e errada.

## 9. Validar antes de publicar

Sempre:

- [ ] `varrer-segredos.sh` sem bloqueio, e material lido por pessoa
- [ ] Cada achado tem **um** destino declarado, e o que não tem destino foi descartado por
      escrito — não deixado de fora em silêncio
- [ ] Nenhum achado de projeto foi empurrado para skill compartilhada
- [ ] Um MR por skill tocada

Skill nova:

- [ ] A `description` dispara nas frases do transcript, testada com uma delas literal
- [ ] Existe pelo menos um item de conhecimento negativo; se não houver, a sessão foi fácil
      demais para virar skill
- [ ] Scripts rodam em máquina limpa, sem caminho absoluto
- [ ] A skill diz o que **não** faz e para qual skill encaminhar
- [ ] Data de revisão no frontmatter — diagnóstico envelhece mais rápido que padrão de
      código, e a infraestrutura está migrando de vSphere para Proxmox

Acréscimo em skill existente:

- [ ] Entrou na seção que já trata do assunto, não numa seção nova no fim
- [ ] Tem regra, mecanismo e contraexemplo
- [ ] Não contradiz o que já estava escrito; se contradiz, o texto antigo saiu no mesmo MR
- [ ] A skill continua sincronizada nos repositórios que a consomem — mudança no canônico
      não chega sozinha ao lockfile de ninguém

## Erros a evitar

**Forçar a sessão numa skill só.** É o erro mais comum e o mais caro. Uma sessão rende
achados de naturezas diferentes, e enfiá-los no mesmo lugar produz skill que mistura regra
geral com decisão de projeto — e que passa a mentir para todo repositório que não é aquele.
Roteie antes de redigir.

**Criar skill nova quando cabia acréscimo.** Cada skill nova custa instalação, lockfile,
sincronização em seis repositórios e mais uma `description` disputando o gatilho. Se existe
casa para o achado, ele mora lá.

**Transcrever a sessão.** O dossiê não é a skill. A skill é a fração que generaliza, e ela
costuma ser pequena: uma investigação de duas horas vira uma página.

**Perder as frases do relator.** Reescrever "está dando connection refused" como "falha de
conectividade no serviço" destrói o gatilho. A skill passa a não disparar quando precisa.

**Guardar só o caminho feliz.** Se a skill não tem beco sem saída, ela não veio de sessão —
veio de memória depois do fato, e a próxima pessoa vai repetir a teoria errada inteira.

**Publicar rascunho como skill.** Sem a passada de generalização, o que sai é um incidente
fantasiado de procedimento.

**Achar que a varredura basta.** Ela pega forma, não sentido.

## Scripts

| Script | Muta? | Uso |
|---|---|---|
| `scripts/extrair-sessao.py --listar [termo]` | Não | Encontra a sessão pelo título ou diretório |
| `scripts/extrair-sessao.py <sessão> -o dossie.md` | Grava só o `-o` | Extrai o dossiê |
| `scripts/varrer-segredos.sh <arquivo>` | Não | Varre segredo; sai 1 se houver bloqueio |

`references/formato-transcript.md` — o esquema do JSONL, medido e não suposto: tipos de
registro, a armadilha do `user` duplo, onde ficam comando, resultado e erro.

`references/anatomia-skill.md` — a anatomia alvo com modelo para copiar, e o que cada seção
do dossiê alimenta.
