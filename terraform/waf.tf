# The ALB itself is created later by the AWS Load Balancer Controller in response to
# the Argo-managed Ingress (see argo/rollouts/rollout-production.yaml). On the first
# `terraform apply` this data source returns no results, so no association is created.
# Re-run `terraform apply` after the Ingress exists to attach the WAF Web ACL to the ALB.
# No depends_on here on purpose: a depends_on referencing a resource created in this
# apply would make `arns` unknown-until-apply, which breaks for_each below. Without
# it, this is a plain AWS API read - on the first apply it returns an empty (but
# known) set since no ALB exists yet; re-run `terraform apply` after the Argo
# Ingress creates the ALB to pick it up and create the WAF association.
data "aws_lbs" "app" {
  tags = {
    "elbv2.k8s.aws/cluster" = module.eks.cluster_name
  }
}

data "aws_lb" "app" {
  for_each = data.aws_lbs.app.arns
  arn      = each.value
}

resource "aws_wafv2_web_acl_association" "alb" {
  for_each = data.aws_lbs.app.arns

  resource_arn = each.value
  web_acl_arn  = module.security.waf_web_acl_arn
}
