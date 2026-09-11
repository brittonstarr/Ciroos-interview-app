output "dashboard_url" {
  value = datadog_dashboard.boa_challenge.url
}

output "datadog_integration_role_arn" {
  value = aws_iam_role.datadog_integration.arn
}

output "datadog_integration_external_id" {
  # Dot access, not [0] index — see the matching comment in
  # aws-integration.tf's datadog_trust policy document.
  value     = datadog_integration_aws_account.this.auth_config.aws_auth_config_role.external_id
  sensitive = true
}
