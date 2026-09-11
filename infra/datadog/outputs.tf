output "dashboard_url" {
  value = datadog_dashboard.boa_challenge.url
}

output "datadog_integration_role_arn" {
  value = aws_iam_role.datadog_integration.arn
}

output "datadog_integration_external_id" {
  value     = datadog_integration_aws_account.this.auth_config[0].aws_auth_config_role[0].external_id
  sensitive = true
}
