output "sinks" {
  description = "Sink e writer identity por projeto de origem."
  value = {
    "cm-ventures-core" = {
      sink            = module.sink_core.sink_name
      writer_identity = module.sink_core.writer_identity
      destination     = module.sink_core.destination
    }
  }
}
