# Adoção do que já existe na nuvem e foi feito à mão (cm-infra#73, plano #70).
#
# Cada bloco abaixo traz para o state um binding que JÁ está vivo, conferido com
# get-iam-policy em 06/10/2026. O apply não muda nada na nuvem por causa deles.
# Depois do apply estes blocos viram no-op e podem sair num PR de limpeza.
#
# Formatos de id do provider google:
#   google_project_iam_member:                "<projeto> <papel> <membro>"
#   google_service_account_iam_member:        "projects/<projeto>/serviceAccounts/<email> <papel> <membro>"
#   google_secret_manager_secret_iam_member:  "projects/<projeto>/secrets/<secret> <papel> <membro>"

# --- WIF do deployer: repos com binding criado à mão ---
import {
  for_each = toset([
    "cm-tech-ventures/cm-analytics",
    "cm-tech-ventures/cm-billing",
    "cm-tech-ventures/cm-docs",
  ])
  to = google_service_account_iam_member.wif_binding[each.value]
  id = "projects/${var.project_id}/serviceAccounts/github-deployer-${var.environment}@${var.project_id}.iam.gserviceaccount.com roles/iam.workloadIdentityUser principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/github-${var.environment}/attribute.repository/${each.value}"
}

# --- Backoffice: o que já tem no projeto (iam.securityReviewer é novo, não entra aqui) ---
import {
  for_each = toset([
    "cm-backoffice-run roles/cloudscheduler.admin",
    "cm-backoffice-run roles/logging.viewer",
    "cm-backoffice-run roles/run.viewer",
    "cm-backoffice-hom-run roles/cloudscheduler.viewer",
    "cm-backoffice-hom-run roles/logging.viewer",
    "cm-backoffice-hom-run roles/run.viewer",
  ])
  to = google_project_iam_member.backoffice_leitura[each.value]
  id = "${var.project_id} ${split(" ", each.value)[1]} serviceAccount:${split(" ", each.value)[0]}@${var.project_id}.iam.gserviceaccount.com"
}

# --- bigquery.jobUser do armazém (hoje no state do cm-analytics) ---
import {
  for_each = toset([
    "analytics-bq-pipeline",
    "analytics-bq-metabase",
  ])
  to = google_project_iam_member.armazem_job_user[each.value]
  id = "${var.project_id} roles/bigquery.jobUser serviceAccount:${each.value}@${var.project_id}.iam.gserviceaccount.com"
}

# --- Leitura cruzada de secrets (todos os pares de var.secrets_leitores_externos) ---
import {
  for_each = merge([
    for secret, membros in var.secrets_leitores_externos : {
      for membro in membros : "${secret} ${membro}" => { secret = secret, membro = membro }
    }
  ]...)
  to = google_secret_manager_secret_iam_member.leitura_cruzada[each.key]
  id = "projects/${var.project_id}/secrets/${each.value.secret} roles/secretmanager.secretAccessor ${each.value.membro}"
}
