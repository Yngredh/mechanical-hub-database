locals {
  common_tags = {
    Project     = var.project
    Component   = "database"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# =============================================================================
# Rede — consumida do repositorio mechanical-hub-infra
# =============================================================================
#
# ADR-0002: cada repositorio mantem seu proprio state e exporta outputs
# explicitos; os consumidores leem esses valores via terraform_remote_state,
# nunca por hardcode de IDs. Aqui lemos vpc_id, private_subnet_ids e os CIDRs
# das subnets privadas do state de `mechanical-hub-infra`.
#
# Fallback: se `infra_state_bucket` estiver vazio (repo infra ainda nao
# aplicado, ou execucao local/CI sem acesso ao state), as variaveis de override
# `vpc_id`, `private_subnet_ids` e `private_subnet_cidrs` sao usadas no lugar.

data "terraform_remote_state" "infra" {
  count = var.infra_state_bucket == "" ? 0 : 1

  backend = "s3"

  config = {
    bucket = var.infra_state_bucket
    key    = var.infra_state_key
    region = var.infra_state_region == "" ? var.aws_region : var.infra_state_region
  }
}

locals {
  infra_outputs = var.infra_state_bucket == "" ? null : data.terraform_remote_state.infra[0].outputs

  # Override explicito tem precedencia sobre o remote state — permite fixar um
  # valor pontualmente sem alterar o contrato entre repositorios. O try()
  # externo evita que a ausencia total de valor estoure aqui: quem reporta o
  # problema e a precondicao abaixo, com mensagem acionavel.
  # Fallback para "" (e nao null): passar null a uma variavel obrigatoria do
  # modulo produz um erro generico de "argument is required" que mascararia a
  # precondicao de rede abaixo, que e quem explica o que fazer.
  vpc_id = try(coalesce(
    var.vpc_id != "" ? var.vpc_id : null,
    try(local.infra_outputs.vpc_id, null),
  ), "")

  private_subnet_ids = try(coalesce(
    length(var.private_subnet_ids) > 0 ? var.private_subnet_ids : null,
    try(tolist(local.infra_outputs.private_subnet_ids), null),
  ), [])

  # Fallback final: o CIDR da VPC inteira, caso o repo infra ainda nao exporte
  # os CIDRs das subnets privadas. Menos granular, mas o banco continua fechado
  # ao mundo externo (publicly_accessible = false).
  private_subnet_cidrs = try(coalesce(
    length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : null,
    try(tolist(local.infra_outputs.private_subnet_cidrs), null),
    try([local.infra_outputs.vpc_cidr], null),
  ), [])
}

# Falha cedo e com mensagem clara quando a rede nao pode ser resolvida — e o
# erro mais provavel de quem aplica este repositorio antes do mechanical-hub-infra.
resource "terraform_data" "network_precondition" {
  lifecycle {
    precondition {
      condition     = local.vpc_id != "" && length(local.private_subnet_ids) >= 2
      error_message = <<-EOT
        Nao foi possivel resolver a rede.

        Aplique o mechanical-hub-infra primeiro e informe o state dele:
          -var="infra_state_bucket=mechanical-hub-tfstate-<conta>"

        Ou passe os valores diretamente:
          -var="vpc_id=vpc-..." -var='private_subnet_ids=["subnet-a","subnet-b"]'

        O DB subnet group exige ao menos duas subnets em AZs distintas.
      EOT
    }

    precondition {
      condition     = length(local.private_subnet_cidrs) > 0
      error_message = "Nenhum CIDR informado para liberar a porta do banco (ver private_subnet_cidrs)."
    }
  }
}

# =============================================================================
# Bancos de dados — uma instancia RDS por servico SQL (ADR-0004)
# =============================================================================
#
# Cada servico (orders, stock, billing) tem instancia, security group e subnet
# group proprios; nenhum servico alcanca o banco de outro por credencial. A
# instancia do `orders` assume o papel do antigo banco do monolito e tambem
# hospeda a role `mechanical_hub_auth` (output auth_database).

resource "terraform_data" "db_passwords_precondition" {
  lifecycle {
    precondition {
      # So o resultado booleano deixa de ser sensivel; as senhas nao aparecem.
      condition = nonsensitive(alltrue([
        for service in keys(var.databases) :
        length(lookup(var.db_passwords, service, "")) > 0
      ]))
      error_message = <<-EOT
        Falta a senha master de ao menos um servico em db_passwords.

        Informe uma senha por chave de `databases`, por exemplo:
          TF_VAR_db_passwords='{"orders":"...","stock":"...","billing":"..."}'

        No pipeline elas vem dos secrets DB_PASSWORD_ORDERS, DB_PASSWORD_STOCK e
        DB_PASSWORD_BILLING.
      EOT
    }
  }
}

module "rds" {
  source   = "./modules/rds"
  for_each = var.databases

  project     = var.project
  environment = var.environment
  service     = each.key

  vpc_id                     = local.vpc_id
  private_subnet_ids         = local.private_subnet_ids
  private_subnet_cidrs       = local.private_subnet_cidrs
  allowed_security_group_ids = var.allowed_security_group_ids

  engine_version    = var.db_engine_version
  db_instance_class = each.value.instance_class
  db_name           = each.value.db_name
  db_username       = each.value.db_username
  db_password       = lookup(var.db_passwords, each.key, "")
  db_port           = var.db_port
  allocated_storage = each.value.allocated_storage

  storage_encrypted       = var.db_storage_encrypted
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
  deletion_protection     = var.db_deletion_protection
  skip_final_snapshot     = var.db_skip_final_snapshot
  apply_immediately       = var.db_apply_immediately

  tags = local.common_tags

  depends_on = [
    terraform_data.network_precondition,
    terraform_data.db_passwords_precondition,
  ]
}

# =============================================================================
# MongoDB do orchestrator — StatefulSet no EKS do mechanical-hub-infra
# =============================================================================
#
# Cluster e StorageClass vem do state do mechanical-hub-infra (contrato:
# eks_cluster_name, eks_cluster_endpoint, eks_cluster_ca_certificate e
# storage_class_name). Os overrides seguem a mesma regra da rede: tem
# precedencia sobre o remote state.

locals {
  eks_cluster_name = try(coalesce(
    var.eks_cluster_name != "" ? var.eks_cluster_name : null,
    try(local.infra_outputs.eks_cluster_name, null),
  ), "")

  eks_cluster_endpoint = try(coalesce(
    var.eks_cluster_endpoint != "" ? var.eks_cluster_endpoint : null,
    try(local.infra_outputs.eks_cluster_endpoint, null),
  ), "")

  eks_cluster_ca_certificate = try(coalesce(
    var.eks_cluster_ca_certificate != "" ? var.eks_cluster_ca_certificate : null,
    try(local.infra_outputs.eks_cluster_ca_certificate, null),
  ), "")

  # Nulo no infra quando o driver EBS CSI esta desligado; nesse caso a
  # persistencia tem de ser desligada (mongodb_persistence_enabled = false).
  mongodb_storage_class_name = try(coalesce(
    var.mongodb_storage_class_name != "" ? var.mongodb_storage_class_name : null,
    try(local.infra_outputs.storage_class_name, null),
  ), "")
}

resource "terraform_data" "cluster_precondition" {
  lifecycle {
    precondition {
      condition     = local.eks_cluster_name != "" && local.eks_cluster_endpoint != "" && local.eks_cluster_ca_certificate != ""
      error_message = <<-EOT
        Nao foi possivel resolver o cluster EKS onde roda o MongoDB.

        Aplique o mechanical-hub-infra primeiro e informe o state dele:
          -var="infra_state_bucket=mechanical-hub-tfstate-<conta>"

        Ou passe eks_cluster_name, eks_cluster_endpoint e
        eks_cluster_ca_certificate diretamente.
      EOT
    }

    precondition {
      condition     = !var.mongodb_persistence_enabled || local.mongodb_storage_class_name != ""
      error_message = <<-EOT
        mongodb_persistence_enabled = true, mas nenhuma StorageClass foi
        resolvida (output storage_class_name do mechanical-hub-infra vazio).

        Ligue o driver EBS CSI no mechanical-hub-infra, informe
        mongodb_storage_class_name, ou rode com
        -var="mongodb_persistence_enabled=false" (emptyDir).
      EOT
    }
  }
}

module "mongodb" {
  source = "./modules/mongodb"

  namespace = var.mongodb_namespace
  database  = var.mongodb_database

  persistence_enabled = var.mongodb_persistence_enabled
  storage_class_name  = local.mongodb_storage_class_name == "" ? null : local.mongodb_storage_class_name
  storage_size        = var.mongodb_storage_size

  labels = {
    "mechanical-hub/project"     = var.project
    "mechanical-hub/environment" = var.environment
  }

  depends_on = [terraform_data.cluster_precondition]
}
