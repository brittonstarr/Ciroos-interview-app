#!/usr/bin/env bash
# Installs the Datadog Agent on both clusters. Requires DD_API_KEY to be
# exported in your shell first — it is created as a Kubernetes Secret via
# kubectl (never written to any committed file). Optionally set DD_SITE if
# your org's Datadog account isn't on the default US1 site
# (datadoghq.com) — e.g. datadoghq.eu, us3.datadoghq.com, us5.datadoghq.com,
# ap1.datadoghq.com.
set -euo pipefail
cd "$(dirname "$0")/../k8s/addons"

: "${DD_API_KEY:?Set DD_API_KEY in your shell first, e.g. export DD_API_KEY=xxxx}"
DD_SITE="${DD_SITE:-datadoghq.com}"

helm repo add datadog https://helm.datadoghq.com >/dev/null
helm repo update >/dev/null

install_one() {
  local ctx="$1" cluster_tag="$2" region_tag="$3"

  kubectl --context "$ctx" create namespace datadog --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -

  kubectl --context "$ctx" -n datadog create secret generic datadog-secret \
    --from-literal api-key="$DD_API_KEY" \
    --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -

  helm upgrade --install datadog datadog/datadog \
    --kube-context "$ctx" \
    -n datadog \
    -f datadog-values.yaml \
    --set datadog.site="$DD_SITE" \
    --set-string "datadog.tags[0]=cluster:${cluster_tag}" \
    --set-string "datadog.tags[1]=region:${region_tag}" \
    --set-string "datadog.tags[2]=project:boa-challenge" \
    --set datadog.clusterName="${cluster_tag}"

  kubectl --context "$ctx" -n datadog rollout status daemonset/datadog --timeout=180s
}

C1_REGION=$(cd ../../infra/terraform && terraform output -raw c1_region)
C2_REGION=$(cd ../../infra/terraform && terraform output -raw c2_region)

install_one c1 c1 "$C1_REGION"
install_one c2 c2 "$C2_REGION"

echo "Datadog Agent installed on both clusters (site: ${DD_SITE})."
