#!/usr/bin/env bash
# Resumes a deploy-staging-xxxxx workflow (promoting its build to production via
# trigger-production), then stops any *other* deploy-staging-* workflows still
# suspended at approve-production - so a pile-up of approvals from earlier pushes
# doesn't each independently kick off their own production deploy.
#
# Usage: approve-staging.sh [deploy-staging-xxxxx]
# If no name is given, auto-selects the most recently created deploy-staging-*
# workflow that is currently suspended at approve-production.
set -euo pipefail

NAME="${1:-}"

if [[ -z "${NAME}" ]]; then
  NAME=$(python3 - <<'EOF'
import json, subprocess, sys

names = subprocess.run(
    ["argo", "list", "-n", "argo", "-o", "name"],
    capture_output=True, text=True, check=True,
).stdout.split()

candidates = []
for wf in names:
    if not wf.startswith("deploy-staging-"):
        continue
    data = json.loads(subprocess.run(
        ["argo", "get", "-n", "argo", wf, "-o", "json"],
        capture_output=True, text=True, check=True,
    ).stdout)
    nodes = data.get("status", {}).get("nodes", {}).values()
    if any(n.get("displayName") == "approve-production" and n.get("phase") == "Running" for n in nodes):
        candidates.append((data["metadata"]["creationTimestamp"], wf))

if not candidates:
    print("ERROR: no deploy-staging-* workflow is currently suspended at approve-production "
          "(see: argo list -n argo)", file=sys.stderr)
    sys.exit(1)

candidates.sort()
chosen = candidates[-1][1]
if len(candidates) > 1:
    others = ", ".join(wf for _, wf in candidates[:-1])
    print(f"==> Multiple suspended deploy-staging workflows found; approving the newest "
          f"({chosen}); will stop: {others}", file=sys.stderr)
print(chosen)
EOF
)
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
