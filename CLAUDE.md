# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A production-grade CI/CD platform on AWS/EKS built entirely on the Argo ecosystem:
`git push` → Argo Events → Argo Workflows (build/test/scan/push to ECR) → Argo
Workflows (deploy via Helm) → Argo Rollouts canary on EKS, behind an ALB protected by
AWS WAF, with Route53/ExternalDNS and a kube-prometheus-stack monitoring stack. See
`README.md` for the full architecture diagram and operational runbook (triggering
deploys, watching canaries, manual approval, rollback, teardown).

This repo has been deployed to a live EKS cluster and verified end-to-end: a real
`git push` flows through webhook → EventSource → Sensor → `ci-pipeline` →
`deploy-pipeline` → staging, manual approval → `deploy-pipeline` → production canary
Rollout, with both `staging.app.<domain>` and `app.<domain>` reachable over HTTPS. See
"Known gotchas from the live deploy" below for issues found this way and how they were
fixed.

If you're working in an environment **without** AWS/kubectl credentials, fall back to
static verification (fmt/validate/lint/template/parse) — the commands below cover both
cases.

## Commands

### Terraform (`terraform/`)
```bash
cd terraform
terraform fmt -recursive          # must be run before validate; auto-reformats modules/*
terraform init -backend=false      # no remote backend configured yet
terraform validate
```
There is no `terraform plan`/`apply` target in this environment (no AWS credentials) —
don't attempt it.

### Helm chart (`helm/app/`)
```bash
cd helm/app
helm lint .
helm template . -f values-staging.yaml
helm template . -f values-production.yaml
```
`values-staging.yaml` sets `rollout.enabled: false` (plain Deployment); production sets
it `true` and renders an `argoproj.io/v1alpha1 Rollout` instead of a Deployment — only
one of the two is ever templated by `templates/deployment.yaml`.

### App (`app/`)
```bash
cd app
pip install -r requirements-dev.txt
pytest -v                          # tests/test_main.py
python3 -m py_compile main.py
```

### Argo / monitoring manifests (`argo/`, `monitoring/`)
These are plain Kubernetes YAML (no templating) — validate with a YAML parser, e.g.:
```bash
python3 -c "import yaml,sys; list(yaml.safe_load_all(open(sys.argv[1])))" <file>
```
(PyYAML may not be installed system-wide due to PEP 668 — use a throwaway venv if
needed: `python3 -m venv /tmp/v && /tmp/v/bin/pip install pyyaml`.)

### Scripts (`scripts/`)
```bash
bash -n scripts/bootstrap.sh scripts/teardown.sh   # syntax check
```

## Architecture & cross-file conventions

### Layering and apply order
1. **`terraform/modules/vpc`** — VPC, 2 AZs, public+private subnets.
2. **`terraform/modules/eks`** — EKS 1.35 cluster + OIDC provider + managed node group.
   Exposes `oidc_provider_arn`/`oidc_provider_url` and `node_group_asg_name`.
3. **`terraform/modules/security`** — 4 IRSA roles (OIDC trust policies) +
   WAFv2 Web ACL. `depends_on module.eks` (needs the OIDC provider).
4. Root `terraform/*.tf` wires `helm_release` resources (AWS LB Controller,
   ExternalDNS, Cluster Autoscaler) that consume the IRSA role ARNs from
   `module.security` and `depends_on` it.
5. **`terraform/waf.tf`** associates the WAF Web ACL with the ALB via
   `data "aws_lbs"`/`data "aws_lb"` lookups by `elbv2.k8s.aws/cluster` tag. The ALB
   doesn't exist until the app's Ingress is applied (step 7), so this association is
   **empty on first `apply`** — a second `terraform apply` is required after the
   Argo manifests are deployed. This is intentional, not a bug.
