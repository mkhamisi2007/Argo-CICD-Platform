# argo-cicd-platform

A production-grade CI/CD platform on AWS: `git push` → Argo Events → Argo Workflows
(build/test/scan/push) → Argo Workflows (deploy) → Argo Rollouts canary on EKS, behind
an ALB protected by AWS WAF, with DNS automation and Prometheus/Grafana monitoring.

## Architecture

```mermaid
flowchart LR
    Dev[Developer] -->|git push main| GitHub

    subgraph EKS["EKS Cluster (private subnets)"]
        subgraph ArgoEvents["argo-events"]
            ES[EventSource: github]
            SE[Sensor: github]
        end

        subgraph Argo["argo"]
            CI[WorkflowTemplate: ci-pipeline]
            Deploy[WorkflowTemplate: deploy-pipeline]
            Cron[CronWorkflow: health-check]
        end

        subgraph Prod["production / staging"]
            Rollout[Argo Rollout: argo-cicd-app]
            Stable[app-stable-svc]
            Canary[app-canary-svc]
            Ingress[app-ingress]
        end

        subgraph KubeSystem["kube-system"]
            ALBC[AWS LB Controller]
            EDNS[ExternalDNS]
            CA[Cluster Autoscaler]
        end

        subgraph Monitoring["monitoring"]
            Prom[Prometheus]
            Graf[Grafana]
            AM[Alertmanager]
        end
    end

    GitHub -->|webhook push| ES --> SE -->|submit Workflow| CI
    CI -->|kaniko build/push| ECR[(ECR: argo-cicd-app)]
    CI -->|trivy scan + pytest| CI
    CI -->|submit Workflow| Deploy
    Deploy -->|helm upgrade --install| Rollout
    Rollout --> Stable & Canary
    Stable & Canary --> Ingress
    Ingress -->|creates/updates| ALB[ALB]
    ALBC -.manages.-> ALB
    EDNS -.manages.-> R53[(Route 53)]
    ALB --> R53
    WAF[AWS WAF] -.associated with.-> ALB
    Users[End users] -->|HTTPS| WAF
    Cron -->|curl /health, /metrics| ALB
    Prom -->|scrape /metrics, rollout metrics| Rollout
    Prom --> AM -->|alerts| Slack[Slack]
    Deploy -->|notify on failure| Slack
    Rollout -->|notify on rollback| Slack
    CA -.scales.-> Nodes[EC2 node group]
```

## Prerequisites

