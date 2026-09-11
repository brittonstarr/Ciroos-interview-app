#!/usr/bin/env bash
# Polls the three C2 Services until AWS Load Balancer Controller has
# provisioned their internal NLBs and populated .status.loadBalancer, then
# writes the hostnames to scripts/.c2-endpoints.env for
# 06-render-c1-config.sh to consume. This is the "phase 2" half of the
# two-phase pattern used throughout this build (same idea as the WAF/ALB
# association): C2's LB DNS names don't exist until AWS finishes creating
# them, so we wait, then feed them forward.
set -euo pipefail
cd "$(dirname "$0")"

wait_for_hostname() {
  local svc="$1" tries=0
  while true; do
    host=$(kubectl --context c2 -n boa get svc "$svc" \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    if [[ -n "$host" ]]; then
      echo "$host"
      return 0
    fi
    tries=$((tries + 1))
    if [[ $tries -gt 60 ]]; then
      echo "Timed out waiting for Service/${svc} to get an NLB hostname." >&2
      exit 1
    fi
    sleep 5
  done
}

echo "Waiting for internal NLBs (usually 2-3 minutes)..." >&2
LEDGERWRITER_HOST=$(wait_for_hostname ledgerwriter)
BALANCEREADER_HOST=$(wait_for_hostname balancereader)
TRANSACTIONHISTORY_HOST=$(wait_for_hostname transactionhistory)

cat > .c2-endpoints.env <<EOF
LEDGERWRITER_ADDR=${LEDGERWRITER_HOST}:8080
BALANCEREADER_ADDR=${BALANCEREADER_HOST}:8080
TRANSACTIONHISTORY_ADDR=${TRANSACTIONHISTORY_HOST}:8080
EOF

echo "Wrote scripts/.c2-endpoints.env:"
cat .c2-endpoints.env
