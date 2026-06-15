#!/usr/bin/env bash
# Resumes the given deploy-staging-xxxxx workflow (promoting its build to
# production via trigger-production), then stops any *other*
# deploy-staging-* workflows still suspended at approve-production - so a
# pile-up of approvals from earlier pushes doesn't each independently kick
# off their own production deploy.
set -euo pipefail

NAME="${1:-}"
if [[ -z "${NAME}" ]]; then
  echo "Usage: $0 <deploy-staging-xxxxx>  (see: argo list -n argo)" >&2
  exit 1
fi

echo "==> Resuming ${NAME} (promotes its build to production)"
argo resume -n argo "${NAME}"

echo "==> Checking for other deploy-staging-* workflows suspended at approve-production..."
for wf in $(argo list -n argo -o name | grep '^deploy-staging-' || true); do
  [[ "${wf}" == "${NAME}" ]] && continue
  suspended=$(argo get -n argo "${wf}" -o json | python3 -c '
import json, sys
nodes = json.load(sys.stdin).get("status", {}).get("nodes", {}).values()
print("yes" if any(n.get("displayName") == "approve-production" and n.get("phase") == "Running" for n in nodes) else "no")
')
  if [[ "${suspended}" == "yes" ]]; then
    echo "==> Stopping stale workflow ${wf}"
    argo stop -n argo "${wf}"
  fi
done
