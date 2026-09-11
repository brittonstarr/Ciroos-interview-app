#!/usr/bin/env bash
# Installs the AWS Load Balancer Controller on both clusters via Helm,
# wired to the IRSA role Terraform already created for each cluster. This
# is what turns the frontend's Ingress into a real ALB (C1) and the three
# ledger-tier Services into internal NLBs (C2).
set -euo pipefail
cd "$(dirname "$0")/../infra/terraform"

helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo update >/dev/null

install_one() {
  local ctx="$1" cluster_name="$2" region="$3" vpc_id="$4" role_arn="$5"

  kubectl --context "$ctx" create serviceaccount -n kube-system aws-load-balancer-controller \
    --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
  kubectl --context "$ctx" annotate serviceaccount -n kube-system aws-load-balancer-controller \
    "eks.amazonaws.com/role-arn=${role_arn}" --overwrite

  helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --kube-context "$ctx" \
    -n kube-system \
    --set clusterName="$cluster_name" \
    --set region="$region" \
    --set vpcId="$vpc_id" \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller

  kubectl --context "$ctx" rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=180s
}

install_one c1 \
  "$(terraform output -raw c1_cluster_name)" \
  "$(terraform output -raw c1_region)" \
  "$(terraform output -raw c1_vpc_id)" \
  "$(terraform output -raw c1_alb_controller_role_arn)"

install_one c2 \
  "$(terraform output -raw c2_cluster_name)" \
  "$(terraform output -raw c2_region)" \
  "$(terraform output -raw c2_vpc_id)" \
  "$(terraform output -raw c2_alb_controller_role_arn)"

echo "AWS Load Balancer Controller installed on both clusters."
