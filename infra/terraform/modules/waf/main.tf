# Regional WAFv2 WebACL for the C1 ALB, built entirely from AWS-maintained
# managed rule groups (no third-party marketplace subscription — avoids
# procurement/approval delay and keeps this at zero incremental cost beyond
# standard WAF request-evaluation charges).
#
# Staged rollout: every rule group's override_action defaults to COUNT
# (var.rule_action_mode = "count") so we can validate against real traffic
# for false positives before flipping to BLOCK.

locals {
  override_action_count = var.rule_action_mode == "count"
}

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name_prefix}-waf"
  description = "WAF for ${var.name_prefix} public ALB (frontend)"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # --- AWS Managed Rules: Core rule set (generic OWASP-style protections) --
  rule {
    name     = "AWS-CommonRuleSet"
    priority = 1

    override_action {
      dynamic "count" {
        for_each = local.override_action_count ? [1] : []
        content {}
      }
      dynamic "none" {
        for_each = local.override_action_count ? [] : [1]
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # --- AWS Managed Rules: known bad inputs ----------------------------------
  rule {
    name     = "AWS-KnownBadInputs"
    priority = 2

    override_action {
      dynamic "count" {
        for_each = local.override_action_count ? [1] : []
        content {}
      }
      dynamic "none" {
        for_each = local.override_action_count ? [] : [1]
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # --- AWS Managed Rules: SQL injection (relevant — Postgres-backed forms) --
  rule {
    name     = "AWS-SQLi"
    priority = 3

    override_action {
      dynamic "count" {
        for_each = local.override_action_count ? [1] : []
        content {}
      }
      dynamic "none" {
        for_each = local.override_action_count ? [] : [1]
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-sqli"
      sampled_requests_enabled   = true
    }
  }

  # --- AWS Managed Rules: Amazon IP reputation list (the "blacklist") ------
  rule {
    name     = "AWS-IpReputation"
    priority = 4

    override_action {
      dynamic "count" {
        for_each = local.override_action_count ? [1] : []
        content {}
      }
      dynamic "none" {
        for_each = local.override_action_count ? [] : [1]
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # --- Optional: Anonymous IP list (VPN/proxy/Tor) — off by default --------
  dynamic "rule" {
    for_each = var.include_anonymous_ip_list ? [1] : []
    content {
      name     = "AWS-AnonymousIpList"
      priority = 5

      override_action {
        dynamic "count" {
          for_each = local.override_action_count ? [1] : []
          content {}
        }
        dynamic "none" {
          for_each = local.override_action_count ? [] : [1]
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesAnonymousIpList"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-anonymous-ip"
        sampled_requests_enabled   = true
      }
    }
  }

  # --- Custom rate-based rule: basic brute-force/DDoS guard -----------------
  rule {
    name     = "RateLimitPerIp"
    priority = 10

    action {
      dynamic "count" {
        for_each = local.override_action_count ? [1] : []
        content {}
      }
      dynamic "block" {
        for_each = local.override_action_count ? [] : [1]
        content {}
      }
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit_per_5min
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-webacl"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

# --- Logging: WAF -> Kinesis Firehose -> S3 -> Datadog Forwarder Lambda ----

resource "aws_s3_bucket" "waf_logs" {
  bucket = "${var.name_prefix}-waf-logs-${data.aws_caller_identity.current.account_id}"

  tags = var.tags
}

resource "aws_s3_bucket_lifecycle_configuration" "waf_logs" {
  bucket = aws_s3_bucket.waf_logs.id

  rule {
    id     = "expire-after-14-days"
    status = "Enabled"
    filter {} # empty filter = applies to every object in the bucket
    expiration {
      days = 14
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "firehose" {
  name = "${var.name_prefix}-waf-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "firehose_s3" {
  name = "${var.name_prefix}-waf-firehose-s3"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject",
      ]
      Resource = [
        aws_s3_bucket.waf_logs.arn,
        "${aws_s3_bucket.waf_logs.arn}/*",
      ]
    }]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "waf_logs" {
  # WAF's logging destination requires the "aws-waf-logs-" name prefix.
  name        = "aws-waf-logs-${var.name_prefix}"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.waf_logs.arn
    prefix     = "waf/"
  }

  tags = var.tags
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_kinesis_firehose_delivery_stream.waf_logs.arn]
}

# --- Association to the ALB (second-apply step, see variable description) --

resource "aws_wafv2_web_acl_association" "alb" {
  count        = var.alb_arn != null ? 1 : 0
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
