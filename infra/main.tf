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
# Banco de dados
# =============================================================================

module "rds" {
  source = "./modules/rds"

  project     = var.project
  environment = var.environment

  vpc_id                     = local.vpc_id
  private_subnet_ids         = local.private_subnet_ids
  private_subnet_cidrs       = local.private_subnet_cidrs
  allowed_security_group_ids = var.allowed_security_group_ids

  engine_version    = var.db_engine_version
  db_instance_class = var.db_instance_class
  db_name           = var.db_name
  db_username       = var.db_username
  db_password       = var.db_password
  db_port           = var.db_port
  allocated_storage = var.db_allocated_storage

  storage_encrypted       = var.db_storage_encrypted
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
  deletion_protection     = var.db_deletion_protection
  skip_final_snapshot     = var.db_skip_final_snapshot
  apply_immediately       = var.db_apply_immediately

  tags = local.common_tags

  depends_on = [terraform_data.network_precondition]
}
