# Alertas das rotinas agendadas do cm-ventures-core.
#
# O que se edita aqui é o `alertas.yaml`, não este arquivo. Alerta novo é um
# item de lista no YAML; este main.tf não muda mais.
#
# Estado separado de propósito: alerta só observa, não altera banco, contrato
# de API nem permissão. Mantê-lo fora dos estados de deploy significa que um
# `destroy` errado aqui não derruba serviço nenhum.

locals {
  alertas = { for a in yamldecode(file("${path.module}/alertas.yaml")) : a.nome => a }

  # Só a caixa que interrompe fica sem limite de frequência.
  limite = {
    dinheiro = ""
    interno  = "86400s"
  }

  severidade = {
    dinheiro = "ERROR"
    interno  = "WARNING"
  }
}

module "alerta" {
  source   = "../../modules/alerta-generico"
  for_each = local.alertas

  nome       = each.key
  titulo     = each.value.titulo
  project_id = var.project_id
  sensor     = each.value.sensor
  alvo       = lookup(each.value, "alvo", [])

  canal_id          = var.canais[each.value.caixa]
  severidade        = local.severidade[each.value.caixa]
  limite_frequencia = local.limite[each.value.caixa]
  janela            = lookup(each.value, "janela", "3600s")
  documentacao      = each.value.doc
}
