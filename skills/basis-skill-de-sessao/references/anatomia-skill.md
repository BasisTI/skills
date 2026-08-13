# Anatomia de uma skill de diagnóstico

Esta página é para **skill nova de diagnóstico**. Para acréscimo em skill existente, que é
o caso mais frequente, o formato está na seção 6 do `SKILL.md` — regra, mecanismo,
contraexemplo, dentro da seção que já trata do assunto.

Modelo para copiar, com a justificativa de cada parte. A referência externa que fundamenta
esta anatomia é o `service-connectivity-triage` de
[`adamgordonbell/devops-agent-skills`](https://github.com/adamgordonbell/devops-agent-skills);
vale ler inteiro, inclusive o `references/failure-modes.md` e o script de coleta.

Proporção observada naquela skill: 182 linhas de `SKILL.md`, 148 de long tail e 336 de
script. **A maior parte do valor está fora do `SKILL.md`.**

## O modelo

````markdown
---
name: basis-<sistema>-triage
description: <uma frase do que diagnostica> — <os sintomas, nas palavras do relator>.
  Use quando alguém disser "<frase literal 1>", "<frase literal 2>"; quando <condição
  observável>. Prefira esta à `<skill-vizinha>` quando <distinção>, porque <o que engana>.
metadata:
  owner: <equipe>
  version: 0.1.0
  revisado-em: AAAA-MM-DD
  default-mode: read-only-until-approved
---

# <Título>

<A frase que reenquadra o problema. Uma ou duas linhas, dizendo por que a intuição
default falha aqui. É o parágrafo que faz a pessoa parar de seguir a teoria errada.>

## Quando usar

Alguém diz: "<frases literais do transcript>" — e <o estado que confunde>.

## Os hábitos que resolvem

**1. <Hábito>.** <Por que, com o mecanismo.>

**2. <Hábito>.** <Por que, com o caso concreto que o justifica.>

## Procedimento

### 1. Colete a evidência de uma vez

```bash
scripts/coletar-evidencia.sh <args>
```

<O que imprime e por que é melhor que improvisar comandos soltos.>

### 2. Confirme sondando o caminho

<Inferência não é prova. O que transforma uma na outra.>

### 3. Quando alguém apontar uma causa, teste — não discuta

<A observação do relator costuma ser real; a conclusão, não. Como testar em um comando.>

### 4. Leia a assinatura

| Observação | O que significa |
|---|---|
| <sintoma preciso, com código de saída ou tempo> | <causa> |

### 5. Corrija na camada certa

<Objeto vivo estanca; manifesto permanece. Atenção ao selfHeal do ArgoCD: em produção
está true e reverte o patch em minutos; em staging está false e o patch mascara.>

### 6. Verifique contra o sintoma relatado

<A métrica interna não é a do relator. Reproduzir a chamada original, na forma original.>

### 7. Feche o ciclo

- **Prevenção.** <O alerta que teria pego isto.>
- **Ferramenta que mente.** <O que retirar do runbook e o que usar no lugar.>
- **Achados fora do escopo.** Reportar como item separado, não misturar na causa raiz.

## Ferramentas que mentem

<Seção própria, porque é o que mais economiza tempo na próxima vez.>

## Scripts

| Script | Muta? | Uso |
|---|---|---|
| `scripts/coletar-evidencia.sh` | Não | Evidência num passo e veredito mecânico |
| `scripts/sondar-caminho.sh` | <declarar exatamente o que cria> | Achar o primeiro salto que falha |
````

## De onde vem cada parte

| Parte da skill | Seção do dossiê | Observação |
|---|---|---|
| `description` | 1. Prompts do relator | Copiar as frases, não traduzir |
| Reenquadramento | 4. Conclusões | Costuma já estar redigido |
| Hábitos | 2. Becos sem saída | O hábito é o antídoto do beco |
| Procedimento | 3. Comandos | Na ordem que funcionou, sem os desvios |
| Assinatura | 4. Conclusões | Precisa de sintoma preciso, não adjetivo |
| Ferramentas que mentem | 2. Becos sem saída | O item mais valioso do dossiê |
| Correção | 5. Arquivos tocados | Dizer a camada, não só o comando |
| Long tail | **Nenhuma** | Vem da passada de generalização |

A última linha é a que mais se esquece: o long tail **não sai do transcript**. Uma sessão
cobre um caso. As outras dez formas de o mesmo sintoma aparecer vêm de quem conhece o
domínio, na segunda passada.

## O que separa skill boa de procedimento transcrito

**Sintoma preciso, não adjetivo.** "Conexão falha instantaneamente, `curl` saindo com 7 e
`connect=0.000s`" é acionável. "Serviço lento" não é.

**Percepção humana virando checagem mecânica.** Se na investigação alguém demorou a ver
algo, o script tem que mostrar isso já reconciliado — o valor procurado impresso ao lado
dos valores que existem de fato, para que a discrepância salte. Reimprimir saída crua
repete a dificuldade original.

**Roteamento negativo na `description`.** Dizer a qual skill vizinha **não** ir, e por quê.
Sem isso, a skill errada dispara justamente no caso confuso.

**Declarar o que muta.** Tabela de scripts com a coluna de mutação, e aprovação explícita
antes de qualquer alteração. `default-mode: read-only-until-approved` no frontmatter é
convenção seguida pela skill, não sandbox garantido pelo runtime — os freios reais são o
próprio script, as permissões do agente e o RBAC.

**Limite de saída.** Relatório abaixo de 30 linhas, veredito de uma linha, saída bruta só
sob pedido. Vale por legibilidade e por consumo de contexto.
