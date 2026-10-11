# Bancos por servico para o teste de integracao.
#
# Reproduz o `module "rds"` do modulo raiz — for_each sobre o mapa de servicos
# — sem o resto da raiz (remote state, cluster EKS e MongoDB), que nao existe
# no LocalStack. O teste passa um mapa com um servico so para economizar.
#
# Nao e usada por nenhum caminho de producao.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

module "rds" {
  source   = "../../../modules/rds"
  for_each = var.databases

  project     = var.project
  environment = var.environment
  service     = each.key

  vpc_id               = var.vpc_id
  private_subnet_ids   = var.private_subnet_ids
  private_subnet_cidrs = var.private_subnet_cidrs

  db_instance_class = each.value.instance_class
  db_name           = each.value.db_name
  db_username       = each.value.db_username
  db_password       = var.db_passwords[each.key]
  allocated_storage = each.value.allocated_storage

  tags = { ManagedBy = "terraform-test" }
}
