SHELL := /bin/bash
TF_DIR := terraform
HELM_DIR := helm/app

# Load SLACK_WEBHOOK_URL / GITHUB_PAT / GITHUB_WEBHOOK_SECRET from .env if present
# (copy .env.example to .env and fill in real values - .env is gitignored).
-include .env

# Override on the command line, e.g.:
#   make github-secret GITHUB_PAT=ghp_xxx GITHUB_WEBHOOK_SECRET=mysecret
#   make bootstrap SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
#   make approve-staging NAME=deploy-staging-xxxxx
# (command-line values always win over .env)
SLACK_WEBHOOK_URL ?=
GITHUB_PAT ?=
GITHUB_WEBHOOK_SECRET ?=
NAME ?=

.DEFAULT_GOAL := help
.PHONY: help \
	tf-init tf-fmt tf-validate tf-plan tf-apply tf-output tf-destroy \
	fill-placeholders fill-slack-secret \
	kubeconfig bootstrap github-secret \
	apply-workflows apply-events apply-rollouts apply-cron apply-argo \
	apply-grafana-dashboard \
	approve-staging stop-staging watch-canary rollback-production \
	helm-lint helm-template-staging helm-template-production \
	test teardown clean

help: ## Show this help and the recommended run order
	@echo "Recommended order:"
	@echo "  1.  make tf-init"
	@echo "  2.  make tf-validate"
	@echo "  3.  make tf-apply"
	@echo "  4.  make fill-placeholders"
	@echo "  5.  make kubeconfig"
	@echo "  6.  make bootstrap SLACK_WEBHOOK_URL=..."
	@echo "  7.  make fill-slack-secret SLACK_WEBHOOK_URL=..."
	@echo "  8.  make github-secret GITHUB_PAT=... GITHUB_WEBHOOK_SECRET=..."
	@echo "  9.  make apply-argo"
	@echo "  10. make tf-apply   (second pass: associates WAF with the new ALB)"
	@echo ""
	@echo "Operations:"
	@echo "  make approve-staging                             (promote the latest suspended staging build, stop other stale approvals)"
	@echo "  make approve-staging NAME=deploy-staging-xxxxx   (promote a specific build instead)"
	@echo "  make stop-staging NAME=deploy-staging-xxxxx      (discard one stale suspended approval manually)"
	@echo "  make watch-canary                                (watch the production canary rollout)"
	@echo "  make rollback-production                         (abort canary + roll back to previous stable)"
	@echo ""
	@echo "Teardown:"
	@echo "  make teardown"
	@echo "  make tf-destroy"
	@echo ""
	@echo "Targets:"
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-24s %s\n", $$1, $$2}'

## --- Terraform -------------------------------------------------------------

tf-init: ## terraform init (no remote backend configured)
	cd $(TF_DIR) && terraform init -backend=false
	@echo ""
	@echo "==> Next: make tf-validate"

tf-fmt: ## terraform fmt -recursive
	cd $(TF_DIR) && terraform fmt -recursive

tf-validate: tf-fmt ## terraform fmt + validate
	cd $(TF_DIR) && terraform validate
	@echo ""
	@echo "==> Next: make tf-apply"

tf-plan: ## terraform plan
	cd $(TF_DIR) && terraform plan

tf-apply: ## terraform apply (run twice: once for infra, again after apply-argo for WAF<->ALB)
	cd $(TF_DIR) && terraform apply
	@echo ""
	@echo "==> Next: make fill-placeholders   (first apply)"
	@echo "    -- or, if this was the second pass after 'make apply-argo', setup"
	@echo "       is complete: git push origin main to trigger a deploy."

tf-output: ## Print all terraform outputs
	cd $(TF_DIR) && terraform output

tf-destroy: ## terraform destroy (run AFTER `make teardown`)
	cd $(TF_DIR) && terraform destroy

## --- Placeholder substitution (after tf-apply) -----------------------------

