# Sinks de eventos estruturados para o bronze_logs do cm-ventures-core (camada
# bronze da plataforma de dados; até cm-infra#57 o destino era o raw_logs).
#
# Estado próprio, fora do bootstrap: o bootstrap tem drift conhecido e não se
# aplica. O sink antigo do MCP (cm-mcp-tool-calls-to-bq, no bootstrap) segue
# como está até a migração dele.
#
# Um sink por projeto: sink só enxerga os logs do projeto onde vive. A conta
# que aplica este state (cm.tech.ventures) tem roles/logging.configWriter no
# md-hom e no bjj-system, concedido à mão pela conta dona de cada um (ver
# docs/observabilidade.md, seção "Sinks para o bronze_logs"). A IAM da writer
# identity cai sempre no dataset do core.

module "sink_core" {
  source     = "../../modules/log-sink-bigquery"
  project_id = "cm-ventures-core"
}

# md-hom é a produção real do MD (os serviços forçam CM_ENV=prod lá). O sink
# antigo do MCP (cm-mcp-tool-calls-to-bq) também vive nesse projeto e não é
# tocado por este state.
module "sink_md_hom" {
  source     = "../../modules/log-sink-bigquery"
  project_id = "md-hom"
}

module "sink_bjj" {
  source     = "../../modules/log-sink-bigquery"
  project_id = "bjj-system"
}
