variable "name_prefix" {
  type = string
}

variable "rule_action_mode" {
  description = "\"count\" or \"block\" — see root variable waf_rule_action_mode for the staged-rollout rationale."
  type        = string
}

variable "include_anonymous_ip_list" {
  type = bool
}

variable "rate_limit_per_5min" {
  type = number
}

variable "alb_arn" {
  description = "ALB ARN to associate the WebACL with. Leave null on the first apply (the ALB doesn't exist yet — it's created by the AWS Load Balancer Controller from the Kubernetes Ingress). Pass it in on a later apply once the app is deployed."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
