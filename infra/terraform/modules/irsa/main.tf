# Generic IAM Roles for Service Accounts (IRSA) role: trusts the cluster's
# OIDC provider, scoped down to one specific namespace/ServiceAccount via
# the `sub` claim condition — a pod can only assume this role if it's
# running as exactly that ServiceAccount. No node-wide credentials.

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = toset(var.policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_policy" "inline" {
  count  = var.inline_policy_json != null ? 1 : 0
  name   = "${var.role_name}-inline"
  policy = var.inline_policy_json
}

resource "aws_iam_role_policy_attachment" "inline" {
  count      = var.inline_policy_json != null ? 1 : 0
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.inline[0].arn
}
