# Resolucao de rede no modulo raiz: remote state do mechanical-hub-infra com
# fallback por variavel, e a precondicao que barra as combinacoes invalidas.
#
# Nenhum run informa infra_state_bucket — com ele vazio o data source
# terraform_remote_state tem count = 0 e o teste nao toca no S3.
#
# Rodar a partir de infra/:
#   terraform test -filter=tests/unit/network_unit.tftest.hcl

mock_provider "aws" {}

variables {
  db_password = "placeholder-password"
}

# ── Caminhos de erro ─────────────────────────────────────────────────────────

run "fails_without_remote_state_or_overrides" {
  command = plan

  # Sem infra_state_bucket e sem overrides: e o erro de quem aplica este
  # repositorio antes do mechanical-hub-infra.
  expect_failures = [terraform_data.network_precondition]
}

run "fails_with_a_single_private_subnet" {
  command = plan

  variables {
    vpc_id               = "vpc-mock00001"
    private_subnet_ids   = ["subnet-mock0001"]
    private_subnet_cidrs = ["10.0.11.0/24"]
  }

  # O DB subnet group exige subnets em ao menos duas AZs.
  expect_failures = [terraform_data.network_precondition]
}

run "fails_without_any_cidr_to_allow" {
  command = plan

  variables {
    vpc_id             = "vpc-mock00001"
    private_subnet_ids = ["subnet-mock0001", "subnet-mock0002"]
  }

  # Sem CIDR nao ha regra de ingress e o banco ficaria inalcancavel.
  expect_failures = [terraform_data.network_precondition]
}

run "fails_when_vpc_id_is_missing" {
  command = plan

  variables {
    private_subnet_ids   = ["subnet-mock0001", "subnet-mock0002"]
    private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  }

  expect_failures = [terraform_data.network_precondition]
}

# ── Caminho feliz ────────────────────────────────────────────────────────────

run "overrides_resolve_the_network" {
  command = plan

  variables {
    vpc_id               = "vpc-mock00001"
    private_subnet_ids   = ["subnet-mock0001", "subnet-mock0002"]
    private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  }

  assert {
    condition     = output.vpc_id == "vpc-mock00001"
    error_message = "O override de vpc_id deveria ter precedencia e chegar ao output."
  }

  assert {
    condition     = length(output.private_subnet_ids) == 2
    error_message = "As duas subnets informadas por override deveriam chegar ao DB subnet group."
  }
}
