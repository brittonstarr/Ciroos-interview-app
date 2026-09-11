# Datadog's AWS integration: lets Datadog pull CloudWatch metrics for the
# infra we built (NLB/ALB target health, WAF request counts, NAT Gateway
# throughput, etc.) via cross-account IAM role assumption — no access keys
# involved, Datadog assumes this role from their own AWS account.
#
# CONFIDENCE NOTE: the account ID below (464622532012) and the
# external-id-then-role pattern are confirmed current against Datadog's
# own docs.datadoghq.com/integrations/guide/aws-terraform-setup/ page.
# The schema below (logs_config/metrics_config/traces_config/
# resources_config all required top-level blocks on
# datadog_integration_aws_account, and `iam_permissions` — not
# `permissions` — as the exported attribute on
# datadog_integration_aws_iam_permissions, which takes no arguments) was
# confirmed against the provider's own docs on 2026-09-11 after an
# earlier draft's guesses failed real `terraform plan` validation. If a
# future provider upgrade changes this again, the
# AWS_MANAGED_POLICY_FALLBACK below is a safe, if broader, substitute
# (just flip the `count`s).

resource "datadog_integration_aws_account" "this" {
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_partition  = "aws"

  aws_regions {
    include_all = true
  }

  auth_config {
    aws_auth_config_role {
      role_name = "${var.project_name}-datadog-integration"
    }
  }

  resources_config {
    cloud_security_posture_management_collection = false
    extended_collection                          = true
  }

  # These three blocks are required by the provider (each with a required
  # nested block of its own — lambda_forwarder / namespace_filters /
  # xray_services), but every field inside is optional, so an empty
  # nested block just takes the provider's own sane defaults: no Lambda
  # log forwarding is configured (we're not shipping logs via a Lambda
  # forwarder — the Datadog Agent DaemonSet handles logs directly),
  # default CloudWatch namespace collection, and no X-Ray trace
  # collection (not used in this challenge).
  logs_config {
    lambda_forwarder {}
  }

  metrics_config {
    namespace_filters {}
  }

  traces_config {
    xray_services {}
  }

  account_tags = ["project:${var.project_name}"]
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "datadog_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::464622532012:root"] # Datadog's AWS account (US1/US3/US5/EU sites)
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      # auth_config / aws_auth_config_role are single nested blocks in this
      # provider's schema ("(Block)", not "(Block List)") — the provider
      # was migrated to the modern plugin framework, which exposes a
      # single nested block as an object attribute, not a one-element
      # list like the older SDKv2-style blocks. So this is plain
      # attribute (dot) access, no `[0]` index — real `terraform plan`
      # confirmed the index syntax is rejected outright.
      values = [datadog_integration_aws_account.this.auth_config.aws_auth_config_role.external_id]
    }
  }
}

resource "aws_iam_role" "datadog_integration" {
  name               = "${var.project_name}-datadog-integration"
  assume_role_policy = data.aws_iam_policy_document.datadog_trust.json
  tags               = { Project = var.project_name }
}

# Datadog-provided data source that returns exactly the read-only
# permissions their integration needs (kept in sync with their own
# feature set, rather than a hand-maintained policy here going stale).
# Takes no arguments; the permissions list is exported as
# `iam_permissions` (not `permissions`).
data "datadog_integration_aws_iam_permissions" "this" {}

resource "aws_iam_role_policy" "datadog_integration" {
  count  = length(data.datadog_integration_aws_iam_permissions.this.iam_permissions) > 0 ? 1 : 0
  name   = "${var.project_name}-datadog-permissions"
  role   = aws_iam_role.datadog_integration.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = data.datadog_integration_aws_iam_permissions.this.iam_permissions
      Resource = "*"
    }]
  })
}

# Fallback (disabled by default): if the data source above doesn't match
# the provider version you end up with, comment out the two resources
# above and set this count to 1 instead. Broader than strictly necessary,
# but standard AWS-managed read-only policies, so still no write access.
resource "aws_iam_role_policy_attachment" "fallback_readonly" {
  count      = 0
  role       = aws_iam_role.datadog_integration.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
