# log-sink-bigquery

Leva os eventos estruturados de **um projeto GCP** para o dataset `bronze_logs`
do `cm-ventures-core`, pelo Cloud Logging. É a peça "sinks" da plataforma de
dados (fase 4, logs estruturados).

O que o módulo cria:

| Recurso | Para quê |
| --- | --- |
| `google_logging_project_sink` | Copia as linhas que passam no filtro para o BigQuery. |
| `google_bigquery_dataset_iam_member` | Dá `bigquery.dataEditor` à writer identity do sink, **só no dataset**. É aditivo: não revoga nada do que já está lá. |

O dataset **não** é criado aqui. Ele é do Terraform do cm-analytics
(`terraform/bigquery.tf`, partição expirando em 730 dias). O módulo só o lê por
`data "google_bigquery_dataset"`: se o dataset não existir, o `plan` falha,
em vez de inventar um.

## Filtro padrão

```
resource.type=("cloud_run_revision" OR "cloud_run_job")
jsonPayload.event:*
jsonPayload.env="prod"
```

- `jsonPayload.event:*`: só entra linha que tem o campo `event`, ou seja, o
  envelope do `cm_sdk.observabilidade`. Log de texto solto fica de fora.
- `jsonPayload.env="prod"`: dado de homologação **não** vai para o BigQuery.
  O filtro é igual em todos os projetos. Serviço que roda produção num
  ambiente com nome antigo (md-hom, frontend-bjj) força `CM_ENV=prod` no
  próprio deploy; o sink não ganha exceção.
- Só Cloud Run (serviço ou job). Para outro filtro, passe `filtro`.

## Nome da tabela: não se escolhe

O Logging decide o nome da tabela a partir do **log id** de origem. O
`cm_sdk.observabilidade` escreve no stdout, então a tabela sai sempre:

```
cm-ventures-core.bronze_logs.run_googleapis_com_stdout
```

Não há opção no sink para trocar esse nome. Com `use_partitioned_tables = true`
ela é **uma tabela só**, particionada por dia (`timestamp`); sem isso, nasceria
uma tabela por dia com sufixo `_AAAAMMDD`. O nome legível
(`stg_logs__eventos`) nasce no dbt do cm-analytics, que declara esta tabela
como source.

Os sinks de vários projetos caem na **mesma tabela**. A origem está nas
colunas `resource.labels.project_id` e `jsonPayload.service`.

Tipos: os campos do envelope chegam como colunas de `jsonPayload`. O `dados`
é texto JSON no envelope, então chega como **STRING**; quem abre é o dbt
(`JSON_VALUE`/`PARSE_JSON`).

## Uso

```hcl
module "sink_core" {
  source     = "../../modules/log-sink-bigquery"
  project_id = "cm-ventures-core"
}
```

Quem aplica precisa poder criar sink no projeto de origem
(`roles/logging.configWriter`) e mudar a IAM do dataset no `cm-ventures-core`.

## Custo

Rotear log por sink não é cobrado. A gravação no BigQuery é por streaming
(cobrança por volume inserido, centavos no volume atual) e o armazenamento
segue a expiração de 730 dias do dataset.
