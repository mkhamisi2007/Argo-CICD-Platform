variable "cluster_name" {
  description = "EKS cluster name (used for resource naming/tags)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster's IAM OIDC provider"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS cluster's IAM OIDC provider (without https://)"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository the Argo Workflows IRSA role may push to"
  type        = string
}

variable "waf_enabled" {
  description = "When true, the WAF Web ACL default action blocks; when false, it allows (keeps plan clean in dev)"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Max requests per 5-minute window from a single IP before it is blocked"
  type        = number
  default     = 1000
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
