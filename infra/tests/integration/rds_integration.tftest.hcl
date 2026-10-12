# Teste de integracao dos bancos por servico contra o LocalStack.
#
# Pre-requisito — LocalStack ouvindo em http://localhost:4566:
#   docker run --rm -d -p 4566:4566 localstack/localstack
#
# Rodar a partir de infra/:
#   terraform init -backend=false -test-directory=tests/integration
#   terraform test -test-directory=tests/integration
#
# A rede vem de uma fixture local (o modulo de VPC pertence ao
# mechanical-hub-infra) e os bancos da fixture `databases`, que repete o
# for_each do modulo raiz sobre o mapa de servicos. O modulo raiz inteiro nao
# roda aqui: ele tambem le o state do infra e cria o MongoDB no EKS.
#
# O mapa leva so o `orders` para economizar: o for_each e o mesmo para os tres
# servicos, e a cobertura de "tres instancias distintas" fica no teste
# unitario databases_unit.

provider "aws" {
  access_key = "test"
  secret_key = "test"
  region     = "us-east-1"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = "http://localhost:4566"
    rds = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

# Passo 1: rede de teste (VPC + duas subnets privadas em AZs distintas).
run "setup_network" {
  command = apply

  module {
    source = "./tests/fixtures/network"
  }

  variables {
    name                 = "mhub-db-test"
    vpc_cidr             = "10.88.0.0/16"
    availability_zones   = ["us-east-1a", "us-east-1b"]
    private_subnet_cidrs = ["10.88.11.0/24", "10.88.12.0/24"]
  }

  assert {
    condition     = length(output.private_subnet_ids) == 2
    error_message = "A fixture deveria criar duas subnets privadas."
  }
}

# Passo 2: os bancos, pelo mapa de servicos, usando a rede do passo 1.
run "databases_are_created_per_service" {
  command = apply

  module {
    source = "./tests/fixtures/databases"
  }

  variables {
    project              = "mhub-test"
    environment          = "test"
    vpc_id               = run.setup_network.vpc_id
    private_subnet_ids   = run.setup_network.private_subnet_ids
    private_subnet_cidrs = run.setup_network.private_subnet_cidrs

    databases = {
      orders = {
        db_name      = "mechanical_hub_orders"
        app_username = "orders_app"
      }
    }

    db_passwords = { orders = "test-password-123" }
  }

  assert {
    condition     = keys(output.databases) == ["orders"]
    error_message = "Deveria existir uma instancia por chave do mapa de servicos."
  }

  assert {
    condition     = output.databases["orders"].endpoint != ""
    error_message = "Endpoint do orders esta vazio — a instancia nao foi criada."
  }

  assert {
    condition     = output.databases["orders"].port == 5432
    error_message = "A porta do RDS deveria ser 5432."
  }

  assert {
    condition     = output.databases["orders"].db_name == "mechanical_hub_orders"
    error_message = "O nome do banco do orders nao confere."
  }

  assert {
    condition     = output.identifiers["orders"] == "mhub-test-orders-test"
    error_message = "O identificador nao segue o padrao <project>-<servico>-<environment>."
  }

  assert {
    condition     = output.subnet_group_names["orders"] == "mhub-test-orders-test-db-subnet-group"
    error_message = "O DB subnet group nao segue o padrao <project>-<servico>-<environment>-db-subnet-group."
  }

  assert {
    condition     = output.security_group_ids["orders"] != ""
    error_message = "O security group do orders nao foi criado."
  }

  # A liberacao por CIDR (ADR-0002) chegou ao security group.
  assert {
    condition     = output.ingress_cidr_blocks["orders"] == sort(run.setup_network.private_subnet_cidrs)
    error_message = "Deveria existir uma regra de ingress para cada subnet privada."
  }

  assert {
    condition     = length(output.ingress_security_group_ids["orders"]) == 0
    error_message = "Sem allowed_security_group_ids nao deveria haver regra por security group."
  }
}
