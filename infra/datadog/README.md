# Datadog — AWS integration, dashboard, monitors

Separate Terraform root from `infra/terraform/` on purpose: different
provider/credentials, own state file, and it reads the AWS side's outputs
via `terraform_remote_state` rather than being tangled into the same
`terraform apply`.

## Prerequisites

1. `infra/terraform/` has already been applied (this reads its state for
   cluster names).
2. A Datadog API key **and** an Application key, both exported:
   ```bash
   export DD_API_KEY=...
   export DD_APP_KEY=...
   ```
   The API key is what the Agent uses to *send* data (already handled by
   `scripts/09-install-datadog-agent.sh`). The Application key is what
   Terraform needs to *manage* Datadog resources (dashboards, monitors,
   the AWS integration) — a different credential, generated under
   Organization Settings -> Application Keys in the Datadog UI.
3. If your org's Datadog account isn't on the default US1 site
   (`datadoghq.com`), set `-var="dd_site=us3.datadoghq.com"` (or eu/us5/ap1)
   on apply.

## Apply

```bash
cd infra/datadog
terraform init
terraform apply
```

Creates: the cross-account IAM role + `datadog_integration_aws_account`
registration (so Datadog pulls CloudWatch metrics — NLB target health, ALB,
WAF, NAT Gateway — from this AWS account), one dashboard, and four
monitors. See `monitors.tf` for which one is the primary fault-demo signal.

## Validation caveat

Same note as the rest of this repo: written carefully but not run through
`terraform validate` from the sandbox this was built in (no network path to
the Terraform or Datadog provider registries there). `aws-integration.tf`
and `dashboard.tf` both carry inline comments on the specific spots most
likely to need a small fix against whatever provider version you land on —
run `terraform validate` first and treat any error there as expected
troubleshooting, not a sign something is fundamentally wrong.