- [AWS CLI](https://docs.aws.amazon.com/cli/) v2, configured with credentials that can
  create VPC/EKS/IAM/ECR/WAF/Route53 resources
- [Terraform](https://developer.hashicorp.com/terraform) >= 1.5
- [kubectl](https://kubernetes.io/docs/tasks/tools/) >= 1.35
- [Helm](https://helm.sh/) >= 3.12
- [Argo CLI](https://argo-workflows.readthedocs.io/en/latest/walk-through/argo-cli/)
  and the [Argo Rollouts kubectl plugin](https://argo-rollouts.readthedocs.io/en/stable/installation/#kubectl-plugin)
  (the plugin is also installed by `scripts/bootstrap.sh`)
- An existing Route 53 **public hosted zone** you control (for `hosted_zone_name`)
- A Slack **incoming webhook URL** for CI/CD and alert notifications

## Setup

This repo includes a `Makefile` that wires together every step below in order. Run
`make help` at any time to see the full target list and the recommended run order.

### 0. Configure variables and secrets

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: hosted_zone_name, app_hostname, slack_webhook_url, aws_region, ...
cd ..

cp .env.example .env
# edit .env: SLACK_WEBHOOK_URL, GITHUB_PAT, GITHUB_WEBHOOK_SECRET
```

`.env` is gitignored and read automatically by `make bootstrap`,
`make fill-slack-secret`, and `make github-secret` — never commit it.

### 1. Provision AWS infrastructure

```bash
make tf-init
make tf-validate
make tf-apply
```

This creates the VPC, EKS cluster (private nodes), ECR repo, IRSA roles, WAF Web
ACL, and installs the AWS Load Balancer Controller, ExternalDNS and Cluster
Autoscaler via Helm.

### 2. Fill in placeholders from the Terraform outputs

```bash
make fill-placeholders
```

Replaces `<ECR_URI>` / `<ECR_REPO_URI>` / `<ARGO_WORKFLOWS_ECR_ROLE_ARN>` in
`helm/app/values.yaml`, `argo/rollouts/rollout-production.yaml`,
`argo/events/sensor-github.yaml`, `argo/workflows/workflow-template-deploy.yaml`, and
`argo/workflows/serviceaccount.yaml` using `terraform output`.

### 3. Point kubectl/helm at the new cluster

```bash
make kubeconfig
```

Runs `aws eks update-kubeconfig` using the `cluster_name`/`aws_region` from the
Terraform outputs.

### 4. Install the Argo ecosystem + monitoring

```bash
make bootstrap
```

Installs, in order: Argo Workflows (`argo`), Argo Events (`argo-events`), Argo
Rollouts (`argo-rollouts`), the `kubectl-argo-rollouts` plugin, and
`kube-prometheus-stack` (`monitoring`). Reads `SLACK_WEBHOOK_URL` from `.env`.

### 5. Fill in the Slack webhook placeholder

```bash
make fill-slack-secret
```

Replaces `<SLACK_WEBHOOK_URL>` in `argo/rollouts/analysis-template.yaml`. Reads
`SLACK_WEBHOOK_URL` from `.env`.

### 6. Create the GitHub webhook credentials secret

```bash
make github-secret
```

Creates the `github-access` Secret in `argo-events` (GitHub PAT + webhook shared
secret) from `GITHUB_PAT`/`GITHUB_WEBHOOK_SECRET` in `.env`. The PAT needs
`admin:repo_hook`/`repo` scope so the EventSource can auto-register the webhook.

> `argo/events/event-source-github.yaml` is already set up for the
> `mkhamisi2007/Argo-CICD-Platform` GitHub repo and the `m-khamisi.com` domain
> (`hosted_zone_name`/`app_hostname` in `terraform.tfvars.example`). Update these if
> you fork or rename the repo.

### 7. Apply the Argo manifests

```bash
make apply-argo
```

Applies `argo/workflows/`, `argo/events/` (including the GitHub webhook Ingress),
`argo/rollouts/`, and `argo/cron/`.

### 8. Re-run terraform apply to associate WAF with the ALB

```bash
make tf-apply
```

> WAF ↔ ALB association: the ALB is created by the AWS Load Balancer Controller only
> once the Ingresses from step 7 exist. This second `terraform apply` lets
> `aws_wafv2_web_acl_association` pick up the new ALB ARN.

## Triggering a deployment

Push to `main`:

```bash
git push origin main
```

The GitHub `push` webhook → `argo-events` Sensor → submits a Workflow from
`ci-pipeline` (clone → kaniko build → pytest + trivy scan → push to ECR → trigger
`deploy-pipeline` for `staging`).

Watch it:

```bash
argo list -n argo
argo logs -n argo @latest -f
```

## Watching a canary rollout

Once `deploy-pipeline` runs for `environment: production`, Argo Rollouts starts the
canary defined in `helm/app/templates/deployment.yaml` (10% → analysis → 50% →
analysis → 100%, ~2 minute pauses between steps).

```bash
kubectl argo rollouts get rollout argo-cicd-app -n production --watch
```

Or open the Argo Rollouts dashboard:

```bash
kubectl argo rollouts dashboard -n argo-rollouts
```

## Manually approving staging → production

`deploy-pipeline` suspends after the staging smoke test + integration test. List
suspended workflows and resume the one for your build:

```bash
argo list -n argo
argo resume -n argo <deploy-staging-xxxxx>
```

Resuming runs `trigger-production`, which submits a new `deploy-pipeline` Workflow
with `environment: production`.

## Forcing a rollback

If a canary analysis fails, Argo Rollouts aborts and rolls back automatically (and
posts to Slack via the notification subscription in
`argo/rollouts/analysis-template.yaml`). To force an abort/rollback manually:

```bash
kubectl argo rollouts abort argo-cicd-app -n production
kubectl argo rollouts undo argo-cicd-app -n production
```

## Estimated AWS cost

~**$80–120/month**, dominated by:

- 2× `t3.medium` EKS worker nodes (~$60/month)
- 1× NAT Gateway (~$33/month + data processing)
- 1× Application Load Balancer (~$16/month + LCU usage)
- AWS WAF Web ACL + rules (~$5–10/month + request volume)
- ECR storage (last 10 images, minimal)

EKS control plane (~$73/month) is **not** included above per AWS's current free
control-plane pricing in most regions — check current pricing for `eu-west-3`.

## Teardown

```bash
make teardown      # removes Argo/monitoring + the app's ALB & DNS records
make tf-destroy
```

Running `make teardown` first lets the AWS Load Balancer Controller and ExternalDNS
deprovision the ALB and Route 53 records before the VPC/EKS cluster they depend on
is destroyed.
