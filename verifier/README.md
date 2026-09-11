# Verification tool

Confirms (1) no unintended public access paths exist anywhere in the
environment, and (2) only the intended C1 -> C2 (frontend -> ledger tier)
communication is permitted.

## Install

```bash
cd verifier
pip install -r requirements.txt
```

## Run

```bash
# Static audit only — reads AWS config via boto3, no cluster access needed.
python3 verify.py

# Static audit + live connectivity tests (needs kubectl configured with
# contexts `c1`/`c2` — see scripts/01-configure-kubectl.sh — for the
# positive half; the negative half just needs network access from wherever
# you run this).
python3 verify.py --live
```

AWS credentials: anything `boto3`/the AWS CLI already picks up (env vars,
`~/.aws/credentials`, SSO). `reader-iam-policy.json` is the minimal
read-only policy the static checks actually need, if you'd rather run this
under a scoped-down role than your build-time credentials.

Exit code is `0` only if every check `PASS`ed. `WARN`s (e.g. "not deployed
yet", or the documented EKS-public-endpoint build-time trade-off) don't
fail the run — they're informational, not violations.

## What it checks

**Static (always runs):**
| Check | What it proves |
|---|---|
| C2 load balancers are internal-only | Nothing in the ledger tier is internet-facing |
| C1 public surface limited to the frontend ALB | The *only* internet-facing thing anywhere is the one intended entry point |
| WAF attached to public ALB | The public entry point is actually protected |
| No security group open to the internet outside allowed ports | No accidental 0.0.0.0/0 ingress anywhere except the ALB on 80/443 |
| C2 private subnets have no route to an Internet Gateway | C2 truly has no inbound public path, at the routing level |
| C2 ledger-port SG rule scoped to C1's frontend subnets | The C1->C2 path is scoped to the specific subnets that need it — not the whole C1 VPC, not the world |
| VPC Peering connection active | The private connectivity mechanism is actually up |
| EKS API endpoint exposure | Surfaced as `WARN`, not `FAIL` — see below |

**Live (`--live`):**
| Check | What it proves |
|---|---|
| C1 -> C2 connectivity (positive) | `kubectl exec`s into a frontend Pod in C1 and confirms it *can* reach each C2 ledger service over the configured address — the intended path actually works |
| Public unreachability of each C2 service (negative) | This machine (wherever you run the tool — presumably your own laptop, i.e. the public internet) attempts a direct TCP connection to each C2 service's internal NLB hostname and confirms it *cannot* connect — proves the internal-only NLB really is private, not just labeled that way |

## A note on the EKS public endpoint WARN

The EKS API server's public endpoint is intentionally left open in this
build (a documented build-time convenience trade-off — see
`architecture-design.md` section 10, confirmed with the requester). This
tool surfaces it as a `WARN`, not a `FAIL`: it's the Kubernetes control
plane API, not an application Service, so it's a different category from
"a service is unintentionally exposed." Worth tightening
(`cluster_endpoint_public_access_cidrs` in `infra/terraform/variables.tf`)
before anything longer-lived than this exercise — the tool says so in its
own output rather than silently passing over it.

## Honesty note

This was written and dry-run tested against mocked AWS API responses (to
catch structural bugs in how it parses `boto3` response shapes) from the
sandbox it was built in, which has no network path to real AWS — it has
**not** been run against the actual deployed environment. Run it for real
once the infrastructure is up and send back anything that errors or
surprises you.
