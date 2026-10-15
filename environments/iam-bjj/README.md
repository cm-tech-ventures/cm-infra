# iam-bjj

Permissões de nuvem do projeto `bjj-system` (sys-bjj), escritas no código.
As regras estão em [`docs/permissoes.md`](../../docs/permissoes.md).

O que mora aqui:

- as contas de deploy (`sys-bjj-*-deploy`) e os papéis delas no projeto;
- o WIF do GitHub (`github-pool` / `github-provider`) e quem pode usar cada conta;
- o IAM do bucket de state `terraform-backend-sys-bjj`;
- o que contas de fora têm aqui: `cm.tech.ventures` (sink de log) e o Backoffice (leitura).

O que **não** mora aqui: conta de runtime, leitura dos próprios secrets e invoker de cada
serviço. Isso fica no Terraform do repo do serviço.

## Quem aplica

A `bjjsystem25@gmail.com`, dona do projeto, na mão. Nunca o CI.
Todo PR que mexe aqui traz o `plan` literal no corpo. O `apply` é do Carlos.

## Como rodar o plan

```bash
cd environments/iam-bjj
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token --account=bjjsystem25@gmail.com)
terraform init
terraform fmt -check && terraform validate
terraform plan -lock=false
```

O state fica em `gs://terraform-backend-sys-bjj/environments/iam-bjj`. Não há tfvars.

## Os imports

`imports.tf` trouxe para o state o que já existia (cm-infra#79). Depois do primeiro `apply`
eles viram no-op: o plan fecha em `No changes` e os blocos podem sair num PR de limpeza.

Tudo aqui é `google_*_iam_member` (aditivo). Para tirar um papel, apagar a linha do mapa:
o plan mostra `1 to destroy` só daquele papel. Nunca usar `_iam_binding` nem `_iam_policy`.
