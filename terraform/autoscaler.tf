# Cluster Autoscaler — scales the EKS managed node group's ASG based on pending pods.
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.security.cluster_autoscaler_role_arn
  }

  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }

  depends_on = [module.security]
}

# Discovery tags Cluster Autoscaler's autoDiscovery uses to find the node group's ASG.
resource "aws_autoscaling_group_tag" "enabled" {
  autoscaling_group_name = module.eks.node_group_asg_name

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "cluster_owned" {
  autoscaling_group_name = module.eks.node_group_asg_name

  tag {
    key                 = "k8s.io/cluster-autoscaler/${module.eks.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}
