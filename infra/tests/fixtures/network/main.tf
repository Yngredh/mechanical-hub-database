# Rede minima para os testes de integracao.
#
# Este repositorio nao possui modulo de VPC — ela pertence ao
# mechanical-hub-infra (ADR-0002) e chega aqui via terraform_remote_state. Para
# testar o modulo rds isoladamente contra o LocalStack, criamos aqui apenas o
# necessario: uma VPC e duas subnets privadas em AZs distintas, que e o minimo
# exigido por um DB subnet group.
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

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc", ManagedBy = "terraform-test" }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = { Name = "${var.name}-private-${count.index}", ManagedBy = "terraform-test" }
}