6. **`scripts/bootstrap.sh`** installs Argo Workflows/Events/Rollouts +
   kube-prometheus-stack via Helm, creates namespaces, and creates the
   `slack-webhook` / `argo-rollouts-notification-secret` k8s Secrets directly
   (Terraform doesn't manage these — avoids a chicken-and-egg with namespace creation).
7. `kubectl apply -f argo/workflows/ | argo/events/ | argo/rollouts/ | argo/cron/`
   deploys the pipeline definitions, which is what eventually creates the Ingress/ALB
   (closing the loop back to step 5).

### Fixed resource names that must stay in sync
The Helm chart, the standalone `argo/rollouts/*.yaml` reference manifests, and the
Argo Workflows deploy pipeline all hardcode the same Kubernetes object names —
**do not switch these to templated/release-derived names**:
- `app-stable-svc`, `app-canary-svc` — Services referenced by
  `helm/app/templates/service.yaml`, the Rollout's `strategy.canary.{canaryService,stableService}`,
  and the smoke/integration-test URLs in `argo/workflows/workflow-template-deploy.yaml`.
- `app-ingress` — Ingress referenced by `strategy.canary.trafficRouting.alb.ingress`.
- `success-rate` — `AnalysisTemplate` name in `argo/rollouts/analysis-template.yaml`
  (namespace `production` only), referenced from `helm/app/values.yaml`'s
  `rollout.canary.steps[].analysis.templates[].templateName`.
- `github-eventsource-svc` — Service auto-created by the Argo Events EventSource
  controller for `argo/events/event-source-github.yaml` (name `github`), targeted by
  `argo/events/ingress-webhook.yaml`. If the EventSource's `metadata.name` ever
  changes, this Service name (and the Ingress backend) changes too.

### Shared ALB (IngressGroup)
`helm/app/templates/ingress.yaml` (staging + production) and
`argo/events/ingress-webhook.yaml` all carry
`alb.ingress.kubernetes.io/group.name: argo-cicd-platform`, so the AWS Load Balancer
Controller provisions **one ALB** for `app.m-khamisi.com`,
`staging.app.m-khamisi.com`, and `webhook.app.m-khamisi.com/push` (host/path-based
rules) — matching the single-ALB cost estimate in `README.md` and the single-ALB
assumption in `terraform/waf.tf`'s `data "aws_lbs" "app"` lookup. Each Ingress in the
group must have a distinct `host` (set via `.Values.ingress.host` in the Helm chart)
so their rules don't collide.

### Namespaces
`argo` (Workflows), `argo-events`, `argo-rollouts`, `monitoring`, `staging`,
`production`. The `success-rate` AnalysisTemplate and the Argo Rollouts notification
ConfigMap/Secret live in `production` only — this is why `values-staging.yaml` forces
`rollout.enabled: false` (a canary Rollout in staging would reference an
AnalysisTemplate that doesn't exist there).

### CI/CD pipeline shape (Argo Workflows)
- `argo/workflows/workflow-template-ci.yaml` ("ci-pipeline"): DAG
  `clone → build → [test, scan] → push-ecr → trigger-deploy`. All image builds use
  **Kaniko** (no Docker socket); `build` pushes `:{{image-tag}}` immediately so
  `test`/`scan` can validate the real pushed image, and `push-ecr` re-runs Kaniko
  (cache hit) to additionally tag `:latest`.
- `argo/workflows/workflow-template-deploy.yaml` ("deploy-pipeline"): 
  `deploy-helm (helm upgrade --install -f values-{{environment}}.yaml) → smoke-test →
  [staging only: approve (suspend) → integration-test → trigger-production]`. Has an
  `onExit` Slack notification handler reading a mounted `slack-webhook` Secret.
- Triggered by `argo/events/sensor-github.yaml`, which derives `image-tag` from the
  first 7 chars of the push SHA via a sprig `substr` dataTemplate.

### Domain and GitHub repo
The Route53 hosted zone (`m-khamisi.com`), app hostnames (`app.m-khamisi.com`,
`staging.app.m-khamisi.com`, `webhook.app.m-khamisi.com`), and GitHub repo
(`mkhamisi2007/argo-cicd-platform`, in `argo/events/event-source-github.yaml`) are
already filled in across `terraform/terraform.tfvars.example`,
`terraform/variables.tf`, the Helm values files, and `argo/cron/health-check-cron.yaml`.

### Placeholders
Several manifests still contain `<UPPER_SNAKE_CASE>` placeholders (e.g. `<ECR_URI>`,
`<ARGO_WORKFLOWS_ECR_ROLE_ARN>`, `<SLACK_WEBHOOK_URL>`) that are filled in manually
after `terraform apply` using `terraform output` / `aws iam get-role` — see the table
in `README.md` step 3. These are intentional, not bugs or TODOs to
remove.

### Known gotchas from the live deploy
These were found by exercising the full pipeline against a real AWS account and are
now fixed in the repo — documented here so the underlying constraints aren't
reintroduced by future edits.

- **Every Ingress in the shared `argo-cicd-platform` IngressGroup needs
  `alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'`**
  (`helm/app/templates/ingress.yaml` / `helm/app/values.yaml`,
  `argo/events/ingress-webhook.yaml`). Without it, an Ingress with no `certificate-arn`
  defaults to `{"HTTP": 80}` only — and since the group's port-80 listener is taken
  over by another member's `ssl-redirect`, the AWS Load Balancer Controller **silently
  drops that Ingress's rule from the merged model with no warning or error at any log
  level**. If a host stops getting a TargetGroupBinding, check this annotation first.
- **The AWS Load Balancer Controller IAM policy
  (`terraform/modules/security/policies/alb-controller-policy.json`) must include
  `elasticloadbalancing:SetRulePriorities`** — needed once the shared IngressGroup has
  3+ member Ingresses (production/staging/webhook), since adding a new host rule
  requires reordering existing rule priorities. Missing this produces a
  `FailedDeployModel` / `AccessDenied` event on the affected Ingress, not a Terraform
  error (it's an IAM action, not a resource Terraform tracks for drift).
- **`module.eks.aws_eks_node_group.default` has
  `lifecycle.ignore_changes = [scaling_config[0].desired_size]`**
  (`terraform/modules/eks/main.tf`). Cluster Autoscaler changes `desired_size` at
  runtime; without `ignore_changes`, every `terraform apply` would scale the node
  group back to `var.node_desired_size` and could terminate nodes running live pods.
- **`argo/rollouts/rollout-production.yaml`'s `spec.selector.matchLabels` /
  `spec.template.metadata.labels` must exactly match the Helm chart's
  `selectorLabels`** (`app.kubernetes.io/name` + `app.kubernetes.io/instance`,
  from `helm/app/templates/_helpers.tpl`). `spec.selector` is effectively immutable —
  if a Rollout was ever created (e.g. by a raw `kubectl apply -f argo/rollouts/`)
  with different labels, `helm upgrade --install` will report success but silently
  no-op the selector change. Fix is to `kubectl delete rollout` (safe once 0 pods
  reference the old selector) and let the next `helm upgrade --install` recreate it.
- **`deploy-helm` in `argo/workflows/workflow-template-deploy.yaml` does NOT use
  `helm upgrade --install --wait`.** Helm's generic CRD-readiness wait looks for
  `status.conditions[].type == "Ready"`, which the Argo Rollouts CRD never sets (it
  uses `Healthy`/`Available`/`Progressing`/`Completed` instead) — `--wait` would block
  until `--timeout` and fail even when the Rollout is genuinely healthy. The
  `smoke-test` step (poll `/health`, 12x5s) is the readiness gate instead.
- **`argo-workflows-deployer` ClusterRole (`argo/workflows/rbac.yaml`) needs
  `namespaces: ["get", "create"]`** — `helm upgrade --install --create-namespace`
  in `deploy-helm` needs this to create `staging`/`production` if they don't exist.
- **`trigger-deploy` (in `workflow-template-ci.yaml`) and `trigger-production` (in
  `workflow-template-deploy.yaml`) must pass an explicit `release-name` parameter**
  (`argo-cicd-app`) — `deploy-pipeline`'s `release-name` argument has no default, and
  Argo Workflows rejects a child Workflow submission that's missing a
  required-with-no-default parameter (`invalid spec: spec.arguments.release-name...
  is required`).
