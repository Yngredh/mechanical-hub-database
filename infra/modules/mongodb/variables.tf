variable "namespace" {
  description = "Namespace do MongoDB. Criado pelo modulo."
  type        = string
  default     = "mongodb"
}

variable "name" {
  description = "Nome do StatefulSet e do Service headless (prefixo do host DNS do pod)."
  type        = string
  default     = "mongodb"
}

variable "image" {
  description = "Imagem do MongoDB. Mirror da AWS para o mongo oficial, evita o rate limit do Docker Hub."
  type        = string
  default     = "public.ecr.aws/docker/library/mongo:7.0"
}

variable "replica_set_name" {
  description = "Nome do replica set (--replSet). Transacoes multi-documento exigem replica set (ADR-0004)."
  type        = string
  default     = "rs0"
}

variable "port" {
  description = "Porta do mongod."
  type        = number
  default     = 27017
}

# ── Banco e usuario do orchestrator ──────────────────────────────────────────

variable "database" {
  description = "Banco do orchestrator. O usuario da aplicacao e criado nele (authSource)."
  type        = string
  default     = "mechanical_hub_orchestrator"
}

variable "app_username" {
  description = "Usuario do orchestrator, com readWrite apenas no banco `database`."
  type        = string
  default     = "orchestrator_app"
}

variable "root_username" {
  description = "Usuario root do MongoDB. So para administracao e para o Job de inicializacao."
  type        = string
  default     = "root"
}

# ── Recursos ─────────────────────────────────────────────────────────────────

variable "cpu_request" {
  description = "Request de CPU do mongod (infrastructure.md §3: ~0,25 vCPU)."
  type        = string
  default     = "250m"
}

variable "memory_request" {
  description = "Request de memoria do mongod (infrastructure.md §3: ~0,75 GiB)."
  type        = string
  default     = "768Mi"
}

variable "cpu_limit" {
  description = "Limite de CPU do mongod."
  type        = string
  default     = "500m"
}

variable "memory_limit" {
  description = "Limite de memoria do mongod."
  type        = string
  default     = "1Gi"
}

variable "wiredtiger_cache_size_gb" {
  description = "Cache do WiredTiger. Mantido bem abaixo do limite de memoria para o pod nao ser morto por OOM."
  type        = number
  default     = 0.25
}

# ── Armazenamento ────────────────────────────────────────────────────────────

variable "persistence_enabled" {
  description = <<-EOT
    true: PVC na StorageClass `storage_class_name` (EBS gp3, driver EBS CSI).
    false: emptyDir — os dados somem quando o pod sai do no; o Job de
    inicializacao recria replica set e usuario no proximo apply.
  EOT
  type        = bool
  default     = true
}

variable "storage_class_name" {
  description = "StorageClass do PVC (output storage_class_name do mechanical-hub-infra). Obrigatoria com persistencia."
  type        = string
  default     = null
}

variable "storage_size" {
  description = "Tamanho do volume de dados."
  type        = string
  default     = "5Gi"
}

variable "labels" {
  description = "Labels comuns aplicados aos objetos do Kubernetes."
  type        = map(string)
  default     = {}
}
