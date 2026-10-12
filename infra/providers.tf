terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

# Cluster do mechanical-hub-infra (eks_cluster_endpoint, eks_cluster_ca_certificate
# e eks_cluster_name do state dele — ADR-0002), onde roda o MongoDB. O token
# vem do `aws eks get-token`, com as mesmas credenciais do provider aws; no
# pipeline nao ha kubeconfig envolvido no apply.
provider "kubernetes" {
  host                   = local.eks_cluster_endpoint == "" ? null : local.eks_cluster_endpoint
  cluster_ca_certificate = local.eks_cluster_ca_certificate == "" ? null : base64decode(local.eks_cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.eks_cluster_name, "--region", var.aws_region]
  }
}
