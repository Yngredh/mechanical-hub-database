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
