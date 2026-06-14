output "argo_workflows_ecr_role_arn" {
  description = "IAM role ARN for the argo-workflows service account (ECR push)"
  value       = aws_iam_role.argo_workflows_ecr.arn
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for the aws-load-balancer-controller service account"
  value       = aws_iam_role.alb_controller.arn
}

output "external_dns_role_arn" {
  description = "IAM role ARN for the external-dns service account"
  value       = aws_iam_role.external_dns.arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for the cluster-autoscaler service account"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for the ebs-csi-controller-sa service account"
  value       = aws_iam_role.ebs_csi_driver.arn
}

output "waf_web_acl_arn" {
  description = "ARN of the WAFv2 Web ACL"
  value       = aws_wafv2_web_acl.this.arn
}

output "waf_web_acl_id" {
  description = "ID of the WAFv2 Web ACL"
  value       = aws_wafv2_web_acl.this.id
}
