# =============================================================================
# Contrato entre repositorios (ADR-0002)
#
# Estes outputs sao interface publica: alterar ou remover qualquer um deles e
# uma mudanca quebra-compatibilidade e exige coordenacao com os consumidores.
#
# Consumidores:
#   - mechanical-hub-auth : rds_endpoint, rds_port, rds_db_name
#   - mechanical-hub (CI)  : rds_endpoint, rds_port, rds_db_name
# =============================================================================

output "rds_endpoint" {
  description = "Hostname da instancia RDS. Usado como DB_HOST/DATABASE_HOST pelos consumidores."
  value       = module.rds.endpoint
}

output "rds_endpoint_with_port" {
  description = "Endpoint completo no formato host:porta."
  value       = module.rds.endpoint_with_port
}

output "rds_port" {
  description = "Porta do banco."
  value       = module.rds.port
}

output "rds_db_name" {
  description = "Nome do banco PostgreSQL."
  value       = module.rds.db_name
}

output "rds_username" {
  description = "Usuario master. As aplicacoes devem usar roles dedicadas, nao este usuario."
  value       = module.rds.db_username
}

output "rds_identifier" {
  description = "Identificador da instancia RDS."
  value       = module.rds.identifier
}

output "rds_arn" {
  description = "ARN da instancia RDS."
  value       = module.rds.arn
}

output "rds_security_group_id" {
  description = "Security group do banco."
  value       = module.rds.security_group_id
}

output "rds_subnet_group_name" {
  description = "Nome do DB subnet group."
  value       = module.rds.subnet_group_name
}

# ── Rede resolvida (util para depurar a leitura do remote state) ─────────────

output "vpc_id" {
  description = "VPC efetivamente usada, vinda do state do mechanical-hub-infra ou do override."
  value       = local.vpc_id
}

output "private_subnet_ids" {
  description = "Subnets privadas efetivamente usadas no DB subnet group."
  value       = local.private_subnet_ids
}