fill-placeholders: ## Replace <ECR_URI>/<ECR_REPO_URI>/<ARGO_WORKFLOWS_ECR_ROLE_ARN>/<ACM_CERTIFICATE_ARN> using terraform outputs
	@cd $(TF_DIR) && \
	ECR_URI=$$(terraform output -raw ecr_repository_url) && \
	ROLE_ARN=$$(terraform output -raw argo_workflows_ecr_role_arn) && \
	CERT_ARN=$$(terraform output -raw acm_certificate_arn) && \
	cd .. && \
	echo "==> ECR_URI=$$ECR_URI" && \
	echo "==> ARGO_WORKFLOWS_ECR_ROLE_ARN=$$ROLE_ARN" && \
	echo "==> ACM_CERTIFICATE_ARN=$$CERT_ARN" && \
	sed -i.bak "s#<ECR_URI>#$$ECR_URI#g" \
		$(HELM_DIR)/values.yaml \
		argo/rollouts/rollout-production.yaml && \
	sed -i.bak "s#<ECR_REPO_URI>#$$ECR_URI#g" \
		argo/events/sensor-github.yaml \
		argo/workflows/workflow-template-deploy.yaml && \
	sed -i.bak "s#<ARGO_WORKFLOWS_ECR_ROLE_ARN>#$$ROLE_ARN#g" \
		argo/workflows/serviceaccount.yaml && \
	sed -i.bak "s#<ACM_CERTIFICATE_ARN>#$$CERT_ARN#g" \
		argo/events/ingress-webhook.yaml \
		monitoring/prometheus-values.yaml && \
	find . -name '*.bak' -delete
	@echo "==> Placeholders filled."
	@echo ""
	@echo "==> Next: make kubeconfig"

fill-slack-secret: ## Replace <SLACK_WEBHOOK_URL> in argo/rollouts/analysis-template.yaml
	@test -n "$(SLACK_WEBHOOK_URL)" || (echo "SLACK_WEBHOOK_URL is required, e.g. make fill-slack-secret SLACK_WEBHOOK_URL=https://hooks.slack.com/services/..." && exit 1)
	sed -i.bak "s#<SLACK_WEBHOOK_URL>#$(SLACK_WEBHOOK_URL)#g" argo/rollouts/analysis-template.yaml
	find . -name '*.bak' -delete
	@echo "==> Slack webhook filled in argo/rollouts/analysis-template.yaml."
	@echo ""
	@echo "==> Next: make github-secret GITHUB_PAT=... GITHUB_WEBHOOK_SECRET=..."

## --- Cluster bootstrap -------------------------------------------------------

kubeconfig: ## aws eks update-kubeconfig (cluster name/region from terraform outputs)
	@cd $(TF_DIR) && \
	CLUSTER=$$(terraform output -raw cluster_name) && \
	REGION=$$(terraform output -raw aws_region) && \
	aws eks update-kubeconfig --name "$$CLUSTER" --region "$$REGION"
	@echo ""
	@echo "==> Next: make bootstrap SLACK_WEBHOOK_URL=..."

bootstrap: ## Install Argo Workflows/Events/Rollouts + kube-prometheus-stack (scripts/bootstrap.sh)
	@test -n "$(SLACK_WEBHOOK_URL)" || (echo "SLACK_WEBHOOK_URL is required, e.g. make bootstrap SLACK_WEBHOOK_URL=https://hooks.slack.com/services/..." && exit 1)
	SLACK_WEBHOOK_URL="$(SLACK_WEBHOOK_URL)" ./scripts/bootstrap.sh
	@echo ""
	@echo "==> Next: make fill-slack-secret SLACK_WEBHOOK_URL=..."

github-secret: ## Create the github-access Secret (GitHub PAT + webhook shared secret)
	@test -n "$(GITHUB_PAT)" || (echo "GITHUB_PAT is required" && exit 1)
	@test -n "$(GITHUB_WEBHOOK_SECRET)" || (echo "GITHUB_WEBHOOK_SECRET is required" && exit 1)
	kubectl create secret generic github-access -n argo-events \
		--from-literal=token="$(GITHUB_PAT)" \
		--from-literal=secret="$(GITHUB_WEBHOOK_SECRET)" \
		--dry-run=client -o yaml | kubectl apply -f -
	@echo ""
	@echo "==> Next: make apply-argo"

