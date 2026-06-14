#!/usr/bin/env bash
# Removes the Argo ecosystem + monitoring stack from the EKS cluster. Run BEFORE
# `terraform destroy` so the AWS Load Balancer Controller and ExternalDNS get a
# chance to clean up the ALB and Route 53 records they created for the app's
# Ingress (deleting the EKS cluster first would orphan those AWS resources).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Deleting Argo-managed app resources (releases the ALB + DNS records)"
kubectl delete -f "${REPO_ROOT}/argo/rollouts/" --ignore-not-found
kubectl delete -f "${REPO_ROOT}/argo/cron/" --ignore-not-found
kubectl delete -f "${REPO_ROOT}/argo/events/" --ignore-not-found
kubectl delete -f "${REPO_ROOT}/argo/workflows/" --ignore-not-found
helm uninstall argo-cicd-app --namespace staging || true
helm uninstall argo-cicd-app --namespace production || true

echo "==> Waiting for the ALB to be deprovisioned..."
sleep 30

echo "==> Uninstalling kube-prometheus-stack (namespace: monitoring)"
helm uninstall prometheus-stack --namespace monitoring || true

echo "==> Uninstalling Argo Rollouts (namespace: argo-rollouts)"
helm uninstall argo-rollouts --namespace argo-rollouts || true

echo "==> Uninstalling Argo Events (namespace: argo-events)"
helm uninstall argo-events --namespace argo-events || true

echo "==> Uninstalling Argo Workflows (namespace: argo)"
helm uninstall argo-workflows --namespace argo || true

echo "==> Deleting namespaces"
for ns in monitoring argo-rollouts argo-events argo staging production; do
  kubectl delete namespace "${ns}" --ignore-not-found
done

cat <<'EOF'

==> Argo components removed.

Next step: tear down the AWS infrastructure
  cd terraform && terraform destroy
EOF
