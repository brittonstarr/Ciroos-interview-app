#!/usr/bin/env bash
# Renders k8s/c1/02-service-api-config.yaml.tmpl -> 02-service-api-config.yaml
# using the C2 endpoint hostnames captured by 05-wait-for-c2-endpoints.sh.
# This is the file that actually points C1's frontend at C2's ledger tier.
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck disable=SC1091
source .c2-endpoints.env

sed \
  -e "s|__LEDGERWRITER_ADDR__|${LEDGERWRITER_ADDR}|" \
  -e "s|__BALANCEREADER_ADDR__|${BALANCEREADER_ADDR}|" \
  -e "s|__TRANSACTIONHISTORY_ADDR__|${TRANSACTIONHISTORY_ADDR}|" \
  ../k8s/c1/02-service-api-config.yaml.tmpl > ../k8s/c1/02-service-api-config.yaml

echo "Rendered k8s/c1/02-service-api-config.yaml:"
cat ../k8s/c1/02-service-api-config.yaml