## --- Argo manifests ----------------------------------------------------------

apply-workflows: ## kubectl apply -f argo/workflows/
	kubectl apply -f argo/workflows/

apply-events: ## kubectl apply -f argo/events/
	kubectl apply -f argo/events/

apply-rollouts: ## kubectl apply -f argo/rollouts/
	kubectl apply -f argo/rollouts/

apply-cron: ## kubectl apply -f argo/cron/
	kubectl apply -f argo/cron/

apply-argo: apply-workflows apply-events apply-rollouts apply-cron ## Apply all argo/ manifests
	@echo ""
	@echo "==> Next: make tf-apply   (second pass: associates WAF with the new ALB)"

## --- Monitoring ----------------------------------------------------------------

apply-grafana-dashboard: ## Load monitoring/grafana-dashboard.json into Grafana via a labeled ConfigMap (auto-loaded by the dashboard sidecar)
	kubectl create configmap argo-cicd-app-dashboard -n monitoring \
		--from-file=argo-cicd-app.json=monitoring/grafana-dashboard.json \
		--dry-run=client -o yaml | \
		kubectl label -f - --local --dry-run=client -o yaml grafana_dashboard=1 | \
		kubectl apply -f -
	@echo ""
	@echo "==> Dashboard 'argo-cicd-platform' will appear in Grafana within ~1 minute."

## --- Operations ----------------------------------------------------------------

approve-staging: ## Resume the latest suspended deploy-staging workflow for production (or NAME=deploy-staging-xxxxx), stopping any other stale ones
	./scripts/approve-staging.sh $(NAME)
	@echo ""
	@echo "==> Next: make watch-canary"

stop-staging: ## Stop a stale suspended deploy-staging workflow (NAME=deploy-staging-xxxxx)
	@test -n "$(NAME)" || (echo "NAME is required, e.g. make stop-staging NAME=deploy-staging-xxxxx (see: argo list -n argo)" && exit 1)
	argo stop -n argo $(NAME)

watch-canary: ## Watch the production canary rollout
	kubectl argo rollouts get rollout argo-cicd-app -n production --watch

rollback-production: ## Abort the current canary and roll back production to the previous stable version
	kubectl argo rollouts abort argo-cicd-app -n production
	kubectl argo rollouts undo argo-cicd-app -n production
	@if [ -n "$(SLACK_WEBHOOK_URL)" ]; then \
		curl -fsS -X POST -H 'Content-type: application/json' \
			--data '{"text":":leftwards_arrow_with_hook: Manual rollback triggered for *production* (argo-cicd-app) via make rollback-production"}' \
			"$(SLACK_WEBHOOK_URL)" >/dev/null || true; \
	else \
		echo "(set SLACK_WEBHOOK_URL in .env to also post a Slack message for manual rollbacks)"; \
	fi
	@echo ""
	@echo "==> Next: make watch-canary"

## --- Verification --------------------------------------------------------------

helm-lint: ## helm lint helm/app
	cd $(HELM_DIR) && helm lint .

helm-template-staging: ## Render the chart with values-staging.yaml
	cd $(HELM_DIR) && helm template . -f values-staging.yaml

helm-template-production: ## Render the chart with values-production.yaml
	cd $(HELM_DIR) && helm template . -f values-production.yaml

test: ## Run the app test suite
	cd app && pip install -r requirements-dev.txt && pytest -v

## --- Teardown -------------------------------------------------------------------

teardown: ## Remove Argo/monitoring stack + app release (scripts/teardown.sh)
	./scripts/teardown.sh

clean: ## Remove local terraform/python cache artifacts
	rm -rf $(TF_DIR)/.terraform app/__pycache__ app/tests/__pycache__
	find . -name '*.bak' -delete
