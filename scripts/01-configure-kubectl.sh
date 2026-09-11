#!/usr/bin/env bash
# Points kubectl at both clusters using context aliases `c1` and `c2`,
# reading cluster names/regions straight from Terraform outputs so this
# never drifts from what was actually deployed.
set -euo pipefail
cd "$(dirname "$0")/../infra/terraform"

C1_NAME=$(terraform output -raw c1_cluster_name)
C2_NAME=$(terraform output -raw c2_cluster_name)
C1_REGION=$(terraform output -raw c1_region)
C2_REGION=$(terraform output -raw c2_region)

aws eks update-kubeconfig --name "$C1_NAME" --region "$C1_REGION" --alias c1
aws eks update-kubeconfig --name "$C2_NAME" --region "$C2_REGION" --alias c2

echo "kubectl contexts ready: c1 (${C1_NAME}, ${C1_REGION}), c2 (${C2_NAME}, ${C2_REGION})"
kubectl config get-contexts c1 c2
