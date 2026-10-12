output "host" {
  description = "Host DNS estavel do pod, o mesmo gravado no replica set."
  value       = local.host
}

output "port" {
  description = "Porta do mongod."
  value       = var.port
}

output "replica_set" {
  description = "Nome do replica set."
  value       = var.replica_set_name
}

output "database" {
  description = "Banco do orchestrator (tambem o authSource do usuario dele)."
  value       = var.database
}

output "secret_name" {
  description = "Secret com username/password do orchestrator (e as credenciais root)."
  value       = kubernetes_secret_v1.credentials.metadata[0].name
}

output "namespace" {
  description = "Namespace do MongoDB, onde fica o Secret."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}
