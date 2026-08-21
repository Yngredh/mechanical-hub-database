variable "name" {
  description = "Prefixo dos recursos criados pela fixture."
  type        = string
  default     = "mhub-db-test"
}

variable "vpc_cidr" {
  description = "CIDR da VPC de teste."
  type        = string
  default     = "10.88.0.0/16"
}

variable "availability_zones" {
  description = "AZs das subnets privadas. Minimo de duas para o DB subnet group."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas, um por AZ."
  type        = list(string)
  default     = ["10.88.11.0/24", "10.88.12.0/24"]
}
