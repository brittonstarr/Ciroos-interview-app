variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  description = "Issuer URL without the https:// scheme, e.g. oidc.eks.us-east-1.amazonaws.com/id/XXXX"
  type        = string
}

variable "namespace" {
  type = string
}

variable "service_account_name" {
  type = string
}

variable "role_name" {
  type = string
}

variable "policy_arns" {
  description = "Managed policy ARNs to attach."
  type        = list(string)
  default     = []
}

variable "inline_policy_json" {
  description = "Optional inline policy document JSON to attach in addition to policy_arns."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
