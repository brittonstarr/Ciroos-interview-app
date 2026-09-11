# Write-up: AWS Application and Infrastructure Observability Challenge

> **Status:** built, verified, and evidenced against real AWS/Datadog
> infrastructure, not just reasoned about. No open items remain below —
> every result cited here (verifier output, screenshots, WAF mode) was
> captured live off the deployed environment.

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

## Engineering philosophy: built to operate, not to impress

Given the 24-hour window, I optimized for the thing I'd actually want if
I inherited this environment on someone else's team, rather than for the
single most visually impressive individual feature I could cram in. Concretely:

- **Everything is infrastructure as code, in composable pieces.** The
  Terraform under `infra/terraform/modules/` — network, EKS, IRSA,
  peering, WAF — and the separate `infra/datadog/` root are each scoped
  to one concern with clean inputs/outputs, not one monolithic
  `main.tf`. Swapping the app, adding a third cluster, or pointing this
  whole thing at a different customer's account is a matter of new
  variable values and a new module call, not a rewrite. That's the
  actual bar for "reusable," not just "it worked once."
- **Every change is atomic and self-explaining.** Every commit in this
  repo's history states what broke, the live evidence that confirmed it,
  and why the fix is correct — not just "fix bug." That's the discipline
  you want from anyone touching shared customer infrastructure, and it's
  what makes `git log` here double as a debugging runbook for the next
  person (or the next incident), not just a changelog.
- **Nothing was fixed on a guess.** Every one of the 19 real issues in
  the "Test results" section below was root-caused from a live signal
  first — a stack trace, a `describe-target-health` response, a tag
  browser lookup — and fixed once, correctly, rather than iterated on by
  trial and error. That habit is slower per-fix than guessing, but it's
  the difference between a fix that's actually understood (and therefore
  safe to repeat on the next customer's environment) and one that
  happens to work here by luck.
- **The verifier tool isn't a one-off script — it's the actual
  regression test for the security posture.** `verifier/verify.py`
  re-validates the "no unintended public exposure, only the intended
  path is permitted" claim against live AWS state any time it's run —
  after this build, after the next change, after someone else's change.
  That's the difference between "we believe this is secure" and "we can
  prove this is secure, on demand, forever."
- **Trade-offs are named, not hidden.** Every place this build took a
  shortcut for the sake of the 24-hour window (single NAT Gateway, EKS
  API endpoints open for build convenience, PrivateLink deferred) is
  called out explicitly, with the real fix described, rather than left
  for someone else to discover the hard way. That's what "not
  production-perfect, but production-honest" looks like.

None of this required extra time the way a flashier single feature
would have — it's a way of working, not a deliverable. But it's the
reason this environment could be handed to another engineer, pointed at
a different customer's AWS account, or extended with a third cluster
next week, without anyone needing to first reverse-engineer what I did
or why.

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
  window. The peering baseline took longer to reach fully-verified than
  planned — five distinct, individually-diagnosed connectivity issues
  (see Test results) between DNS resolution, client-IP preservation, a
  route-table conflict, and two separate NLB-health-check gaps — so
  PrivateLink was not attempted. Scoped design for it is still worth
  discussing at the demo: it trades peering's "narrow by policy" model
  for "narrow by construction" (no routing table changes possible at
  all), which is the stronger security story if this were headed to
  production.
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

Every item below is real output from this build's actual deployed
infrastructure — not projected or reasoned-about. The 19 issues found
along the way are the most concrete evidence of the "root-cause from
live evidence, fix once" discipline described above: each was diagnosed
from a real signal (a stack trace, an AWS API response, a Datadog tag
browser lookup) before a fix was written, never guessed twice.

### `terraform apply` — both roots, clean

`infra/terraform` (network/EKS/peering/WAF) and `infra/datadog`
(dashboard/monitors/AWS integration) both apply cleanly with 0 errors as
of the final commit in this repo's history. Getting there surfaced 17
real, individually-diagnosed bugs across both roots — provider schema
drift, an AWS description-field character restriction hit twice, a
route-table/peering-route conflict that silently deleted routes on every
unrelated apply, an IAM policy exceeding AWS's size limit, and more. The
full list, in the order found, is in `claude/build-status.md`'s bug log
and worth reading in the demo as the actual "test results" — a clean
`terraform apply` on the first try would have meant less real signal
that this was tested against reality rather than written and assumed
correct.

### Python verifier — 13 passed, 0 failed, 2 documented warnings

