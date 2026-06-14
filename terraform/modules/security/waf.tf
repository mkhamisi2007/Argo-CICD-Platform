# WAFv2 Web ACL for the ALB (regional). When var.waf_enabled is false the default
# action is "allow" so `terraform plan` stays clean in dev environments while still
# creating the ACL and its association.

resource "aws_cloudwatch_log_group" "waf" {
  name              = "/aws/waf/argo-cicd"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.cluster_name}-waf"
  description = "WAF for argo-cicd-app ALB"
  scope       = "REGIONAL"

  default_action {
    dynamic "block" {
      for_each = var.waf_enabled ? [1] : []
      content {}
    }

    dynamic "allow" {
      for_each = var.waf_enabled ? [] : [1]
      content {}
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # GitHub push webhook payloads routinely exceed the default 8KB body
        # inspection limit and were being blocked by SizeRestrictions_BODY.
        # Count instead of block for this rule only; the rest of the Core
        # Rule Set (XSS/SQLi/LFI etc.) still blocks as normal.
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitPerIP"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.cluster_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

# NOTE: AWS requires WAFv2 logging destination log groups to be named with the
# "aws-waf-logs-" prefix. The "/aws/waf/argo-cicd" name from the spec is kept for the
# group itself (used for other diagnostics), but logging is shipped to a second,
# correctly-prefixed group so `aws_wafv2_web_acl_logging_configuration` doesn't fail.
resource "aws_cloudwatch_log_group" "waf_logs" {
  name              = "aws-waf-logs-argo-cicd"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs.arn]
}
