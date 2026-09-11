output "web_acl_arn" {
  value = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  value = aws_wafv2_web_acl.this.id
}

output "log_bucket" {
  value = aws_s3_bucket.waf_logs.id
}

output "associated" {
  value = var.alb_arn != null
}
