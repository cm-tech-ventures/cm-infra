# ADR-004 — Política de revisão de diff (matriz de pares, paths sensíveis, severidade)

- **Status:** Accepted
- **Data:** 2026-08-04
- **Autor / dono:** CTO / Arquiteto
- **Issue:** CMV-399
- **Bloqueia:** CMV-398 (gate de revisão de diff — implementação do workflow pelo PlatformEngineer)
- **Contexto-fonte:** Decisão do board em 2026-08-04; levantamento de restrições do GitHub Free na CMV-398

> **Critério de sucesso deste ADR:** o PlatformEngineer implementa o workflow de revisão
> e o reviewer agent executa `/code-review` **lendo só este documento**. Onde este ADR
> contradiz sugestões anteriores, **o ADR vence**.

---

## 1. Contexto

Até 2026-08-04, nenhum diff era lido antes de entrar em `main` nos repos da CM Ventures — os
8 PRs do `cm-crm` foram todos self-merge sob a política provisória de 2026-07-20. O board
decidiu introduzir revisão obrigatória de diff como gate no fluxo de desenvolvimento.

### 1.1 Restrições verificadas (não são hipóteses)

| Restrição | Detalhe |
|---|---|
| **Mesma conta GitHub** | Todos os 9 agentes operam sob `cadusds2` (20/20 commits verificados). O GitHub proíbe aprovar o próprio PR — logo `CODEOWNERS` e *require approvals* nativos **não funcionam**. |
| **Branch protection bloqueada** | HTTP 403 em todos os repos privados (org + conta pessoal): plano Free não suporta rulesets nem branch protection. |
| **Plano gratuito permanente** | Decisão de board: a solução **não** pode depender de GitHub Pro/Team, nem de tornar repo público para destravar rulesets. O enforcement é o **check vermelho** no PR somado à política escrita nos `AGENTS.md`. |
| **Revisor roda na sessão do agente par** | O gate usa `/code-review` no Paperclip — custo na assinatura Claude já paga, sem `ANTHROPIC_API_KEY` adicional. |

### 1.2 Repos em escopo

**Org `cm-tech-ventures` (privados):**
- `cm-crm`, `cm-identity`, `cm-mcp`, `cm-sdk`, `cm-service-template`, `cm-analytics`

**Org `cm-tech-ventures` (público):**
- `cm-infra`

**Conta pessoal `cadusds2`:**
- `md-backend`, `md-frontend`, `sys-bjj-backend`

**Conta `matheusnaziel`:**
- `sys-bjj-frontend`

---

## 2. Decisão

### 2.1 Mecanismo de enforcement

O gate é implementado como um **GitHub Actions workflow** disparado em `pull_request`. Ele:

1. Inspeciona os paths modificados no PR.
2. Determina o revisor par conforme a Seção 2.2.
3. Acorda o revisor via Paperclip API com o prompt de `/code-review`.
4. Publica o resultado como **status check** (`reviewer-gate`) no commit do PR.
5. O status check falha (vermelho) se houver achado bloqueante; passa (verde) caso contrário.

O merge fica bloqueado **por política** (não por branch protection) enquanto o check estiver
vermelho. Como não há branch protection disponível no plano Free, o sinal de enforcement é
visual + normativo: o check vermelho é evidência de violação e o `AGENTS.md` proíbe merge
com check vermelho. Qualquer merge de PR com check vermelho é registrado como incidente de
governança e reportado ao board no próximo heartbeat do CTO.

### 2.2 Matriz de pares

| Autor do PR | Revisor par |
|---|---|
| BackendCore | IntegrationsEngineer |
| IntegrationsEngineer | BackendCore |
| VerticalMD | VerticalBJJ |
| VerticalBJJ | VerticalMD |
| DataEngineer | BackendCore |
| PlatformEngineer | CTO |
| CTO | PlatformEngineer |
| CEO | CTO |
| *(qualquer agente)* | **CTO** (override, ver §2.3) |

Regra: nenhum agente revisa a si mesmo. A matriz é simétrica por default.

### 2.3 Override de roteamento para o CTO

O revisor é **sempre o CTO**, independentemente da matriz de pares, quando o diff toca:

- Qualquer arquivo de contrato OpenAPI (`schema.yml`, `openapi.yml`, `**/*.yaml` na pasta `docs/api/`).
- Qualquer arquivo sob `cm-sdk/` (SDK consumido por todas as verticais — regressão propaga).
- Qualquer modificação de escopo ou chave em `cm-identity/`.
- Fronteiras entre serviços: chamada cross-service introduzida ou removida.

Motivo: o CTO tem veto técnico sobre contratos de API e acoplamento entre serviços (conforme `AGENTS.md`). Redirecionar para o par nestes casos tornaria o veto ineficaz.

### 2.4 Paths sensíveis — revisão obrigatória

PRs que modificam **qualquer** path abaixo disparam o gate de revisão. Fora desta lista, o PR
passa direto (evita fricção em commits de docs, testes unitários e scaffold sem impacto sistêmico).

| Glob | Motivo |
|---|---|
| `**/schema.yml` | Contrato OpenAPI — regressão propaga para todos os consumers |
| `**/openapi*.yml` | Idem |
| `docs/api/**` | Idem |
| `**/migrations/**` | Alteração de schema de banco — irreversível sem rollback explícito |
| `service/**` | Lógica de domínio dos cores — coração do negócio |
| `.github/workflows/**` | Modifica o próprio pipeline de CI/CD |
| `infra/**` | Infraestrutura: mudança propaga para produção diretamente |
| `cm-sdk/**` | Consumido por todas as verticais — breaking change cascateia |
| `config/settings*` | Configurações de runtime — erro aqui derruba o serviço |
| `**/AGENTS.md` | Política de execução dos agentes — altera governança |

