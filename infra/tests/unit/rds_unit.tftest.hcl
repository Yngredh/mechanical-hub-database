# Modulo rds: regras de ingress e postura da instancia.
#
# Cobre a mudanca de maior risco em relacao ao modulo herdado do
# mechanical-hub: a liberacao por CIDR das subnets privadas substituiu a
# liberacao pelo security group do EKS (ADR-0002). Um erro aqui — zero regras
# de ingress — so apareceria no apply, contra a AWS real.
#
# Rodar a partir de infra/:
#   terraform test -filter=tests/unit/rds_unit.tftest.hcl

mock_provider "aws" {
  mock_resource "aws_db_subnet_group" {
    defaults = {
      id   = "mhub-test-test-db-subnet-group"
      name = "mhub-test-test-db-subnet-group"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id  = "sg-mock000001"
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-mock000001"
    }
  }

  mock_resource "aws_security_group_rule" {
    defaults = {
      id = "sgrule-mock0001"
    }
  }

  mock_resource "aws_db_instance" {
    defaults = {
      id       = "mhub-test-test-postgres"
      address  = "mhub-test-test-postgres.mock.us-east-1.rds.amazonaws.com"
      endpoint = "mhub-test-test-postgres.mock.us-east-1.rds.amazonaws.com:5432"
      arn      = "arn:aws:rds:us-east-1:123456789012:db:mhub-test-test-postgres"
    }
  }
}

variables {
  project              = "mhub-test"
  environment          = "test"
  vpc_id               = "vpc-mock00001"
  private_subnet_ids   = ["subnet-mock0001", "subnet-mock0002"]
  private_subnet_cidrs = ["10.88.11.0/24", "10.88.12.0/24"]
  db_instance_class    = "db.t3.micro"
  db_name              = "mechanical_hub"
  db_username          = "mechanical_hub"
  db_password          = "test-password-123"
  allocated_storage    = 20
  tags                 = { ManagedBy = "terraform" }
}

run "one_ingress_rule_per_private_cidr" {
  command = plan

  module {
    source = "../../modules/rds"
  }

  assert {
    condition     = length(aws_security_group_rule.postgres_from_private_subnets) == length(var.private_subnet_cidrs)
    error_message = "Deveria existir exatamente uma regra de ingress por CIDR de subnet privada."
  }

  assert {
    condition = alltrue([
      for cidr in var.private_subnet_cidrs :
      contains(keys(aws_security_group_rule.postgres_from_private_subnets), cidr)
    ])
    error_message = "Todo CIDR informado precisa ter regra de ingress correspondente."
  }
}

run "no_extra_security_group_rules_by_default" {
  command = plan

  module {
    source = "../../modules/rds"
  }

  # ADR-0002: a liberacao e por CIDR justamente para nao depender do security
  # group das Lambdas, que sao criadas depois, no mechanical-hub-auth.
  assert {
    condition     = length(aws_security_group_rule.postgres_from_security_groups) == 0
    error_message = "Sem allowed_security_group_ids nao deveria haver regra por security group."
  }
}

run "extra_security_group_is_allowed_when_informed" {
  command = plan

  module {
    source = "../../modules/rds"
  }

  variables {
    allowed_security_group_ids = ["sg-extra00001"]
  }

  assert {
    condition     = length(aws_security_group_rule.postgres_from_security_groups) == 1
    error_message = "allowed_security_group_ids deveria gerar uma regra de ingress por security group."
  }
}

run "instance_is_private_and_encrypted" {
  command = plan

  module {
    source = "../../modules/rds"
  }

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false
    error_message = "O banco nunca pode ser exposto publicamente (ADR-0002)."
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted == true
    error_message = "A criptografia em repouso deveria estar habilitada por padrao."
  }

  assert {
    condition     = aws_db_instance.this.port == 5432
    error_message = "A porta padrao do PostgreSQL deveria ser 5432."
  }

  assert {
    condition     = aws_db_instance.this.engine == "postgres"
    error_message = "O engine deveria ser postgres (RFC-0001)."
  }
}

run "resource_names_carry_project_and_environment" {
  command = plan

  module {
    source = "../../modules/rds"
  }

  assert {
    condition     = aws_db_instance.this.identifier == "mhub-test-test-postgres"
    error_message = "O identifier deveria seguir o padrao <project>-<environment>-postgres."
  }

  assert {
    condition     = aws_db_subnet_group.this.subnet_ids == toset(var.private_subnet_ids)
    error_message = "O DB subnet group deveria conter exatamente as subnets privadas informadas."
  }
}
