# Datadog's AWS integration: lets Datadog pull CloudWatch metrics for the
# infra we built (NLB/ALB target health, WAF request counts, NAT Gateway
# throughput, etc.) via cross-account IAM role assumption — no access keys
# involved, Datadog assumes this role from their own AWS account.
#
# CONFIDENCE NOTE (read this before applying): the account ID below
# (464622532012) and the general external-id-then-role pattern are
# confirmed current as of writing against Datadog's own
# docs.datadoghq.com/integrations/guide/aws-terraform-setup/ page. The
# exact attribute names on datadog_integration_aws_iam_permissions below
# could not be double-checked against a live Terraform Registry render
# from this sandbox (registry.terraform.io serves its docs via
# JS-rendered pages this environment couldn't fetch content from). Run
# `terraform init && terraform validate` here first — if that data
# source's attributes have changed, the AWS_MANAGED_POLICY_FALLBACK
# below is a safe, if broader, substitute (just flip the `count`s).

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
    extended_collection                           = true
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
      values   = [datadog_integration_aws_account.this.auth_config[0].aws_auth_config_role[0].external_id]
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
data "datadog_integration_aws_iam_permissions" "this" {
  account_type = "monitor"
}

resource "aws_iam_role_policy" "datadog_integration" {
  count  = length(data.datadog_integration_aws_iam_permissions.this.permissions) > 0 ? 1 : 0
  name   = "${var.project_name}-datadog-permissions"
  role   = aws_iam_role.datadog_integration.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = data.datadog_integration_aws_iam_permissions.this.permissions
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
