variable "name_prefix" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  description = "Needed so the EKS-managed load balancer resources can discover public subnets for internet-facing ALBs. Pass an empty list for a cluster that should never have an internet-facing ALB (C2)."
  type        = list(string)
  default     = []
}

variable "endpoint_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "node_instance_type" {
  type = string
}

variable "node_desired_size" {
  type = number
}

variable "node_min_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

variable "tags" {
  type    = map(string)
  default = {}
}
