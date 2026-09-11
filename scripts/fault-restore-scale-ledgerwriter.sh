#!/usr/bin/env bash
set -euo pipefail

kubectl --context c2 -n boa scale deployment/ledgerwriter --replicas=1
kubectl --context c2 -n boa rollout status deployment/ledgerwriter --timeout=120s
echo "ledgerwriter restored to 1 replica."
