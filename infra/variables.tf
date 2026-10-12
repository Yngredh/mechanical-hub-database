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

variable "databases" {
  description = <<-EOT
    Uma instancia RDS por servico SQL (ADR-0004), indexada pelo nome do servico.

      db_name           : banco criado na instancia
      db_username       : usuario master (so para administracao e scripts sql/)
      app_username      : usuario da aplicacao, criado por sql/service-user.sql
      instance_class    : classe da instancia
      allocated_storage : armazenamento em GB

    A chave `orders` e obrigatoria: a instancia dela tambem atende a
    autenticacao (output auth_database).
  EOT
  type = map(object({
    db_name           = string
    db_username       = optional(string, "mechanical_hub_admin")
    app_username      = string
    instance_class    = optional(string, "db.t3.micro")
    allocated_storage = optional(number, 20)
  }))

  default = {
    orders = {
      db_name      = "mechanical_hub_orders"
      app_username = "orders_app"
    }
    stock = {
      db_name      = "mechanical_hub_stock"
      app_username = "stock_app"
    }
    billing = {
      db_name      = "mechanical_hub_billing"
      app_username = "billing_app"
    }
  }

  validation {
    condition     = contains(keys(var.databases), "orders")
    error_message = "databases precisa da chave \"orders\": e a instancia apontada por auth_database."
  }

  validation {
    condition     = alltrue([for k in keys(var.databases) : can(regex("^[a-z][a-z0-9-]*$", k))])
    error_message = "As chaves de databases (nomes dos servicos) devem conter apenas letras minusculas, digitos e hifen."
  }
}

variable "db_passwords" {
  description = <<-EOT
    Senha master de cada instancia, indexada pela mesma chave de `databases`.
    No pipeline vem dos secrets DB_PASSWORD_ORDERS, DB_PASSWORD_STOCK e
    DB_PASSWORD_BILLING, via TF_VAR_db_passwords (JSON).
  EOT
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "db_port" {
  description = "Porta do banco."
  type        = number
  default     = 5432
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

# ── Cluster EKS (MongoDB) — overrides do remote state ────────────────────────

variable "eks_cluster_name" {
  description = "Override do nome do cluster EKS. Tem precedencia sobre o remote state."
  type        = string
  default     = ""
}

variable "eks_cluster_endpoint" {
  description = "Override do endpoint do API server do EKS."
  type        = string
  default     = ""
}

variable "eks_cluster_ca_certificate" {
  description = "Override da CA do cluster EKS, em base64 (como o output do mechanical-hub-infra)."
  type        = string
  default     = ""
}

# ── MongoDB ──────────────────────────────────────────────────────────────────

variable "mongodb_namespace" {
  description = "Namespace do MongoDB do orchestrator."
  type        = string
  default     = "mongodb"
}

variable "mongodb_database" {
  description = "Banco do orchestrator no MongoDB."
  type        = string
  default     = "mechanical_hub_orchestrator"
}

variable "mongodb_persistence_enabled" {
  description = <<-EOT
    true: dados em PVC na StorageClass gp3 do mechanical-hub-infra (EBS CSI).
    false: emptyDir — use se o teste do driver EBS CSI falhar no Lab. Os dados
    somem quando o pod muda de no; o proximo apply recria replica set e usuario.
  EOT
  type        = bool
  default     = true
}

variable "mongodb_storage_class_name" {
  description = "Override da StorageClass do PVC. Vazio usa o output storage_class_name do mechanical-hub-infra."
  type        = string
  default     = ""
}

variable "mongodb_storage_size" {
  description = "Tamanho do volume de dados do MongoDB."
  type        = string
  default     = "5Gi"
}
