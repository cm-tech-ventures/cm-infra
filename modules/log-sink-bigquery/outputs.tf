output "sink_name" {
  value = google_logging_project_sink.eventos.name
}

output "writer_identity" {
  description = "Conta que o Logging usa para gravar no BigQuery (member IAM completo)."
  value       = google_logging_project_sink.eventos.writer_identity
}

output "destination" {
  value = google_logging_project_sink.eventos.destination
}

output "filter" {
  value = google_logging_project_sink.eventos.filter
}
