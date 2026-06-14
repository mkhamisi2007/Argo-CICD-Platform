#!/usr/bin/env bash
# Installs the Argo ecosystem + monitoring stack onto an existing EKS cluster.
# Run AFTER `terraform apply` (cluster, IRSA roles, ALB controller, ExternalDNS,
# Cluster Autoscaler must already exist) and with kubectl/helm pointed at that
# cluster (`aws eks update-kubeconfig --name <cluster_name> --region <region>`).
#
# Required env var:
#   SLACK_WEBHOOK_URL - Slack incoming webhook used by CI/CD + health-check alerts
set -euo pipefail

: "${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL must be set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Adding Helm repositories"
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "==> Creating namespaces"
for ns in argo argo-events argo-rollouts monitoring staging production; do
  kubectl get namespace "${ns}" >/dev/null 2>&1 || kubectl create namespace "${ns}"
done

echo "==> [1/5] Installing Argo Workflows (namespace: argo)"
helm upgrade --install argo-workflows argo/argo-workflows \
  --namespace argo \
  --set server.extraArgs[0]="--auth-mode=server"

echo "==> [2/5] Installing Argo Events (namespace: argo-events)"
helm upgrade --install argo-events argo/argo-events \
  --namespace argo-events

echo "==> [3/5] Installing Argo Rollouts (namespace: argo-rollouts)"
helm upgrade --install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts

echo "==> [4/5] Installing Argo Rollouts kubectl plugin"
if command -v kubectl-argo-rollouts >/dev/null 2>&1; then
  echo "    kubectl-argo-rollouts already installed: $(kubectl-argo-rollouts version --short 2>/dev/null || true)"
else
  os="$(uname | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "${arch}" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
  esac
  plugin_url="https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-${os}-${arch}"
  echo "    Downloading ${plugin_url}"
  curl -fsSL -o /usr/local/bin/kubectl-argo-rollouts "${plugin_url}"
  chmod +x /usr/local/bin/kubectl-argo-rollouts
fi

echo "==> [5/5] Installing kube-prometheus-stack (namespace: monitoring)"
helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f "${REPO_ROOT}/monitoring/prometheus-values.yaml" \
  --set-string alertmanager.config.receivers[0].slack_configs[0].api_url="${SLACK_WEBHOOK_URL}"

echo "==> Creating slack-webhook Secrets (used by Argo Workflows/CronWorkflow)"
for ns in argo production; do
  kubectl create secret generic slack-webhook \
    --from-literal=url="${SLACK_WEBHOOK_URL}" \
    --namespace "${ns}" \
    --dry-run=client -o yaml | kubectl apply -f -
done

echo "==> Setting Argo Rollouts notification secret (namespace: production)"
kubectl create secret generic argo-rollouts-notification-secret \
  --from-literal=slack-webhook-url="${SLACK_WEBHOOK_URL}" \
  --namespace production \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'EOF'

==> Bootstrap complete.

Next steps:
  1. Fill in the placeholders in argo/workflows/serviceaccount.yaml,
     argo/events/event-source-github.yaml, argo/events/sensor-github.yaml and
     argo/rollouts/rollout-production.yaml using your `terraform output` values.
  2. kubectl apply -f argo/workflows/
  3. kubectl apply -f argo/events/
  4. kubectl apply -f argo/rollouts/
  5. kubectl apply -f argo/cron/
EOF
