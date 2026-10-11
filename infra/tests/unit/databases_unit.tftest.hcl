# Modulo raiz: uma instancia RDS por servico SQL (ADR-0004) e o contrato de
# outputs (secao 3 da spec do mechanical-hub-database).
#
# Rodar a partir de infra/:
#   terraform test -test-directory=tests/unit -filter=tests/unit/databases_unit.tftest.hcl

mock_provider "aws" {
  mock_resource "aws_db_instance" {
    defaults = {
      address = "mock.us-east-1.rds.amazonaws.com"
      port    = 5432
    }
  }
}
mock_provider "kubernetes" {}
mock_provider "random" {}

variables {
  db_passwords = { orders = "placeholder", stock = "placeholder", billing = "placeholder" }

  vpc_id               = "vpc-mock00001"
  private_subnet_ids   = ["subnet-mock0001", "subnet-mock0002"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

  eks_cluster_name           = "mhub-test"
  eks_cluster_endpoint       = "https://mock.eks.amazonaws.com"
  eks_cluster_ca_certificate = "bW9jaw=="
  mongodb_storage_class_name = "gp3"
}

run "one_instance_per_sql_service" {
  command = plan

  assert {
    condition     = toset(keys(module.rds)) == toset(["orders", "stock", "billing"])
    error_message = "Deveria existir uma instancia RDS para orders, stock e billing."
  }

  assert {
    condition     = length(distinct([for rds in module.rds : rds.identifier])) == 3
    error_message = "Os identificadores das tres instancias precisam ser distintos."
  }

  assert {
    condition = alltrue([
      for service, rds in module.rds :
      rds.identifier == "mechanical-hub-${service}-production"
    ])
    error_message = "O identificador deveria seguir mechanical-hub-<servico>-<ambiente>."
  }

  assert {
    condition     = alltrue([for rds in module.rds : rds.publicly_accessible == false])
    error_message = "Nenhuma instancia pode ser publica (ADR-0002)."
  }

  assert {
    condition     = length(distinct([for rds in module.rds : rds.subnet_group_name])) == 3
    error_message = "Cada instancia deveria ter seu proprio DB subnet group."
  }
}

run "outputs_follow_the_contract" {
  command = plan

  assert {
    condition     = toset(keys(output.databases)) == toset(["orders", "stock", "billing"])
    error_message = "O output databases deveria ter uma chave por servico SQL."
  }

  assert {
    condition = alltrue([
      for service, db in output.databases :
      db.db_name == "mechanical_hub_${service}" && db.app_username == "${service}_app"
    ])
    error_message = "databases deveria trazer db_name e app_username de cada servico."
  }

  assert {
    condition     = output.auth_database.db_name == "mechanical_hub_orders"
    error_message = "auth_database deveria apontar para o banco do orders."
  }

  assert {
    condition     = toset(keys(output.rds_security_group_ids)) == toset(["orders", "stock", "billing"])
    error_message = "rds_security_group_ids deveria ter uma chave por servico SQL."
  }

  assert {
    condition     = output.mongodb_replica_set == "rs0" && output.mongodb_database == "mechanical_hub_orchestrator"
    error_message = "Outputs do MongoDB fora do contrato."
  }
}

run "fails_without_a_password_per_service" {
  command = plan

  variables {
    db_passwords = { orders = "placeholder", stock = "placeholder" }
  }

  expect_failures = [terraform_data.db_passwords_precondition]
}

run "fails_without_the_orders_database" {
  command = plan

  variables {
    databases = {
      stock = { db_name = "mechanical_hub_stock", app_username = "stock_app" }
    }
  }

  # auth_database aponta para a instancia do orders.
  expect_failures = [var.databases]
}

run "fails_without_the_cluster" {
  command = plan

  variables {
    eks_cluster_name           = ""
    eks_cluster_endpoint       = ""
    eks_cluster_ca_certificate = ""
  }

  expect_failures = [terraform_data.cluster_precondition]
}

run "emptydir_does_not_need_a_storage_class" {
  command = plan

  variables {
    mongodb_storage_class_name  = ""
    mongodb_persistence_enabled = false
  }
}

run "persistence_without_storage_class_fails" {
  command = plan

  variables {
    mongodb_storage_class_name = ""
  }

  expect_failures = [terraform_data.cluster_precondition]
}
