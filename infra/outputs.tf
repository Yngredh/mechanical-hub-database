# =============================================================================
# Contrato entre repositorios (ADR-0002)
#
# Estes outputs sao interface publica: alterar ou remover qualquer um deles e
# uma mudanca quebra-compatibilidade e exige coordenacao com os consumidores.
#
# Consumidores:
#   - mechanical-hub-orders, -stock, -billing (pipelines) : databases
#   - mechanical-hub-auth                                 : auth_database
#   - mechanical-hub-orchestrator (pipeline)              : mongodb_host, mongodb_port,
#                                                           mongodb_replica_set, mongodb_database,
#                                                           mongodb_secret_name
#   - diagnostico                                         : rds_security_group_ids
# =============================================================================

output "databases" {
  description = <<-EOT
    Uma entrada por servico SQL (orders, stock, billing) com endpoint (host,
    sem porta), port, db_name e app_username. Substitui os antigos rds_*.
    A senha do usuario da aplicacao nao sai daqui: fica no secret
    <SERVICO>_DB_APP_PASSWORD de cada repositorio.
  EOT
  value = {
    for service, rds in module.rds : service => {
      endpoint     = rds.endpoint
      port         = rds.port
      db_name      = rds.db_name
      app_username = var.databases[service].app_username
    }
  }
}

output "auth_database" {
  description = "Banco consultado pela autenticacao: a instancia do orders, onde vivem users/profiles e a role mechanical_hub_auth."
  value = {
    endpoint = module.rds["orders"].endpoint
    port     = module.rds["orders"].port
    db_name  = module.rds["orders"].db_name
  }
}

output "rds_security_group_ids" {
  description = "Security group de cada instancia, por servico."
  value       = { for service, rds in module.rds : service => rds.security_group_id }
}

# ── MongoDB do orchestrator ──────────────────────────────────────────────────
# O orchestrator monta a URI com estes valores; usuario e senha ficam so no
# Secret mongodb_secret_name (namespace mongodb_namespace).

output "mongodb_host" {
  description = "Host DNS estavel do pod do MongoDB (<sts>-0.<svc>.<ns>.svc.cluster.local)."
  value       = module.mongodb.host
}

output "mongodb_port" {
  description = "Porta do MongoDB."
  value       = module.mongodb.port
}

output "mongodb_replica_set" {
  description = "Nome do replica set (parametro replicaSet da URI)."
  value       = module.mongodb.replica_set
}

output "mongodb_database" {
  description = "Banco do orchestrator, tambem o authSource do usuario dele."
  value       = module.mongodb.database
}

output "mongodb_secret_name" {
  description = "Secret com as chaves username e password do orchestrator."
  value       = module.mongodb.secret_name
}

output "mongodb_namespace" {
  description = "Namespace onde estao o MongoDB e o Secret mongodb_secret_name."
  value       = module.mongodb.namespace
}

# ── Uso interno da pipeline deste repositorio ────────────────────────────────

output "rds_master_usernames" {
  description = "Usuario master de cada instancia, por servico. Usado apenas pelo Job que roda os scripts de sql/."
  value       = { for service, rds in module.rds : service => rds.db_username }
}

# ── Rede resolvida (util para depurar a leitura do remote state) ─────────────

output "vpc_id" {
  description = "VPC efetivamente usada, vinda do state do mechanical-hub-infra ou do override."
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "Subnets privadas efetivamente usadas nos DB subnet groups."
  value       = local.private_subnet_ids
}

output "eks_cluster_name" {
  description = "Nome do cluster EKS (state do mechanical-hub-infra), usado para rodar os scripts de sql/ via Job no cluster."
  value       = local.eks_cluster_name == "" ? null : local.eks_cluster_name
}
