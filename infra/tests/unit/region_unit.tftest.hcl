# Validacao da variavel aws_region no modulo raiz.
#
# Usa mock_provider — nao precisa de credenciais AWS nem de LocalStack.
# Rodar a partir de infra/:
#   terraform test -filter=tests/unit/region_unit.tftest.hcl

mock_provider "aws" {}
mock_provider "kubernetes" {}
mock_provider "random" {}

# Rede resolvida por override para que o plan chegue ate a validacao da regiao
# sem esbarrar antes na precondicao de rede.
variables {
  db_passwords = { orders = "placeholder", stock = "placeholder", billing = "placeholder" }

  # Cluster resolvido por override: estes testes cobrem rede e regiao, nao o MongoDB.
  eks_cluster_name           = "mhub-test"
  eks_cluster_endpoint       = "https://mock.eks.amazonaws.com"
  eks_cluster_ca_certificate = "bW9jaw=="
  mongodb_storage_class_name = "gp3"
  vpc_id                     = "vpc-mock00001"
  private_subnet_ids         = ["subnet-mock0001", "subnet-mock0002"]
  private_subnet_cidrs       = ["10.0.11.0/24", "10.0.12.0/24"]
}

run "valid_region_us_east_1" {
  command = plan

  variables {
    aws_region = "us-east-1"
  }
}

run "valid_region_us_west_2" {
  command = plan

  variables {
    aws_region = "us-west-2"
  }
}

run "invalid_region_is_rejected" {
  command = plan

  variables {
    aws_region = "eu-west-1"
  }

  # O AWS Academy so libera us-east-1 e us-west-2.
  expect_failures = [var.aws_region]
}
