# Permissões

Como a CM Ventures dá, confere e tira permissão de nuvem.
Ler antes de criar conta de serviço, dar papel ou mexer em `bootstrap/`.

De onde vem:

- plano: [cm-infra#70](https://github.com/cm-tech-ventures/cm-infra/issues/70);
- spike de 06/10/2026, "Gerenciamento de permissões da CM Ventures", seções 4.1 a 4.6
  (o link está no corpo do #70).

Este repo é público. Aqui ficam as regras e o processo.
A lista de exceções (o que está vivo, fora do código e com motivo) fica no cm-docs, que é privado
([cm-docs#13](https://github.com/cm-tech-ventures/cm-docs/issues/13)).

## As 4 regras

### 1. Automação nunca tem poder sobre o próprio poder

Conta de CI e conta de runtime **nunca** recebem:

- `roles/resourcemanager.projectIamAdmin`;
- `roles/iam.roleAdmin`;
- `roles/iam.serviceAccountAdmin`;
- `roles/iam.serviceAccountUser` no projeto inteiro (na própria SA de runtime pode);
- `roles/iam.workloadIdentityPoolAdmin`;
- `roles/storage.admin` no projeto (num bucket específico pode);
- `roles/secretmanager.admin` sem condição;
- `roles/owner` ou `roles/editor`.

Quem tem um desses papéis consegue se dar qualquer outro. Por isso eles ficam só com pessoas.

### 2. Dado que não se recria só tem dono humano

- Dataset insubstituível (lista abaixo) tem como dono só a conta humana do projeto.
- CI e pipeline ficam em leitor ou escritor, nunca dono.
- O Terraform declara **quem lê e quem escreve** no dataset, nunca o dataset em si.
  Tirar o dataset do código faria o Terraform apagá-lo.

### 3. Hom não alcança prod

- Cada ambiente tem sua conta de deploy.
- O WIF de prod só aceita `refs/heads/main`. O de hom só aceita `refs/heads/hom`.
- No core essa regra tem um limite. Ver [O limite da regra 3 no core](#o-limite-da-regra-3-no-core).

### 4. Quem roda não é quem implanta

- A SA de runtime é separada da SA de deploy.
- A de runtime só lê os próprios secrets, mais log e trace.
- Exceção prevista: o billing cria secrets de subconta. Ele ganha admin só em `billing-subconta-*`,
  por condição, e nada além disso.

## Quem aplica o quê

| O quê | Mora em | Quem aplica |
|---|---|---|
| **Fundação**: WIF, o que cada SA de deploy pode, permissão entre projetos, acesso a dado insubstituível, papéis de pessoas | `bootstrap/` (core) e `environments/iam-*` (bjj, md) | A conta humana dona do projeto, na mão, com o `plan` literal no PR |
| **Do serviço**: SA de runtime, leitura dos próprios secrets, invoker, o próprio bucket | Terraform do repo do serviço, com os módulos deste repo | O CI, no merge |
| **Banco (Supabase)**: roles e grants | Migração ou script no repo do serviço (padrão do `face_service` do sys-bjj-face) | O CI, no deploy |
| **GitHub**: membros, colaboradores, environments, secrets | Console do GitHub | O Carlos, na mão |
| **cm-identity**: organizações, chaves, escopos | Banco do identity (é dado de produto) | Só pela API do identity, nunca escrevendo direto no banco |

Contas humanas donas de cada projeto:

| Projeto | Conta |
|---|---|
| core (`cm-ventures-core`) | `cm.tech.ventures` |
| bjj (`bjj-system`) | `bjjsystem25` |
| MD | `ti.meusdredinhos` |

Regras de quem aplica:

- `bootstrap/` e `environments/iam-*` nunca são aplicados pelo CI. Este repo não tem CI, e o
  log do Actions seria público.
- Todo PR que mexe em permissão traz o `plan` literal no corpo. O `apply` é do Carlos.
- Conta humana de um projeto não tem papel de admin em projeto de outra conta,
  salvo o que estiver declarado em `iam-*`.

## O que dá para condicionar

Conferido na documentação do Google em 06/10/2026. Condição de IAM não funciona em todo recurso.
Antes de prometer "só nos recursos X", olhar aqui.

| Promessa | Funciona? | Como fazemos | Fonte |
|---|---|---|---|
| Secret por prefixo de nome | Sim, mas a condição **bloqueia criar e listar**, que são checados no projeto | Admin condicionado ao prefixo, mais `secrets.create` sem condição num papel custom, só onde precisa criar | [acesso](https://docs.cloud.google.com/secret-manager/docs/access-control), [create](https://docs.cloud.google.com/secret-manager/docs/reference/rest/v1/projects.secrets/create), [list no pai](https://docs.cloud.google.com/iam/docs/configuring-resource-based-access) |
| `serviceAccountUser` só nas SAs de runtime | **Não** por condição | Binding na própria SA (`deployer_act_as`), como no módulo `cloud-run-service` | [atributos por serviço](https://docs.cloud.google.com/iam/docs/conditions-resource-attributes), [atributo ausente](https://docs.cloud.google.com/iam/docs/conditions-attribute-reference) |
| Cloud Run só `*-hom` | **Não**. O Run não fornece o nome do recurso para a condição | Só com SA ou projeto separado | [Cloud Run](https://docs.cloud.google.com/run/docs/securing/managing-access), [atributos por serviço](https://docs.cloud.google.com/iam/docs/conditions-resource-attributes) |
| Cloud Scheduler por job | **Não** (nem condição, nem tag) | `cloudscheduler.admin` sem condição. Aceito e documentado | [tags suportadas](https://docs.cloud.google.com/resource-manager/docs/tags/tags-supported-services) |
| Artifact Registry por repositório | Não por nome | Binding no próprio repositório | [Artifact Registry](https://docs.cloud.google.com/artifact-registry/docs/access-control) |
| State do Terraform por prefixo no bucket | Sim, mas a listagem continua vendo o nome de todos os objetos | `objectAdmin` condicionado ao prefixo. Exige acesso uniforme no bucket | [Cloud Storage](https://docs.cloud.google.com/storage/docs/access-control/iam) |
| BigQuery por dataset | Sim (o nome usa o id do projeto) | Condição em `projects/ID/datasets/X`. Evitar condição negativa | [BigQuery](https://docs.cloud.google.com/bigquery/docs/conditions) |
| WIF por branch | Sim, em duas camadas | O provider filtra main ou hom. O binding por `attribute.ref` separa as SAs | [WIF em pipelines](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines) |
| "Pode conceder só os papéis X" (`modifiedGrantsByRole`) | Sim, só em projeto | Plano B, se algum repo precisar mesmo conceder papel. Não limita **a quem** se concede | [limites de concessão](https://docs.cloud.google.com/iam/docs/setting-limits-on-granting-roles) |

Limites gerais das condições:

- papel básico (owner, editor, viewer) e `allUsers` não aceitam condição;
- no máximo 20 bindings do mesmo papel para o mesmo principal;
- no máximo 12 operadores lógicos por condição.

Fontes: [visão geral](https://docs.cloud.google.com/iam/docs/conditions-overview),
[cotas](https://docs.cloud.google.com/iam/quotas),
[recursos com binding condicional](https://docs.cloud.google.com/iam/docs/resource-types-with-conditional-roles).

Duas inferências ainda sem teste:

- a condição por prefixo bloqueia mesmo o `secrets.create`;
- a condição `== bucket` libera a listagem no Cloud Storage.

A SA de ensaio (abaixo) prova as duas antes de qualquer remoção.

## Datasets insubstituíveis

São dados que não se recriam. Valem a regra 2.

| Dataset | O que guarda |
|---|---|
| `billing_export` (em cada projeto que tem) | Export de faturamento do GCP |
| `bronze_logs` | Eventos dos sinks de log dos projetos |
| `raw_mcp_logs` | Logs crus dos servidores MCP |

- O Terraform declara só quem lê e quem escreve nesses datasets.
- O dataset em si nunca entra em Terraform. Se entrou, sai com
  `removed { lifecycle { destroy = false } }`.
- Dataset novo nessa situação entra nesta lista no mesmo PR que o cria.

## O limite da regra 3 no core

No bjj e no MD, hom e prod podem ter contas e WIF separados por projeto.
No core, hom e prod dividem o mesmo projeto GCP (`cm-ventures-core`).

O desenho (decisão D1 do #70):

- `deployer-prd`: WIF só de `refs/heads/main`;
- `deployer-hom`: WIF só de `refs/heads/hom`;
- a `deployer-hom` só alcança os secrets `*-hom-*` e o state em `*-hom/`, por condição.

O que isso **não** cobre:

- os serviços Cloud Run de prod continuam ao alcance da `deployer-hom`;
- o motivo: o Cloud Run não aceita condição por nome (tabela acima).

Então, no core, "hom não alcança prod" vale para secrets e state, não para o Cloud Run.

Ponto de virada para um projeto GCP separado para o core de hom. Qualquer um destes:

- mais de uma pessoa fazendo merge em `hom` no core;
- um core de hom passar a guardar dado real de cliente.

## Como revogar

Primeiro, entender o tipo de recurso:

- `google_*_iam_member` é **aditivo**. Ele só garante o que declara. Não tira o que não declara.
- `google_*_iam_binding` e `google_*_iam_policy` são **autoritativos**. Eles apagam tudo que
  não declaram. **Nunca usar esses tipos para revogar.**

Como tirar, conforme o caso:

| Caso | O PR faz | O plan mostra |
|---|---|---|
| Permissão declarada no código | Apaga o bloco | `1 to destroy` |
| Papel de projeto dado à mão | Acrescenta um `google_project_iam_member_remove` | `1 to add` |
| Papel dado à mão em recurso (secret, SA, dataset, bucket) | Dois commits: primeiro `import {}`, depois apaga o bloco | `1 to import`, depois `1 to destroy` |

Emergência:

1. Tirar pelo console.
2. Depois, levar ao código (`google_project_iam_member_remove` ou import e remoção),
   ou registrar na lista de exceções do cm-docs.

Nada fica vivo fora do código e fora da lista de exceções.

## Como testar uma remoção

Tirar papel de conta de deploy pode quebrar o próximo deploy. Antes de aplicar:

1. **SA de ensaio.** O bootstrap cria uma SA temporária com exatamente os papéis que a conta de
   deploy vai ter depois da remoção. Ela não tem WIF. Só o Carlos pode impersoná-la.
2. **Plan de todos os states** do projeto, impersonando a SA de ensaio.
3. **Apply dos states de hom** com ela (os de prod, nunca).
4. Se tudo passa, a remoção vai para a conta de deploy real.
5. **Deploy de hom** de cada serviço logo depois do apply.
6. A SA de ensaio é apagada no fim.

Cuidados:

- **um projeto GCP por dia**, nunca dois;
- antes, o Policy Simulator do Google pode mostrar o que o uso recente teria negado.

Desfazer é rápido: devolver o mesmo papel.

```bash
gcloud projects add-iam-policy-binding <projeto> \
  --member="serviceAccount:<sa>" --role="<papel>"
```

Depois, levar a volta ao código também.

### SA de ensaio do core (cm-infra#74)

`deployer-ensaio@cm-ventures-core.iam.gserviceaccount.com`, declarada em `bootstrap/ensaio.tf`.
Tem o poder que o `github-deployer-prod` terá depois da etapa 11 ([#76](https://github.com/cm-tech-ventures/cm-infra/issues/76)):

- os papéis de projeto do bootstrap, o papel custom de IAM de SA e `iam.serviceAccountCreator`;
- `secretmanager.admin` só com as duas condições do deployer (`core-secrets-only` e `core-secrets-extra`, mesmo texto);
- `storage.objectAdmin` no bucket de state e `storage.admin` só nos 3 buckets de site e staging;
- `iam.serviceAccountUser` SA a SA, nas de runtime e de proxy onde o deployer tem hoje;
- `bigquery.dataOwner` nos datasets do armazém e `dataViewer` no `billing_export`.
  Nada no `bronze_logs` nem no `raw_mcp_logs` (etapa 14).

Não tem: projectIamAdmin, roleAdmin, serviceAccountAdmin, serviceAccountUser no projeto,
storage.admin no projeto, secretmanager.admin sem condição, iap.admin, loadBalancerAdmin. Nem WIF.
As listas estão em `bootstrap/terraform.tfvars.example` (`ensaio_*`), com o comando que as conferiu.

#### 1. Impersonar

Só `cm.tech.ventures` e a conta pessoal do Carlos têm `serviceAccountTokenCreator` na SA.
Depois do apply do bootstrap, o binding pode levar alguns minutos para valer.

Para o Terraform, o jeito mais simples é um token da SA (vale 1 hora; o backend GCS também usa):

```bash
SA=deployer-ensaio@cm-ventures-core.iam.gserviceaccount.com
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token \
  --account=cm.tech.ventures@gmail.com --impersonate-service-account=$SA)
```

Alternativa, com ADC (`gcloud auth application-default login`):
`export GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=$SA`.

Para comandos `gcloud` avulsos: `gcloud config set auth/impersonate_service_account $SA`.
Desfazer no fim com `gcloud config unset auth/impersonate_service_account`.

Conferir quem está agindo antes de rodar qualquer coisa:

```bash
curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=$GOOGLE_OAUTH_ACCESS_TOKEN" | jq -r .email
```

#### 2. Plan de cada state do core

Em cada repo, no diretório do Terraform, com as mesmas variáveis que o workflow passa
(ver o `deploy-cloud-run.yml` e o workflow do repo). Use a imagem que está no ar, para o plan
não mostrar troca de imagem:
`gcloud run services describe <serviço> --region=southamerica-east1 --format='value(spec.template.spec.containers[0].image)'`.

```bash
terraform init -input=false -reconfigure \
  -backend-config=bucket=cm-ventures-core-tfstate -backend-config=prefix=<prefixo>
terraform plan -input=false -lock=false <as -var do workflow>
```

| Core | Prefixo do state | O que rodar |
|---|---|---|
| analytics | `cm-analytics/prod` | plan |
| backoffice | `cm-backoffice/prod`, `cm-backoffice-frontend/prod` | plan |
| billing | `billing/prod` | plan |
| crm | `crm/prod` | plan |
| docs | `cm-docs/prod` | plan |
| identity | `identity/prod` | plan |
| mcp | `cm-mcp/prod` | plan |
| service | `service/prod` | plan |
| billing hom | `billing-hom/hom` | plan e **apply** |
| identity hom | `identity-hom/hom` | plan e **apply** |
| backoffice hom | `cm-backoffice-hom/hom`, `cm-backoffice-frontend-hom/hom` | plan e **apply** |

Apply só nos de hom, e sempre pela conta do Carlos impersonando a SA, nunca pelo CI.
De prod, nunca.

#### 3. O que conta como passou

- **Plan:** termina sem erro e mostra o **mesmo** resumo (`N to add, M to change, K to destroy`)
  que o plan do mesmo state rodado pela `cm.tech.ventures` sem impersonar.
  Um `403`/`Permission denied` é reprovação, mesmo que o resto do plan saia.
- **Apply de hom:** termina com `Apply complete!` e o serviço de hom segue `Ready`
  (`gcloud run services describe <serviço>-hom --region=southamerica-east1 --format='value(status.conditions[0].status)'`).
- O resultado (comando, prefixo, resumo, erro se houver) vai colado no PR da etapa 9.

Reprovou? O papel que faltou não sai do deployer na etapa 11, ou o que o usa é corrigido antes.
Não se acrescenta papel à SA de ensaio para "fazer passar": ela tem que continuar igual ao deployer pós-E5.

Cuidado ao ler o resultado: um plan sem mudança só prova leitura. Escrita (setIamPolicy, actAs,
criar recurso) só aparece quando o plan tem algo a mudar, ou no apply de hom.

#### 4. Desligar

No `bootstrap/terraform.tfvars`: `ensaio_habilitado = false`. O plan tem que mostrar só
destroys de recursos `*ensaio*` (a SA e os bindings dela), nenhum do deployer.
Depois do apply, um PR apaga `bootstrap/ensaio.tf`, as variáveis `ensaio_*` e esta seção
(plan: `No changes`).
