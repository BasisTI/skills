---
name: basis-relatorio-incidente
description: Gera ou revisa uma Nota de Incidente no padrão da equipe, em Jira wiki markup. Use quando o usuário pedir relatório/nota/postmortem de incidente, documentação de uma ocorrência, ou quiser padronizar uma nota já existente — inclusive a partir de logs, alertas de Watchdog, saídas de comando ou de uma conversa de investigação já feita. Também se aplica a incidentes de e-mail (mailcow, Postfix, Rspamd, fail2ban), rede e infraestrutura.
---

# Nota de Incidente

Padrão da equipe para documentar ocorrências no Jira. O formato existe para sustentar
avaliação CMMI-5: cada nota precisa ser **quantitativa** (métricas em vez de adjetivos),
**rastreável** (cronologia em UTC) e **verificável** (evidência de que a correção funciona,
não apenas a descrição do que foi mudado).

## Antes de escrever

Levante o material disponível: logs, alertas, saídas de comando, histórico da investigação.
Extraia os números você mesmo — contagens, IPs distintos, janelas de tempo — em vez de pedir
ao usuário o que dá para derivar dos dados.

Depois confira o que falta. Em geral o usuário tem os dados técnicos e **não** tem:

- horários das ações humanas (início da análise, momento da correção);
- responsáveis e prazos das pendências;
- confirmação de que a correção foi testada.

Não invente nenhum desses. Marque com `<preencher>` e diga ao usuário, no fim, o que
ficou pendente. Um horário de log é fato; um horário humano não comprovado é `(estimado)`.

Se a correção **não** foi verificada, não maquie: registre na seção de verificação que não
foi possível, explique por quê, e abra pendência para confirmar em condição real.

## Estrutura

Sem numeração de seções. Três `h2` fixos:

```
Nota de Incidente — <título curto do sintoma>

*Sistema afetado*:
*Data do incidente*:
*Detecção*:            automática (qual alerta) | manual (como foi percebido)
*Severidade*:          Baixa | Média | Alta | Crítica — + justificativa em uma linha
*Status*:              Em andamento | Resolvido | Resolvido / em observação

h2. Descrição e causa raiz
    h3. Resumo                    (obrigatório)
    h3. Impacto                   (obrigatório)
    h3. Cronologia                (obrigatório)
    h3. Descrição do incidente    (obrigatório)
    h3. Causa raiz                (obrigatório)
    h3. Evidências                (quando aplicável)
    h3. Recorrência               (obrigatório)

h2. Ações tomadas
    h3. Contenção                 (obrigatório)
    h3. Correção                  (obrigatório)
    h3. Verificação de eficácia   (obrigatório)

h2. Ações preventivas e próximos passos
    h3. Ações preventivas         (quando aplicável)
    h3. Pendências                (obrigatório)
    h3. Lições aprendidas         (obrigatório)
```

A chave da ocorrência no Jira é a referência da nota e o _reporter_ é quem a registrou —
**não** inclua campos de identificação ou de autoria no corpo.

Seção "(quando aplicável)" pode ser omitida, mas a ausência deve ser justificada em uma linha.

O texto completo do modelo, com a orientação de cada seção, está em
`references/template.txt` — copie a partir dele. Exemplo real preenchido em
`references/exemplo.txt`.

## Regras de conteúdo

**Resumo** — um a dois parágrafos, legíveis isoladamente: o que aconteceu, a causa raiz, o
que foi feito. Se houve ou não comprometimento/perda de dados, diga aqui e não só no fim.

**Impacto** — tabela. Sempre indisponibilidade, usuários afetados e perda de dados, mais as
métricas específicas do caso. Métrica zero se escreve `0`; métrica não levantada se escreve
`Não medido`. Nunca em branco — a diferença entre "é zero" e "não olhamos" é justamente o
que a auditoria procura.

**Cronologia** — tabela em UTC, do primeiro sinal à última ação. Deve permitir derivar tempo
de detecção e tempo de resolução sem cálculo adicional. É a seção que costuma revelar o
achado que ninguém tinha notado: um evento detectado dias antes de ser analisado indica que
existe detecção mas não existe **notificação** — são capacidades distintas, e essa lacuna
vira causa contribuinte e pendência.

**Descrição do incidente** — o relato técnico, sem conclusões de causa.

**Causa raiz** — a causa, não o sintoma. Se "por que isso foi possível?" ainda tem camada
abaixo, desça a camada. Separe `*Causa raiz*` (o que permitiu) de `*Causas contribuintes*`
(o que ampliou o impacto ou atrasou a detecção). Configuração padrão mal dimensionada é
causa raiz legítima — não é preciso haver erro humano.

**Evidências** — logs e saídas que sustentam a causa raiz. Explique qualquer coisa que possa
ser mal lida por quem revisa: um valor base64 num log de falha de autenticação, por exemplo,
pode parecer credencial exposta quando é só o _challenge_ do servidor.

**Contenção** — o que parou o efeito em curso, com horário. Contenção automática se registra
como tal; é resultado, não omissão.

**Correção** — mudança de parâmetro vai em tabela `||Item||Antes||Depois||`, nunca em prosa.
Registre também o que foi verificado e **não** precisou mudar: distingue "estava correto" de
"não foi olhado".

**Verificação de eficácia** — a prova, não a descrição. Comando executado depois da correção
e saída obtida. Se a condição original não é reproduzível, construa um teste sintético e
explique por que é equivalente: para bloqueio por remetente, o que importa é o envelope e não
o conteúdo, então um `.eml` sintético serve. Aponte na saída o sinal positivo **e** a ausência
do sinal que causava o problema — ambos comprovam.

**Ações preventivas** — o que reduz a classe do problema, não só esta ocorrência. Separado de
"Ações tomadas" para ser auditável em separado: correção tem evidência, prevenção tem prazo.

**Pendências** — tabela com responsável e prazo. Sem responsável não é pendência, é intenção.

**Lições aprendidas** — o que vale para além deste incidente, incluindo o que funcionou. Onde
o ganho veio de ajuste de configuração em vez de nova ferramenta, diga — é o cenário de melhor
custo-benefício e merece registro. "Nada a aprender" é resposta válida se justificada.

## Markup

Jira wiki markup, não Markdown: `h2.`/`h3.`, `*negrito*`, `_itálico_`, `{{mono}}`,
`||cabeçalho||`, `|célula|`, `{code}` para saída de máquina, `{noformat}` para sequências e
cronologias em texto puro. Escape asterisco dentro de mono como `{{\*@dominio}}`.

Evite `{panel}` e cores: o padrão precisa ser reproduzível por qualquer pessoa da equipe, e
markup elaborado degrada quando o cliente converte para HTML. Ênfase se faz com negrito.

## Erros a evitar

- Descrever a correção na seção de verificação. Verificação é o teste **posterior**.
- Adjetivos no lugar de números ("volume elevado" em vez de "~500 mensagens").
- Misturar recomendação com ação tomada.
- Afirmar que algo funciona sem ter exercitado — especialmente regra de bloqueio, que só se
  confirma quando o tráfego correspondente aparece de novo.
- Preencher horário humano por dedução.
