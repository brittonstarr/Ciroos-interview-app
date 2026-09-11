#!/usr/bin/env bash
# Runs the full deploy in order. Prerequisite: `terraform apply` has
# already succeeded in infra/terraform (see infra/terraform/README.md
# Phase 1) — this script only touches Kubernetes/Helm and the final WAF
# association apply.
set -euo pipefail
cd "$(dirname "$0")"

./01-configure-kubectl.sh
./02-install-alb-controllers.sh
./03-generate-jwt-secret.sh
./04-deploy-c2.sh
./05-wait-for-c2-endpoints.sh
./06-render-c1-config.sh
./07-deploy-c1.sh
./08-get-alb-info.sh

echo
echo "Done. Run the terraform apply command printed above to attach the WAF."
