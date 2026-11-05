# billing-export-acesso-bjj

Leitura (`roles/bigquery.dataViewer`) no dataset `bjj-system.billing_export`, o
export de faturamento da conta do sys-bjj (histórico do sys-bjj até 06/10/2026, antes da troca de conta), para duas SAs do
`cm-ventures-core`:

| SA | Por quê |
|---|---|
| `analytics-bq-pipeline` | lê a tabela pela view `bronze.custos__gcp_detalhado_bjj` do cm-analytics |
| `github-deployer-prod` | o apply do cm-analytics cria a view, e o BigQuery confere a tabela de origem na criação |

Tabela lida: `bjj-system.billing_export.gcp_billing_export_resource_v1_019321_0AD781_2A231D`.

Parte do plano "custo do GCP no Metabase" (cm-analytics#144), etapa cm-infra#98.
É cópia do `environments/billing-export-acesso` (o mesmo para o export do core).

## É aditivo

Só `google_bigquery_dataset_iam_member`. Ele acrescenta o membro ao papel e
não revoga quem já tem acesso ao dataset. Nunca trocar por `_iam_binding` ou
`_iam_policy`, que são autoritativos e tirariam acessos que este state não
declara. Nada de `dataOwner`, que permite apagar o dataset (decisão do Carlos,
06/10/2026). O dataset em si fica fora do Terraform: foi criado à mão como
destino do export e não se recria.

## Por que o state mora em `terraform-backend-sys-bjj`

O state fica no bucket da própria conta dona do dataset, e não no
`cm-ventures-core-tfstate` como os outros environments do core. Testado em
04/11/2026:

- as contas das verticais (ti.meusdredinhos e bjjsystem25) levam 403 no
  `cm-ventures-core-tfstate`;
- a cm.tech.ventures leva 403 nos `billing_export` do `md-hom` e do
  `bjj-system`.

Então nenhuma conta sozinha alcança o bucket do core e o dataset da vertical ao
mesmo tempo. Com o state no bucket da conta dona, uma conta só faz tudo, sem
cruzar logins (decisão do grelhado de 04/11/2026: "State na conta dona").

## Apply

O cm-infra não tem CI. Quem aplica é o Carlos, com a conta **bjjsystem25**
sozinha, depois do merge e com o `plan` literal revisado no PR:

```bash
cd environments/billing-export-acesso-bjj
gcloud auth application-default login   # entrar com bjjsystem25
terraform init
terraform plan -out=plan.bin   # esperado: 2 to add, 0 to change, 0 to destroy
terraform apply plan.bin
```

Conferência depois do apply (aceite da etapa), com a SA do pipeline. A conta
da vertical não impersona SA do core: rodar de uma conta do core que tenha
`roles/iam.serviceAccountTokenCreator` na `analytics-bq-pipeline`:

```bash
bq ls --impersonate_service_account=analytics-bq-pipeline@cm-ventures-core.iam.gserviceaccount.com bjj-system:billing_export
```

A etapa das views no `bronze` (cm-analytics#145) só pode ser mergeada depois
deste apply: o deploy do cm-analytics cria a view e quebra se o deployer ainda
não lê a origem.
