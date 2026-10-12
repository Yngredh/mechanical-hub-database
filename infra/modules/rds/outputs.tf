output "endpoint" {
  description = "Hostname da instancia (sem a porta)."
  value       = aws_db_instance.this.address
}

output "endpoint_with_port" {
  description = "Endpoint completo no formato host:porta."
  value       = aws_db_instance.this.endpoint
}

output "port" {
  description = "Porta do banco."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Nome do banco PostgreSQL."
  value       = aws_db_instance.this.db_name
}

output "db_username" {
  description = "Usuario master."
  value       = aws_db_instance.this.username
}

output "identifier" {
  description = "Identificador da instancia RDS."
  value       = aws_db_instance.this.identifier
}

output "arn" {
  description = "ARN da instancia RDS."
  value       = aws_db_instance.this.arn
}

output "security_group_id" {
  description = "Security group do banco."
  value       = aws_security_group.rds.id
}

output "subnet_group_name" {
  description = "Nome do DB subnet group."
  value       = aws_db_subnet_group.this.name
}

output "publicly_accessible" {
  description = "Se a instancia aceita conexao publica. Sempre false (ADR-0002); exposto para os testes do modulo raiz."
  value       = aws_db_instance.this.publicly_accessible
}

output "ingress_cidr_blocks" {
  description = "CIDRs com regra de ingress na porta do banco, ja aplicadas ao security group."
  value       = sort([for rule in aws_security_group_rule.postgres_from_private_subnets : one(rule.cidr_blocks)])
}

output "ingress_security_group_ids" {
  description = "Security groups com regra de ingress na porta do banco."
  value       = sort([for rule in aws_security_group_rule.postgres_from_security_groups : rule.source_security_group_id])
}
