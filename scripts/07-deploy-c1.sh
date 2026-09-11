#!/usr/bin/env bash
# Deploys the identity/UI tier to C1, including the Ingress that becomes
# the public ALB. Must run after 06-render-c1-config.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f k8s/c1/02-service-api-config.yaml ]]; then
  echo "k8s/c1/02-service-api-config.yaml doesn't exist yet — run scripts/06-render-c1-config.sh first." >&2
  exit 1
fi

kubectl --context c1 apply -f k8s/c1/
echo "Applied C1 manifests. Waiting for rollouts..."
kubectl --context c1 -n boa rollout status statefulset/accounts-db --timeout=180s
kubectl --context c1 -n boa rollout status deployment/userservice --timeout=180s
kubectl --context c1 -n boa rollout status deployment/contacts --timeout=180s
kubectl --context c1 -n boa rollout status deployment/frontend --timeout=180s
echo "C1 (identity/UI tier) is up. Run scripts/08-get-alb-info.sh once the Ingress has an address."
