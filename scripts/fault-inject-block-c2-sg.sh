#!/usr/bin/env bash
# SECONDARY / bonus fault: revoke the security group rule that permits
# C1 -> C2 ledger-port traffic, breaking the private-connectivity path
# itself rather than the application. More thematically on-point for this
# challenge (it directly faults the "secure private connectivity"
# mechanism being demonstrated) — but flagged honestly in
# docs/fault-injection.md: which exact Datadog signal trips first (log
# monitor vs NLB health) depends on infra specifics not fully verified
# live from the sandbox this was built in. Verify once, then it's a great
# second act for the demo.
set -euo pipefail
cd "$(dirname "$0")/../infra/terraform"

SG_ID=$(terraform output -raw c2_cluster_security_group_id)
REGION=$(terraform output -raw c2_region)

# Matches the rule created by infra/terraform/modules/peering (one rule per
# ledger_service_ports entry — default just [8080]).
for CIDR in 10.10.16.0/20 10.10.32.0/20; do
  aws ec2 revoke-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp --port 8080 \
    --cidr "$CIDR" || echo "  (rule for ${CIDR} may already be gone)"
done

echo "Revoked C1 -> C2 ledger-port ingress on ${SG_ID}. The private connectivity path is now blocked at the network layer."
echo "Watch: frontend error logs / the 'frontend error log spike' monitor, and (if it trips) the NLB unhealthy-host monitor."