**Racionalidade da lista:** um erro em qualquer um desses paths pode propagar para múltiplos
serviços ou ser irreversível. Commits de `README`, `tests/`, `docs/` fora de `docs/api/` e
arquivos de fixtures não precisam de gate — a relação custo/risco não justifica.

### 2.5 Critério de severidade

#### Bloqueante (impede merge — check vermelho)

O achado é bloqueante quando:

1. **Supressão de erro sem causa raiz:** configurar build/pipeline para tolerar uma falha
   (ex.: `handleHttpError` ignorando falha de prerender) sem eliminar a causa. Regra do
   `AGENTS.md`: "supressão de erro não é correção" — é regressão disfarçada.

2. **Acoplamento proibido:** FK ou join entre schemas de serviços diferentes; acesso direto
   ao banco de outro serviço (violação do princípio de integração via API + eventos).

3. **Conceito de vertical em core:** qualquer campo, tipo ou lógica específica de vertical
   (ex.: "faixa", "aula", "dread") introduzida em `cm-crm`, `cm-identity`, `cm-mcp`, `cm-sdk`.

4. **Breaking change em contrato público sem versão:** remoção ou renomeação de campo
   obrigatório em OpenAPI sem `v2/` ou deprecated flag.

5. **Secret ou credencial em código:** qualquer string que pareça chave, token ou senha
   hardcoded.

6. **Violação de multi-tenant:** dado sem `organization_id`; query que vaza dados entre orgs.

7. **Self-merge com check vermelho:** merge de PR onde o gate de revisão falhou.

#### Consultivo (comenta e segue — check verde com nota)

O achado é consultivo quando:

- Oportunidade de refatoração que não afeta comportamento externo.
- Nomenclatura inconsistente sem impacto em contrato.
- Cobertura de teste abaixo do desejável, mas sem risco de regressão imediata.
- Documentação ausente ou desatualizada.
- Ineficiência de performance sem impacto em SLA atual.

O revisor **deve** comentar achados consultivos no PR para registro, mas o check permanece
verde e o merge pode prosseguir.

---

## 3. Alternativas consideradas

### 3.1 GitHub native approvals + CODEOWNERS
Descartado: todos os agentes operam sob a mesma conta (`cadusds2`). O GitHub rejeita
aprovação do próprio PR independentemente de CODEOWNERS. Inviável sem múltiplas contas.

### 3.2 Upgrade para GitHub Pro/Team
Descartado por decisão de board: a solução deve funcionar no plano gratuito em definitivo.

### 3.3 Tornar repos públicos para destravar rulesets
Descartado: código de negócio privado — risco de exposição supera qualquer benefício de
governança.

### 3.4 Revisão de todos os PRs (sem filtro de paths)
Descartado: gera fricção excessiva em commits rotineiros (docs, testes, scaffolding) e
desgasta o ciclo de revisão. O gate concentrado nos paths de alto risco maximiza o sinal/ruído.

### 3.5 Revisão manual pelo usuário humano (Cadu)
Descartado como gate primário: cria gargalo humano e não escala. Permanece como escalação
em casos de conflito ou incidente.

---

## 4. Consequências

### 4.1 Positivas
- Regressões arquiteturais (acoplamento, conceito de vertical em core) são detectadas antes do merge.
- O CTO mantém veto efetivo sobre contratos de API sem revisar todo PR.
- Zero custo adicional: revisor roda na assinatura Claude existente.
- Enforcement visual claro: check vermelho é inequívoco para qualquer participante do board.

### 4.2 Negativas / trade-offs
- Sem branch protection, um agente pode tecnicamente fazer merge com check vermelho. Mitigação:
  o `AGENTS.md` proíbe explicitamente e o incidente é reportado ao board.
- Latência no merge: o gate adiciona o tempo de execução do `/code-review` ao ciclo de PR.
  Estimativa: 2–5 minutos por revisão (aceitável dado o risco evitado).
- A matriz de pares depende de que o workflow identifique corretamente o agente autor pelo
  login do committer. Agentes que operem sob login diferente de `cadusds2` precisarão de
  mapeamento explícito no workflow.

### 4.3 Riscos residuais
- Agente desrespeita a política → incidente de governança, reportado ao board no próximo
  heartbeat do CTO.
- Path sensível não listado e PR problemático passa direto → o CTO atualiza este ADR e
  o filtro de paths no workflow na próxima iteração.

---

## 5. Implementação — próximos passos

Este ADR é o blocker da implementação. A sequência:

1. **PlatformEngineer** implementa o workflow `.github/workflows/diff-review.yml` em todos
   os repos em escopo, lendo este ADR como especificação. (CMV-398 desbloqueada após merge deste ADR)
2. O workflow deve:
   - Detectar paths modificados via `git diff --name-only`.
   - Aplicar o override de roteamento da Seção 2.3 antes da matriz de pares.
   - Acordar o revisor via Paperclip API com o PR number e diff como contexto.
   - Publicar o status check `reviewer-gate` com o resultado.
3. **CTO** revisa o PR do workflow antes do merge (PlatformEngineer → CTO, conforme matriz).

---

## 6. Glossário

| Termo | Definição neste ADR |
|---|---|
| **Gate** | Status check obrigatório no PR; falha (vermelho) impede merge por política |
| **Bloqueante** | Achado que faz o check falhar e impede merge |
| **Consultivo** | Achado registrado como comentário; check permanece verde |
| **Override CTO** | Roteamento que ignora a matriz de pares e envia para o CTO |
| **Path sensível** | Arquivo cujo erro tem potencial de propagação sistêmica |
| **Self-merge** | Merge de PR pelo mesmo agente que o abriu, sem gate aprovado |
