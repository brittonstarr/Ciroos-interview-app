#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../infra/terraform"

SG_ID=$(terraform output -raw c2_cluster_security_group_id)
REGION=$(terraform output -raw c2_region)

for CIDR in 10.10.16.0/20 10.10.32.0/20; do
  aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp --port 8080 \
    --cidr "$CIDR" || echo "  (rule for ${CIDR} may already exist)"
done

echo "Restored C1 -> C2 ledger-port ingress on ${SG_ID}."
echo "Faster alternative: 'terraform apply' in infra/terraform also fixes this via drift detection, but this script is quicker mid-demo."