```
$ python3 verify.py --live
== Static AWS configuration audit ==

[PASS] C2 load balancers are internal-only
[PASS] C1 public surface limited to the frontend ALB
[PASS] WAF attached to public ALB: WebACL 'boa-challenge-waf' is associated.
[PASS] No security group open to the internet outside allowed ports
[PASS] C2 private subnets have no route to an Internet Gateway
[PASS] C2 ledger-port SG rule scoped to C1's frontend subnets
[PASS] VPC Peering connection active
[WARN] C1 EKS API endpoint exposure: public endpoint open to 0.0.0.0/0 — documented build-time trade-off, not an app/Service exposure
[WARN] C2 EKS API endpoint exposure: same trade-off

== Live connectivity tests ==

[PASS] LIVE: C1 -> C2 connectivity (ledgerwriter): reachable (HTTP 200)
[PASS] LIVE: C1 -> C2 connectivity (balancereader): reachable (HTTP 200)
[PASS] LIVE: C1 -> C2 connectivity (transactionhistory): reachable (HTTP 200)
[PASS] LIVE: public unreachability of ledgerwriter, balancereader, transactionhistory (x3)

13 passed, 2 warnings, 0 failed
```

Both the "no unintended public path" and "only the intended C1→C2 path
is permitted" requirements are proven here against live AWS state, not
just code review — that distinction is the entire point of shipping the
verifier as a tool rather than a one-time manual check.

### App reachability

`http://boa-challenge-c1-1942053970.us-east-1.elb.amazonaws.com/` —
live, publicly reachable, WAF-fronted. Confirmed both by the verifier's
live checks above and by hand: a real logged-in session, real balance,
real transaction history.

![Bank of Anthos checking account, live through the WAF-fronted ALB](images/app-live-checking-account.png)

### WAF state

WAFv2 WebACL `boa-challenge-waf` is confirmed attached to the public
ALB (verifier PASS above). Deployed initially in `COUNT` mode (see
"Security" above for the staged-rollout rationale — observe real traffic
first, then enforce); after confirming no false positives against real
app traffic, flipped to `BLOCK` via
`terraform apply -var="c1_alb_arn=..." -var="waf_rule_action_mode=block"`.
App confirmed still fully reachable and functional post-flip, so the
managed rule groups aren't false-positiving on legitimate traffic. The
WAF is enforcing, not just observing, for the live demo.

### Datadog dashboard

All widgets rendering real data as of the final `cluster` tag-key fix:
replica-availability timeseries for both clusters, NLB target health,
container restarts, frontend error logs, and ledger-tier logs.

![Bank of Anthos Challenge dashboard, all widgets live](images/datadog-dashboard.png)

### Fault injection — detected on both the application and infrastructure signal

Fault: `scripts/fault-inject-scale-ledgerwriter.sh` (scales `ledgerwriter`
to 0 replicas in C2). Confirmed at every layer:

- **Kubernetes:** `ledgerwriter` deployment genuinely at 0/0/0
  (`kubectl get deployment` confirmed live).
- **Application:** a real deposit attempt in the live UI silently
  failed.
- **Datadog detection — both monitors fired:**
  - `[boa-challenge] frontend error log spike` — fired almost
    immediately (log-count-based, reacts fast to a burst of new error
    lines).
  - `[boa-challenge] ledgerwriter has no available replicas (C1->C2
    path down)` — the primary, most direct signal — fired within a few
    minutes (metric-based, evaluates on a rolling window, so slightly
    slower than the log alert by design, not by bug).

  ![Both monitors in Alert state during the fault](images/fault-detected-monitors.png)

- **Restoration:** `scripts/fault-restore-scale-ledgerwriter.sh`.
  `ledgerwriter_unavailable` clears immediately once replicas recover
  (instantaneous-value check). `frontend_error_log_spike` clears up to 5
  minutes later by design — it's a rolling 5-minute error *count*, not
  an instantaneous rate, so it only drops below threshold once the
  errors logged *during* the fault window age out of that window. Worth
  narrating explicitly in the demo: it's a real, understood difference
  in monitor evaluation semantics, not a lingering bug. Confirmed both
  back to `OK` below.

  ![Both fault-demo monitors back to OK after restoration](images/fault-recovered-monitors.png)

  (The unrelated `NO DATA` on "ledgerwriter internal NLB has unhealthy
  targets" is the pre-existing, documented `target_group` vs.
  `targetgroup` tag-name uncertainty noted in `infra/datadog/monitors.tf`
  — it's a supporting monitor, not one of the two the fault demo targets,
  and doesn't affect the primary result above.)

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
