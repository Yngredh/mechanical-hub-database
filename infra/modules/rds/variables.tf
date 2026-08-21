variable "project" {
  description = "Prefixo aplicado ao nome dos recursos."
  type        = string
}

variable "environment" {
  description = "Ambiente (sufixo dos nomes de recurso)."
  type        = string
}

# ── Rede ──────────────────────────────────────────────────────────────────────

variable "vpc_id" {
  description = "VPC onde o banco e o security group sao criados."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas do DB subnet group. Minimo de duas AZs."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs liberados na porta do banco (ADR-0002: liberacao por CIDR)."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups adicionais autorizados. Opcional."
  type        = list(string)
  default     = []
}

# ── Instancia ─────────────────────────────────────────────────────────────────

variable "engine_version" {
  description = "Versao do PostgreSQL."
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "Classe da instancia RDS."
  type        = string
}

variable "db_name" {
  description = "Nome do banco PostgreSQL."
  type        = string
}

variable "db_username" {
  description = "Usuario master da instancia."
  type        = string
}

variable "db_password" {
  description = "Senha do usuario master."
  type        = string
  sensitive   = true
}

variable "db_port" {
  description = "Porta do banco."
  type        = number
  default     = 5432
}

variable "allocated_storage" {
  description = "Armazenamento alocado em GB."
  type        = number
}

variable "storage_encrypted" {
  description = "Criptografia em repouso."
  type        = bool
  default     = true
}

variable "multi_az" {
  description = "Implantacao Multi-AZ."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Dias de retencao de backup automatico. 0 desabilita."
  type        = number
  default     = 0
}

variable "deletion_protection" {
  description = "Protecao contra exclusao da instancia."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Pula o snapshot final ao destruir a instancia."
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Aplica alteracoes imediatamente, sem esperar a janela de manutencao."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags comuns."
  type        = map(string)
}
