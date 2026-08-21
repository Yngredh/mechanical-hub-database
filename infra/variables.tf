variable "aws_region" {
  description = "Regiao AWS. O AWS Academy so libera us-east-1 e us-west-2."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.aws_region)
    error_message = "AWS Academy only allows us-east-1 or us-west-2."
  }
}

variable "project" {
  description = "Nome do projeto, usado como prefixo dos recursos."
  type        = string
  default     = "mechanical-hub"
}

variable "environment" {
  description = "Ambiente de implantacao (production, staging)."
  type        = string
  default     = "production"
}

# ── State remoto do mechanical-hub-infra ─────────────────────────────────────

variable "infra_state_bucket" {
  description = <<-EOT
    Bucket S3 do state do mechanical-hub-infra, de onde vpc_id,
    private_subnet_ids e private_subnet_cidrs sao lidos (ADR-0002).

    Vazio desativa a leitura do remote state; nesse caso informe vpc_id,
    private_subnet_ids e private_subnet_cidrs diretamente.
  EOT
  type        = string
  default     = ""
}

variable "infra_state_key" {
  description = "Chave do state do mechanical-hub-infra dentro do bucket."
  type        = string
  default     = "mechanical-hub-infra/terraform.tfstate"
}

variable "infra_state_region" {
  description = "Regiao do bucket de state. Vazio usa var.aws_region."
  type        = string
  default     = ""
}

# ── Overrides de rede (fallback do remote state) ─────────────────────────────

variable "vpc_id" {
  description = "Override do vpc_id. Tem precedencia sobre o remote state."
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "Override das subnets privadas. Minimo de duas AZs distintas."
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "Override dos CIDRs liberados na porta do banco (ADR-0002)."
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = <<-EOT
    Security groups adicionais autorizados a acessar o banco.

    Normalmente vazio: a ADR-0002 decidiu pela liberacao por CIDR justamente
    para evitar dependencia circular com o repositorio mechanical-hub-auth.
  EOT
  type        = list(string)
  default     = []
}

# ── RDS ──────────────────────────────────────────────────────────────────────

variable "db_engine_version" {
  description = "Versao do PostgreSQL."
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "Classe da instancia RDS."
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Nome do banco PostgreSQL."
  type        = string
  default     = "mechanical_hub"
}

variable "db_username" {
  description = "Usuario master da instancia RDS."
  type        = string
  default     = "mechanical_hub"
}

variable "db_password" {
  description = "Senha do usuario master. Injetada no CI via TF_VAR_db_password."
  type        = string
  sensitive   = true
}

variable "db_port" {
  description = "Porta do banco."
  type        = number
  default     = 5432
}

variable "db_allocated_storage" {
  description = "Armazenamento alocado em GB."
  type        = number
  default     = 20
}

variable "db_storage_encrypted" {
  description = "Criptografia em repouso."
  type        = bool
  default     = true
}

variable "db_multi_az" {
  description = "Implantacao Multi-AZ. Desligado no AWS Academy por custo."
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "Dias de retencao de backup automatico. 0 desabilita."
  type        = number
  default     = 0
}

variable "db_deletion_protection" {
  description = "Protecao contra exclusao da instancia."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Pula o snapshot final ao destruir a instancia."
  type        = bool
  default     = true
}

variable "db_apply_immediately" {
  description = "Aplica alteracoes sem esperar a janela de manutencao."
  type        = bool
  default     = false
}
