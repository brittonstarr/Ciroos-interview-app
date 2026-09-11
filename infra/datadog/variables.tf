variable "dd_site" {
  description = "Datadog site your org's account lives on. US1 (default) is datadoghq.com; others include datadoghq.eu, us3.datadoghq.com, us5.datadoghq.com, ap1.datadoghq.com."
  type        = string
  default     = "datadoghq.com"
}

variable "aws_region" {
  description = "Region for the AWS provider used only to create the Datadog integration IAM role (IAM is global; any region works)."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "boa-challenge"
}
