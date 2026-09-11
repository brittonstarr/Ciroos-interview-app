#!/usr/bin/env bash
# Tears everything down cleanly. Order matters: Kubernetes-created AWS
# resources (the ALB from the Ingress, the 3 internal NLBs from the
# LoadBalancer Services) have to be deleted *through Kubernetes* first, or
# their AWS Load Balancer Controller finalizers will block/orphan them and
# `terraform destroy` will hang or leave stray ELBv2 resources behind.
set -euo pipefail
cd "$(dirname "$0")"

echo "Deleting C1 app manifests (releases the ALB)..."
kubectl --context c1 delete -f ../k8s/c1/ --ignore-not-found --wait=true --timeout=180s || true

echo "Deleting C2 app manifests (releases the 3 internal NLBs)..."
kubectl --context c2 delete -f ../k8s/c2/ --ignore-not-found --wait=true --timeout=180s || true

echo "Uninstalling AWS Load Balancer Controller from both clusters..."
helm uninstall aws-load-balancer-controller --kube-context c1 -n kube-system || true
helm uninstall aws-load-balancer-controller --kube-context c2 -n kube-system || true

echo "Running terraform destroy..."
cd ../infra/terraform
terraform destroy

echo "Teardown complete."
