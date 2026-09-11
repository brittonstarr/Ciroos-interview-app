variable "project_name" {
  description = "Short name used as a prefix/tag on every resource."
  type        = string
  default     = "boa-challenge"
}

# ---------------------------------------------------------------------------
# Regions
# ---------------------------------------------------------------------------

variable "c1_region" {
  description = "Region for Cluster C1 (public-facing identity/UI tier)."
  type        = string
  default     = "us-east-1"
}

variable "c2_region" {
  description = "Region for Cluster C2 (private ledger tier, no public exposure)."
  type        = string
  default     = "us-west-2"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "c1_vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "c1_public_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.0.0/24", "10.10.1.0/24"]
}

variable "c1_private_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.16.0/20", "10.10.32.0/20"]
}

variable "c2_vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "c2_public_subnet_cidrs" {
  description = "C2 still needs public subnets for outbound-only NAT Gateway egress (image pulls, Datadog Agent, etc). Nothing inbound is ever routed here — no ALB, no public Service/NodePort is ever placed in C2. This is not 'public exposure of a service'."
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "c2_private_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.16.0/20", "10.20.32.0/20"]
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS API public endpoint. Defaults wide open for build-time kubectl convenience per the agreed build-time IAM assumption — tighten to your own IP before the interview if you want to lock it down further."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# Cross-cluster ledger connectivity (used by the peering module)
# ---------------------------------------------------------------------------

variable "ledger_service_ports" {
  description = "Ports the C2 ledger-tier services listen on, exposed to C1 only. Bank of Anthos services all listen on 8080 internally."
  type        = list(number)
  default     = [8080]
}

# ---------------------------------------------------------------------------
# WAF
# ---------------------------------------------------------------------------

variable "waf_rule_action_mode" {
  description = "\"count\" for the staged rollout (observe, no blocking) or \"block\" once validated against real traffic."
  type        = string
  default     = "count"

  validation {
    condition     = contains(["count", "block"], var.waf_rule_action_mode)
    error_message = "waf_rule_action_mode must be \"count\" or \"block\"."
  }
}

variable "waf_include_anonymous_ip_list" {
  description = "Whether to include AWSManagedRulesAnonymousIpList (blocks VPN/proxy/Tor). Left off by default so VPN-connected reviewers aren't blocked during the demo."
  type        = bool
  default     = false
}

variable "waf_rate_limit_per_5min" {
  description = "Requests per 5-minute window per source IP before the rate-based rule triggers."
  type        = number
  default     = 2000
}

# ALB ARN is not known until the AWS Load Balancer Controller creates it via
# the Kubernetes Ingress (see k8s/addons). Leave null for the first apply;
# after the app + ingress are deployed, look up the ALB (aws_lb data source
# by tag) and pass its ARN here on a second apply to attach the WAF.
variable "c1_alb_arn" {
  type    = string
  default = null
}
