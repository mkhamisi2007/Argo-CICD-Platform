variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1" # N. Virginia
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "argo-cicd-cluster"
}

variable "hosted_zone_name" {
  description = "Existing Route 53 hosted zone (e.g. example.com) used by ExternalDNS"
  type        = string
}

variable "app_hostname" {
  description = "Hostname for the production app Ingress (must be within hosted_zone_name)"
  type        = string
  default     = "app.m-khamisi.com"
}

variable "waf_enabled" {
  description = "Whether the WAF Web ACL should block (true) or allow (false) by default"
  type        = bool
  default     = true
}

variable "ecr_repo_name" {
  description = "Name of the ECR repository for the app image"
  type        = string
  default     = "argo-cicd-app"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS managed node group"
  type        = string
  default     = "t3.medium"
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 5
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL used for CI/CD and alerting notifications"
  type        = string
  sensitive   = true
}

variable "eks_admin_principal_arns" {
  description = "Extra IAM principal ARNs (in addition to the account root user) to grant cluster-admin EKS access entries, e.g. [\"arn:aws:iam::123456789012:user/alice\"]"
  type        = list(string)
  default     = []
}
