# Write-up: AWS Application and Infrastructure Observability Challenge

> **Status: draft.** Sections marked `[TODO: fill in after live test]` need
> real output from an actual `terraform apply` / deploy / Datadog run —
> this build was produced in a sandbox with no live AWS or Datadog network
> access, so every command was written and reasoned about but not yet
> executed. Replace those sections with real screenshots/output before
> submitting.

## Summary

Two independent EKS clusters — C1 (`us-east-1`) and C2 (`us-west-2`) —
run a modified [Bank of Anthos](https://github.com/GoogleCloudPlatform/bank-of-anthos)
deployment split across the identity/UI tier (C1) and the ledger tier
(C2). C1 is reachable from the internet only through an ALB fronted by
AWS WAFv2; C2 has no internet-facing load balancer at all. The two
clusters communicate privately over cross-region VPC Peering, scoped at
the routing, security-group, and Kubernetes NetworkPolicy layers to
exactly the ledger-service ports and the specific subnets that need them.
Datadog collects logs and infrastructure/application metrics from both
clusters plus AWS (ALB/NLB/NAT/VPC), with a dashboard and monitors
covering the key failure modes. A scripted fault (scaling the ledger
write service to zero replicas) deterministically trips one of those
monitors, demonstrated end to end.

## Design choices and why

### Application: Bank of Anthos

Chosen from the challenge's suggested list because it already has a
natural identity/ledger service boundary (frontend/userservice/contacts
vs. ledgerwriter/balancereader/transactionhistory) that maps cleanly onto
a two-cluster split with a real, single-direction dependency — exactly
what "a service in C1 must communicate with a specific service in C2"
calls for — rather than a boundary that would need to be invented. It
also ships three independently testable request/response paths
(payment, balance, transaction history) instead of just one, which gives
the verifier and the demo more to actually check. Full comparison against
the other suggested apps is in `architecture-design.md` §1.

### Cluster split

- **C1 (us-east-1):** `frontend`, `userservice`, `contacts`, `accounts-db`,
  `loadgenerator`. Public entry point — the only cluster with an ALB.
- **C2 (us-west-2):** `ledgerwriter`, `balancereader`, `transactionhistory`,
  `ledger-db`. No public exposure whatsoever.

Rationale and the full service graph are in `docs/architecture.md` §2.

### Private connectivity: VPC Peering (not PrivateLink)

Given the 24-hour window, VPC Peering was chosen as the baseline
private-connectivity mechanism over AWS PrivateLink (VPC Endpoint
Service/Interface Endpoint), on a build-time-risk basis:

| | VPC Peering | PrivateLink |
|---|---|---|
| Setup complexity | Low — one peering connection, two routes, one SG rule | Higher — NLB behind the endpoint service, consumer endpoint, endpoint policies |
| Blast radius if misconfigured | Broader by default (mitigated here by scoping routes/SGs tightly) | Narrower by construction — no routing table changes needed at all |
| Fits a 24h build | Yes, first-attempt reliable | Real risk of not finishing if something doesn't come up cleanly |
| More impressive to a reviewer | Standard, well-understood | Shows deeper AWS networking knowledge |

VPC Peering was chosen for the guaranteed working baseline, with
least-privilege enforced at three layers to compensate for peering's
normally-broader default reachability (`docs/architecture.md` §1, §3):
routes added only to the specific private route tables that need them
(not a blanket VPC-to-VPC route), a security-group rule scoped to C1's
private-subnet CIDRs and the ledger ports only, and Kubernetes
NetworkPolicy narrowing this further to the pod level inside C2.

**PrivateLink is the explicit stretch goal** (see "What was skipped"
below) if time remained after the baseline was verified working.

### Security

- **WAFv2** in front of the C1 ALB: AWS managed rule groups (Common,
  Known Bad Inputs, SQLi, IP Reputation), a custom rate-based rule, and
  logging to S3 via Kinesis Firehose. Deployed in COUNT mode first with a
  documented switch to BLOCK — staged rollout to avoid locking myself out
  mid-build if a rule is more aggressive than expected.
- **No public exposure of C2, ever** — no ALB, no public subnets used for
  workloads (public subnets in C2 exist only for NAT Gateway egress).
- **Least privilege on the cross-cluster path** at three layers (routing,
  security group, NetworkPolicy) as described above.
- **IRSA** (IAM Roles for Service Accounts) for the AWS Load Balancer
  Controller in both clusters, rather than broad node-instance-profile
  permissions.
- **Fresh JWT signing keypair** generated at deploy time — upstream Bank
  of Anthos ships a publicly-known demo private key in its manifests,
  which would be a real finding in this context; this build generates a
  new keypair and stores it as a Kubernetes Secret instead.
- **Named, not hidden, trade-off:** EKS cluster API endpoints are
  currently reachable from `0.0.0.0/0` (control-plane/`kubectl` access,
  not application traffic) for build-time convenience. This is called out
  explicitly rather than left implicit, with the fix (restrict to a
  specific CIDR or switch to private-only + a bastion/SSM) noted as a
  follow-up.

### Observability

Datadog Agent (DaemonSet on both clusters) collects logs, container and
kube-state metrics, APM/OTLP endpoints (ready if the app were instrumented
further), and Cloud Network Monitoring data. A separate AWS integration
(cross-account IAM role) brings in CloudWatch metrics for the
ALB/NLB/NAT/VPC layer, so both the application and the infrastructure
requirements are covered from two complementary sources rather than one.
Full data-flow diagram in `docs/architecture.md` §4.

## What was built

- [x] Two EKS clusters (C1 `us-east-1`, C2 `us-west-2`), Terraform-managed,
  as reusable modules (`infra/terraform/modules/{network,eks,irsa,peering,waf}`).
- [x] Bank of Anthos, split across the two clusters, with a fresh JWT
  keypair and hardened Secret handling.
- [x] Internet-facing ALB + WAFv2 in front of C1 only.
- [x] Cross-region VPC Peering with layered least-privilege scoping
  (routes, security group, NetworkPolicy).
- [x] Kubernetes NetworkPolicy, default-deny plus scoped allows, with the
  VPC CNI's `enableNetworkPolicy` addon configuration explicitly set
  (easy to miss on EKS — NetworkPolicy objects are silently inert without it).
- [x] Datadog Agent on both clusters (logs, metrics, APM-ready, NPM) +
  AWS integration for infra metrics.
- [x] Datadog dashboard and four monitors covering application
  (`ledgerwriter` replica availability, frontend error-log spikes),
  infrastructure (NLB target health, node CPU).
- [x] Two fault-injection scenarios, one primary/deterministic (scale
  `ledgerwriter` to 0) and one secondary/bonus (revoke the C1→C2 security
  group rule, breaking the private-connectivity mechanism itself) — see
  `docs/fault-injection.md`.
- [x] Python verification tool (`verifier/`) — static AWS-config audit via
  boto3 (no unintended public exposure) plus live connectivity checks
  (positive: C1→C2 path works; negative: nothing else does).
- [x] Architecture diagrams (`docs/architecture.md`, Mermaid — network
  topology, service graph, request path, observability data flow).

## What was skipped, and why

- **PrivateLink upgrade (stretch goal).** VPC Peering is the shipped
  baseline; PrivateLink (a VPC Endpoint Service in C2 fronting the
  ledger-tier NLB, consumed via an Interface Endpoint in C1, with an
  endpoint policy narrowing it further) was scoped and deferred until the
  peering baseline was confirmed working end-to-end, given the 24h
  window. `[TODO: state here whether it was attempted and how far it got.]`
- **Restricting EKS API endpoint access** to specific CIDRs (currently
  `0.0.0.0/0` for build-time convenience). Named explicitly above as a
  trade-off, not silently left in place.
- **Full mTLS / service mesh between C1 and C2.** NetworkPolicy plus
  security-group scoping was judged sufficient for the stated
  requirements within the time budget; a mesh (App Mesh, Istio) would add
  defense-in-depth but wasn't essential to meeting the "least privilege"
  and "private connectivity" requirements as written.
- **Multi-AZ NAT Gateways** — a single NAT Gateway per VPC was used
  (`single_nat_gateway = true`) rather than one per AZ, trading
  cross-AZ resilience for lower cost/build complexity; this is a
  demo/interview environment, not a production SLA target.
- **CI/CD pipeline** for the Terraform/Kubernetes changes — everything
  here is applied by hand per the README's ordered steps. Given the 24h
  window, hand-applying a small, ordered set of changes was judged lower
  risk than also building and debugging a pipeline.

## Test results

`[TODO: fill in with actual output once run live]`

- `terraform validate` / `terraform plan` output for both roots
  (`infra/terraform`, `infra/datadog`):
- Cluster creation confirmation (`kubectl get nodes` on both contexts):
- App reachability (ALB URL, screenshot of the UI):
- `verifier/verify.py --live` output (full report):
- WAF state (COUNT vs BLOCK, sample blocked request):
- Datadog dashboard screenshot (steady state):
- Fault injection: monitor transition to Alert (screenshot/timestamp),
  time-to-detect:
- Fault restoration: monitor recovery (screenshot/timestamp):

## What I'd do with more time

1. Finish the PrivateLink upgrade and diff it against the peering
   baseline in the write-up (setup complexity vs. blast-radius reduction,
   concretely, not just in the abstract table above).
2. Restrict EKS API endpoint access to a known CIDR (or move to
   private-only endpoints + SSM Session Manager for `kubectl` access).
3. Add mTLS between the two clusters (App Mesh or a lightweight service
   mesh) for defense-in-depth beyond NetworkPolicy/security groups.
4. Wire up a minimal CI pipeline (GitHub Actions) to run
   `terraform validate`/`plan` and the Python verifier's unit tests on
   every push, since both already exist as standalone tools.
5. Expand the fault-injection catalog — a third scenario worth trying is
   a WAF rate-limit trip (flood the ALB past the configured threshold)
   to demonstrate the security-control side of monitoring, not just
   availability.
6. Multi-AZ NAT Gateways for real HA, if this were headed toward
   production rather than a timed demo.
</content>
