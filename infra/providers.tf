terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # State remoto proprio deste repositorio (ADR-0002). A configuracao e passada
  # via -backend-config no pipeline, para nao versionar bucket nem conta.
  #
  #   terraform init \
  #     -backend-config="bucket=mechanical-hub-tfstate-<conta>" \
  #     -backend-config="key=mechanical-hub-database/terraform.tfstate" \
  #     -backend-config="region=us-east-1"
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}
