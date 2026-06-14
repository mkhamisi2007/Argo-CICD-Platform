# IRSA roles (and the WAF Web ACL, bundled in the same "security" module) require the
# EKS OIDC provider to exist first.
module "security" {
  source = "./modules/security"

  cluster_name       = var.cluster_name
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  ecr_repository_arn = aws_ecr_repository.app.arn

  waf_enabled = var.waf_enabled

  tags = local.tags

  depends_on = [module.eks]
}
