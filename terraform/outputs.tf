output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "ECR repository URI for image push"
  value       = aws_ecr_repository.app.repository_url
}

output "alb_dns_name" {
  description = "ALB DNS name (available after the Argo Ingress is applied and the ALB is provisioned)"
  value       = try([for lb in data.aws_lb.app : lb.dns_name][0], null)
}

output "waf_web_acl_arn" {
  description = "ARN of the WAFv2 Web ACL"
  value       = module.security.waf_web_acl_arn
}

output "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (for IRSA trust policies)"
  value       = module.eks.oidc_provider_arn
}

output "argo_workflows_ecr_role_arn" {
  description = "IAM role ARN for the argo-workflows service account (ECR push)"
  value       = module.security.argo_workflows_ecr_role_arn
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "aws_region" {
  description = "AWS region the cluster is deployed in"
  value       = var.aws_region
}
