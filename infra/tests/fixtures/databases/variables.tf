variable "project" {
  description = "Prefixo dos recursos."
  type        = string
  default     = "mhub-test"
}

variable "environment" {
  description = "Ambiente (sufixo dos nomes)."
  type        = string
  default     = "test"
}

variable "databases" {
  description = "Mesmo formato da variavel databases do modulo raiz."
  type = map(object({
    db_name           = string
    db_username       = optional(string, "mechanical_hub_admin")
    app_username      = string
    instance_class    = optional(string, "db.t3.micro")
    allocated_storage = optional(number, 20)
  }))
}

variable "db_passwords" {
  description = "Senha master por servico."
  type        = map(string)
  sensitive   = true
}

variable "vpc_id" {
  description = "VPC de teste."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas de teste."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs liberados na porta do banco."
  type        = list(string)
}
