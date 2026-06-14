# EBS CSI driver: required for dynamic PVC provisioning on EKS (the in-tree
# kubernetes.io/aws-ebs provisioner that ships gp2 by default no longer works).
# Argo Workflows' volumeClaimTemplates (e.g. workflow-template-ci.yaml's
# "workdir" PVC) rely on this StorageClass being the cluster default.
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = module.security.ebs_csi_driver_role_arn
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.security]
}

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type = "gp3"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}
