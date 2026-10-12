output "databases" {
  description = "Mesmo formato do output databases do modulo raiz."
  value = {
    for service, rds in module.rds : service => {
      endpoint     = rds.endpoint
      port         = rds.port
      db_name      = rds.db_name
      app_username = var.databases[service].app_username
    }
  }
}

output "identifiers" {
  description = "Identificador de cada instancia, por servico."
  value       = { for service, rds in module.rds : service => rds.identifier }
}

output "subnet_group_names" {
  description = "DB subnet group de cada instancia, por servico."
  value       = { for service, rds in module.rds : service => rds.subnet_group_name }
}

output "security_group_ids" {
  description = "Security group de cada instancia, por servico."
  value       = { for service, rds in module.rds : service => rds.security_group_id }
}

output "ingress_cidr_blocks" {
  description = "CIDRs liberados no security group de cada instancia, por servico."
  value       = { for service, rds in module.rds : service => rds.ingress_cidr_blocks }
}

output "ingress_security_group_ids" {
  description = "Security groups liberados em cada instancia, por servico."
  value       = { for service, rds in module.rds : service => rds.ingress_security_group_ids }
}
