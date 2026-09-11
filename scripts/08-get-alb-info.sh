#!/usr/bin/env bash
# Waits for the frontend Ingress's ALB to come up, then prints both the
# public URL and the exact `terraform apply` command to attach the WAF —
# see infra/terraform/README.md Phase 2.
set -euo pipefail

tries=0
while true; do
  ALB_HOST=$(kubectl --context c1 -n boa get ingress frontend \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "$ALB_HOST" ]]; then
    break
  fi
  tries=$((tries + 1))
  if [[ $tries -gt 60 ]]; then
    echo "Timed out waiting for the frontend Ingress to get an ALB hostname." >&2
    exit 1
  fi
  sleep 5
done

C1_REGION=$(cd "$(dirname "$0")/../infra/terraform" && terraform output -raw c1_region)
ALB_ARN=$(aws elbv2 describe-load-balancers --region "$C1_REGION" \
  --query "LoadBalancers[?contains(LoadBalancerName, 'boa-challenge-c1')].LoadBalancerArn" \
  --output text)

echo "App URL:  http://${ALB_HOST}/"
echo "ALB ARN:  ${ALB_ARN}"
echo
echo "To attach the WAF (Phase 2), run:"
echo "  cd infra/terraform && terraform apply -var=\"c1_alb_arn=${ALB_ARN}\""
