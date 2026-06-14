terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  tags = {
    Project   = "argo-cicd-platform"
    ManagedBy = "terraform"
  }

  # Account root user and the IAM principal running Terraform always get
  # cluster-admin EKS access, plus any extra principals supplied via
  # var.eks_admin_principal_arns. The Terraform principal must be included:
  # switching authentication_mode to API_AND_CONFIG_MAP drops the implicit
  # "cluster creator" admin access that mode CONFIG_MAP granted, so without
  # an explicit access entry the kubernetes/helm providers (using this same
  # principal via `aws eks get-token`) would lose access to the cluster.
  eks_admin_principal_arns = distinct(concat(
    [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
      data.aws_caller_identity.current.arn,
    ],
    var.eks_admin_principal_arns
  ))
}

# Authenticate the kubernetes/helm providers against the EKS cluster created by
# module.eks using `aws eks get-token` (exec plugin) rather than a static
# `aws_eks_cluster_auth` token. EKS auth tokens are only valid for 15 minutes; a
# static token fetched once at the start of `terraform apply` can expire before
# Terraform reaches the helm_release resources (after VPC/EKS/node group/OIDC/IRSA
# have all been created), causing "the server has asked for the client to provide
# credentials" errors. `exec` fetches a fresh token for every API call instead.
# Requires AWS CLI v2 on the machine running Terraform, using the same credentials
# as the "aws" provider above.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}
