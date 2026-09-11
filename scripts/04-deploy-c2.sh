#!/usr/bin/env bash
# Deploys the ledger tier to C2. Must run after 03-generate-jwt-secret.sh
# (needs the jwt-key Secret) and 02-install-alb-controllers.sh (needs the
# controller to provision the internal NLBs these Services request).
set -euo pipefail
cd "$(dirname "$0")/.."

# Render the 3 ledger-tier Service templates: fills in
# __C2_CLUSTER_SG_ID__ with the real EKS cluster security group so the
# aws-load-balancer-security-groups annotation can hand AWS LBC a
# concrete SG ID instead of a placeholder. See the comment on that
# annotation in k8s/c2/04-ledgerwriter.yaml.tmpl for why this matters —
# without it, AWS LBC auto-creates its own SG per Service, open to
# 0.0.0.0/0 on the target port.
C2_CLUSTER_SG_ID=$(cd infra/terraform && terraform output -raw c2_cluster_security_group_id)
for tmpl in k8s/c2/04-ledgerwriter.yaml.tmpl k8s/c2/05-balancereader.yaml.tmpl k8s/c2/06-transactionhistory.yaml.tmpl; do
  sed -e "s|__C2_CLUSTER_SG_ID__|${C2_CLUSTER_SG_ID}|" "$tmpl" > "${tmpl%.tmpl}"
done
echo "Rendered C2 manifests with cluster security group ${C2_CLUSTER_SG_ID}."

kubectl --context c2 apply -f k8s/c2/
echo "Applied C2 manifests. Waiting for ledger-db to become ready..."
kubectl --context c2 -n boa rollout status statefulset/ledger-db --timeout=180s
kubectl --context c2 -n boa rollout status deployment/ledgerwriter --timeout=180s
kubectl --context c2 -n boa rollout status deployment/balancereader --timeout=180s
kubectl --context c2 -n boa rollout status deployment/transactionhistory --timeout=180s
echo "C2 (ledger tier) is up."
