# Alertas das rotinas agendadas do bjj-system (sys-bjj).
#
# Por que isto vive no cm-infra e não no Terraform do sys-bjj: lá, push em main
# deploya produção e os applies disputam o lock do estado. Alerta é observação
# pura e não tem por que participar dessa fila — nem de arriscar travá-la.
#
# Projeto e conta Google são outros (bjjsystem25@gmail.com), por isso estado e
# backend próprios. Não se usa provider aliasado: seria preciso uma credencial
# única com permissão nos dois projetos, e essa ponte é um risco permanente
# maior do que o problema que resolveria.

locals {
  alertas = { for a in yamldecode(file("${path.module}/alertas.yaml")) : a.nome => a }
}

module "alerta" {
  source   = "../../modules/alerta-generico"
  for_each = local.alertas

  nome       = each.key
  titulo     = each.value.titulo
  project_id = var.project_id
  sensor     = each.value.sensor
  alvo       = lookup(each.value, "alvo", [])

  canal_id     = var.canais[each.value.caixa]
  severidade   = "ERROR"
  janela       = lookup(each.value, "janela", "3600s")
  documentacao = each.value.doc
}
