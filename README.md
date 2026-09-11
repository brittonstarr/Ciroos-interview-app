# Ciroos interview challenge — AWS Application & Infrastructure Observability

Two-region EKS deployment of [Bank of Anthos](https://github.com/GoogleCloudPlatform/bank-of-anthos), split across C1 (`us-east-1`, identity/UI tier, public via ALB+WAF) and C2 (`us-west-2`, ledger tier, no public exposure), connected privately over VPC Peering (with a PrivateLink upgrade planned as a stretch goal).

Full design rationale lives in the project's `architecture-design.md` doc, not duplicated here. This README is the "how to actually run it" entry point.

## Layout

```
infra/terraform/   Network, EKS, peering, WAF — see infra/terraform/README.md
infra/datadog/      AWS integration, dashboard, monitors — see infra/datadog/README.md
k8s/c1/             Identity/UI tier manifests (frontend, userservice, contacts, accounts-db, loadgenerator)
k8s/c2/             Ledger tier manifests (ledgerwriter, balancereader, transactionhistory, ledger-db)
k8s/addons/         Datadog Agent Helm values
scripts/            Numbered, ordered deploy scripts — run scripts/deploy-all.sh, or step through individually
verifier/           Python connectivity/exposure verification tool — see verifier/README.md
docs/               architecture.md (Mermaid diagrams), fault-injection.md (demo plan), write-up.md (design write-up draft)
```

## Deploy order

1. `cd infra/terraform && terraform init && terraform apply` — see `infra/terraform/README.md` for details and the two-phase WAF note.
2. `cd scripts && ./deploy-all.sh` — configures kubectl, installs the AWS Load Balancer Controller on both clusters, generates a fresh JWT signing keypair, deploys C2 then C1 in the order that respects the cross-cluster address dependency, and prints the app URL plus the `terraform apply` command that attaches the WAF.
3. Run the printed `terraform apply -var="c1_alb_arn=..."` command to attach the WAF (staged in COUNT mode — see `infra/terraform/README.md`).
4. `export DD_API_KEY=... && ./scripts/09-install-datadog-agent.sh` — Datadog Agent on both clusters (logs, infra/container metrics, APM/OTLP ready, Cloud Network Monitoring).
5. `export DD_APP_KEY=... && cd infra/datadog && terraform init && terraform apply` — AWS integration (CloudWatch metrics), dashboard, monitors. See `infra/datadog/README.md`.
6. `cd verifier && pip install -r requirements.txt && python3 verify.py --live` — confirms no unintended public exposure and that only the intended C1->C2 path works, both by AWS config audit and by a real positive/negative connectivity test. See `verifier/README.md`.
7. `./scripts/fault-inject-scale-ledgerwriter.sh` — trigger the demo fault, watch it detected in Datadog, then `./scripts/fault-restore-scale-ledgerwriter.sh` to restore. See `docs/fault-injection.md` for the full demo script and a secondary/bonus fault.

Each script in `scripts/` is also runnable individually and documents what it does and why at the top of the file — useful if any one step needs debugging or re-running.

## Teardown

```bash
cd scripts && ./teardown.sh
```

Deletes the Kubernetes-created ALB/NLBs first (required — see the comment in `teardown.sh` for why), then runs `terraform destroy`.

## Prerequisites

AWS CLI v2, Terraform >= 1.7, `kubectl`, `helm`, `openssl`.
