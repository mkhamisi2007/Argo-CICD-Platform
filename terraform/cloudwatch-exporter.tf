# CloudWatch exporter (yet-another-cloudwatch-exporter) — polls the AWS/WAFV2
# BlockedRequests metric for the Web ACL created in terraform/modules/security/waf.tf
# and exposes it to Prometheus, for the "WAF Blocked Requests" panel in
# monitoring/grafana-dashboard.json.
resource "helm_release" "cloudwatch_exporter" {
  name       = "cloudwatch-exporter"
  repository = "https://nerdswords.github.io/helm-charts"
  chart      = "yet-another-cloudwatch-exporter"
  namespace  = "monitoring"

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "cloudwatch-exporter"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.security.cloudwatch_exporter_role_arn
  }

  set {
    name  = "serviceMonitor.enabled"
    value = "true"
  }

  set {
    name  = "serviceMonitor.namespace"
    value = "monitoring"
  }

  values = [
    <<-EOT
    config: |
      apiVersion: v1alpha1
      sts-region: ${var.aws_region}
      static:
        - namespace: AWS/WAFV2
          name: waf-blocked-requests
          regions:
            - ${var.aws_region}
          dimensions:
            - name: WebACL
              value: ${var.cluster_name}-waf
            - name: Region
              value: ${var.aws_region}
            - name: Rule
              value: ALL
          metrics:
            - name: BlockedRequests
              statistics:
                - Sum
              period: 300
              length: 300
    EOT
  ]

  depends_on = [module.security]
}
