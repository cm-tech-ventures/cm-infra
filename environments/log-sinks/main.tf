# Sinks de eventos estruturados para o raw_logs do cm-ventures-core.
#
# Estado próprio, fora do bootstrap: o bootstrap tem drift conhecido e não se
# aplica. O sink antigo do MCP (cm-mcp-tool-calls-to-bq, no bootstrap) segue
# como está até a migração dele.
#
# Um sink por projeto. Hoje só o cm-ventures-core. md-hom e bjj-system entram
# aqui depois que a conta que aplica este state puder criar sink lá (ver
# docs/observabilidade.md, seção "Sinks para o raw_logs").

module "sink_core" {
  source     = "../../modules/log-sink-bigquery"
  project_id = "cm-ventures-core"
}
