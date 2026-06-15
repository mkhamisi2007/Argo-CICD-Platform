# Six IRSA roles, each trusted by the EKS OIDC provider and scoped to a single
# Kubernetes service account via the "sub" condition.

locals {
  oidc_sub_argo_workflows      = "system:serviceaccount:argo:argo-workflows"
  oidc_sub_alb_controller      = "system:serviceaccount:kube-system:aws-load-balancer-controller"
  oidc_sub_external_dns        = "system:serviceaccount:kube-system:external-dns"
  oidc_sub_autoscaler          = "system:serviceaccount:kube-system:cluster-autoscaler"
  oidc_sub_ebs_csi_driver      = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
  oidc_sub_cloudwatch_exporter = "system:serviceaccount:monitoring:cloudwatch-exporter"
}

# --- 1. argo-workflows-ecr ---

data "aws_iam_policy_document" "argo_workflows_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = [local.oidc_sub_argo_workflows]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "argo_workflows_ecr" {
  name               = "argo-workflows-ecr"
  assume_role_policy = data.aws_iam_policy_document.argo_workflows_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "argo_workflows_ecr" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_role_policy" "argo_workflows_ecr" {
  name   = "ecr-push"
  role   = aws_iam_role.argo_workflows_ecr.id
  policy = data.aws_iam_policy_document.argo_workflows_ecr.json
}

# --- 2. aws-load-balancer-controller ---

data "aws_iam_policy_document" "alb_controller_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = [local.oidc_sub_alb_controller]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_trust.json
  tags               = var.tags
}

resource "aws_iam_policy" "alb_controller" {
  name   = "AWSLoadBalancerControllerIAMPolicy-${var.cluster_name}"
  policy = file("${path.module}/policies/alb-controller-policy.json")
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# --- 3. external-dns ---

data "aws_iam_policy_document" "external_dns_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = [local.oidc_sub_external_dns]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "external_dns" {
  statement {
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "external_dns" {
  name   = "route53-dns-management"
  role   = aws_iam_role.external_dns.id
  policy = data.aws_iam_policy_document.external_dns.json
}

# --- 4. cluster-autoscaler ---

data "aws_iam_policy_document" "cluster_autoscaler_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = [local.oidc_sub_autoscaler]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeInstanceTypes",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name   = "cluster-autoscaler"
  role   = aws_iam_role.cluster_autoscaler.id
  policy = data.aws_iam_policy_document.cluster_autoscaler.json
}

# --- 5. ebs-csi-controller (aws-ebs-csi-driver addon) ---

data "aws_iam_policy_document" "ebs_csi_driver_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = [local.oidc_sub_ebs_csi_driver]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "ebs-csi-controller"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# --- 6. cloudwatch-exporter (yet-another-cloudwatch-exporter, WAF metrics) ---

data "aws_iam_policy_document" "cloudwatch_exporter_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = [local.oidc_sub_cloudwatch_exporter]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudwatch_exporter" {
  name               = "cloudwatch-exporter"
  assume_role_policy = data.aws_iam_policy_document.cloudwatch_exporter_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "cloudwatch_exporter" {
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "tag:GetResources",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cloudwatch_exporter" {
  name   = "cloudwatch-read"
  role   = aws_iam_role.cloudwatch_exporter.id
  policy = data.aws_iam_policy_document.cloudwatch_exporter.json
}
