# Teste de integracao do modulo rds contra o LocalStack.
#
# Pre-requisito — LocalStack ouvindo em http://localhost:4566:
#   docker run --rm -d -p 4566:4566 localstack/localstack
#
# Rodar a partir de infra/:
#   terraform test -filter=tests/integration/rds_integration.tftest.hcl
#
# Adaptado do teste homonimo do mechanical-hub. Duas mudancas em relacao ao
# original: nao ha mais a variavel eks_sg_id (a ADR-0002 trocou a liberacao por
# security group pela liberacao por CIDR) e a rede vem de uma fixture local, ja
# que o modulo de VPC pertence ao mechanical-hub-infra.

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
    source = "../fixtures/network"
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

# Passo 2: o banco, usando a rede do passo 1.
run "rds_instance_is_created" {
  command = apply

  module {
    source = "../../modules/rds"
  }

  variables {
    project              = "mhub-test"
    environment          = "test"
    vpc_id               = run.setup_network.vpc_id
    private_subnet_ids   = run.setup_network.private_subnet_ids
    private_subnet_cidrs = run.setup_network.private_subnet_cidrs
    db_instance_class    = "db.t3.micro"
    db_name              = "mechanical_hub"
    db_username          = "mechanical_hub"
    db_password          = "test-password-123"
    allocated_storage    = 20
    tags                 = { ManagedBy = "terraform" }
  }

  assert {
    condition     = output.endpoint != ""
    error_message = "RDS endpoint esta vazio — a instancia nao foi criada."
  }

  assert {
    condition     = output.port == 5432
    error_message = "A porta do RDS deveria ser 5432."
  }

  assert {
    condition     = output.db_name == "mechanical_hub"
    error_message = "O nome do banco nao confere."
  }

  assert {
    condition     = output.security_group_id != ""
    error_message = "O security group do banco nao foi criado."
  }

  assert {
    condition     = output.subnet_group_name == "mhub-test-test-db-subnet-group"
    error_message = "O DB subnet group nao segue o padrao <project>-<environment>-db-subnet-group."
  }
}

# Passo 3: a liberacao por CIDR (ADR-0002) chegou de fato ao security group.
run "ingress_rules_match_private_cidrs" {
  command = apply

  module {
    source = "../../modules/rds"
  }

  variables {
    project              = "mhub-test"
    environment          = "test"
    vpc_id               = run.setup_network.vpc_id
    private_subnet_ids   = run.setup_network.private_subnet_ids
    private_subnet_cidrs = run.setup_network.private_subnet_cidrs
    db_instance_class    = "db.t3.micro"
    db_name              = "mechanical_hub"
    db_username          = "mechanical_hub"
    db_password          = "test-password-123"
    allocated_storage    = 20
    tags                 = { ManagedBy = "terraform" }
  }

  assert {
    condition     = length(aws_security_group_rule.postgres_from_private_subnets) == 2
    error_message = "Deveria existir uma regra de ingress para cada subnet privada."
  }

  assert {
    condition     = length(aws_security_group_rule.postgres_from_security_groups) == 0
    error_message = "Sem allowed_security_group_ids nao deveria haver regra por security group."
  }
}
