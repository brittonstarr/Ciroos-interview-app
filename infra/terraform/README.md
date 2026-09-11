# Terraform — network, EKS, peering, WAF

## Prerequisites (run these on your own machine, not in a sandbox)

- Terraform >= 1.7
- AWS CLI v2, configured with credentials that can create VPCs/EKS/IAM/WAF resources
- `kubectl`

## What this builds

- Two VPCs (`c1` in `us-east-1`, `c2` in `us-west-2`), each with public subnets (NAT Gateway only — no workloads) and private subnets (EKS nodes/Pods).
- Two EKS clusters, one per VPC, each with a managed node group and an IRSA role for the AWS Load Balancer Controller.
- Cross-region VPC Peering between the two VPCs, with routes scoped to just the private subnets and a security group rule in C2 that only allows C1's frontend subnets in on the ledger service ports.
- A regional WAFv2 WebACL (AWS managed rule groups, staged in COUNT mode by default) — not yet attached to an ALB, because the ALB doesn't exist until the app is deployed.

## Apply — two phases

**Phase 1: infrastructure**

```bash
cd infra/terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Then point kubectl at both clusters (see the `kubeconfig_commands` output, or run):

```bash
aws eks update-kubeconfig --name boa-challenge-c1-eks --region us-east-1 --alias c1
aws eks update-kubeconfig --name boa-challenge-c2-eks --region us-west-2 --alias c2
```

**Phase 2: attach the WAF to the ALB, after the app + Ingress are deployed** (see `/k8s`), which is what actually creates the ALB:

```bash
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName, 'boa-challenge')].LoadBalancerArn" \
  --output text)

terraform apply -var="c1_alb_arn=${ALB_ARN}"
```

## Staged WAF rollout

Rules deploy in `count` mode by default (`waf_rule_action_mode = "count"`). After generating some real traffic through the ALB and checking CloudWatch metrics / the WAF sampled requests for false positives, flip to blocking:

```bash
terraform apply -var="c1_alb_arn=${ALB_ARN}" -var="waf_rule_action_mode=block"
```

## Teardown

```bash
terraform destroy
```

(A convenience wrapper will land in `/scripts` alongside the app-deploy scripts.)

## Note on validation

This code was written and reviewed manually but has **not** been run through `terraform init/validate/plan` yet — the sandbox this was authored in has no network path to the Terraform provider registry. Please run `terraform init && terraform validate` first and send back any errors; provider/version issues are the most likely thing to surface and are quick to fix.
