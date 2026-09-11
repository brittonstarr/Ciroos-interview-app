#!/usr/bin/env bash
# Deploys the ledger tier to C2. Must run after 03-generate-jwt-secret.sh
# (needs the jwt-key Secret) and 02-install-alb-controllers.sh (needs the
# controller to provision the internal NLBs these Services request).
set -euo pipefail
cd "$(dirname "$0")/.."

kubectl --context c2 apply -f k8s/c2/
echo "Applied C2 manifests. Waiting for ledger-db to become ready..."
kubectl --context c2 -n boa rollout status statefulset/ledger-db --timeout=180s
kubectl --context c2 -n boa rollout status deployment/ledgerwriter --timeout=180s
kubectl --context c2 -n boa rollout status deployment/balancereader --timeout=180s
kubectl --context c2 -n boa rollout status deployment/transactionhistory --timeout=180s
echo "C2 (ledger tier) is up."
