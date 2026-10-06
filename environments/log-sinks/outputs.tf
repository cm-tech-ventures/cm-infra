output "sinks" {
  description = "Sink e writer identity por projeto de origem."
  value = {
    for projeto, m in {
      "cm-ventures-core" = module.sink_core
      "md-hom"           = module.sink_md_hom
      "bjj-system"       = module.sink_bjj
      } : projeto => {
      sink            = m.sink_name
      writer_identity = m.writer_identity
      destination     = m.destination
    }
  }
}
