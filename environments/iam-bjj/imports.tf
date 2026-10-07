# Adoção do IAM vivo do bjj-system (cm-infra#79, plano #70).
#
# Cada bloco traz para o state algo que JÁ existe, conferido com gcloud em
# 06/10/2026 (projects get-iam-policy, service-accounts get-iam-policy,
# workload-identity-pools describe, storage buckets get-iam-policy).
# O apply não muda nada na nuvem. Depois do apply estes blocos viram no-op e
# podem sair num PR de limpeza.
#
# Parte disto também está no state do Terraform do sys-bjj-backend e do
# sys-bjj-face. As etapas 16 e 17 tiram de lá com
# `removed { lifecycle { destroy = false } }`. Até lá os dois states declaram a
# mesma coisa, o que é inofensivo com `_iam_member` (aditivo).
#
# Formatos de id do provider google:
#   google_service_account:              "projects/<projeto>/serviceAccounts/<email>"
#   google_service_account_iam_member:   "projects/<projeto>/serviceAccounts/<email> <papel> <membro>"
#   google_project_iam_member:           "<projeto> <papel> <membro>"
#   google_storage_bucket_iam_member:    "b/<bucket> <papel> <membro>"

import {
  for_each = local.contas_deploy
  to       = google_service_account.deploy[each.key]
  id       = "projects/${var.project_id}/serviceAccounts/${each.key}@${var.project_id}.iam.gserviceaccount.com"
}

import {
  to = google_iam_workload_identity_pool.github
  id = "projects/${var.project_id}/locations/global/workloadIdentityPools/${local.pool_id}"
}

import {
  to = google_iam_workload_identity_pool_provider.github
  id = "projects/${var.project_id}/locations/global/workloadIdentityPools/${local.pool_id}/providers/github-provider"
}

import {
  for_each = local.wif
  to       = google_service_account_iam_member.wif[each.key]
  id       = "projects/${var.project_id}/serviceAccounts/${each.value.sa}@${var.project_id}.iam.gserviceaccount.com ${each.value.papel} ${each.value.membro}"
}

import {
  to = google_service_account_iam_member.backend_assina_urls
  id = "projects/${var.project_id}/serviceAccounts/sys-bjj-backend-deploy@${var.project_id}.iam.gserviceaccount.com roles/iam.serviceAccountTokenCreator serviceAccount:sys-bjj-backend-deploy@${var.project_id}.iam.gserviceaccount.com"
}

import {
  for_each = local.deploy_projeto
  to       = google_project_iam_member.deploy[each.key]
  id       = "${var.project_id} ${each.value.papel} serviceAccount:${each.value.sa}@${var.project_id}.iam.gserviceaccount.com"
}

import {
  for_each = local.externos_projeto
  to       = google_project_iam_member.externos[each.key]
  id       = "${var.project_id} ${each.value.papel} ${each.value.membro}"
}

import {
  for_each = local.deploy_bucket_state
  to       = google_storage_bucket_iam_member.state[each.key]
  id       = "b/terraform-backend-sys-bjj ${each.value.papel} serviceAccount:${each.value.sa}@${var.project_id}.iam.gserviceaccount.com"
}
