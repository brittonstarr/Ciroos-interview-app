variable "c1_vpc_id" {
  type = string
}

variable "c1_vpc_cidr" {
  type = string
}

variable "c1_region" {
  type = string
}

variable "c1_private_route_table_ids" {
  type = list(string)
}

variable "c1_source_cidrs" {
  description = "The specific C1 subnet CIDR(s) allowed to reach C2's ledger tier (the private subnets that actually host the frontend Pods) — deliberately narrower than the whole C1 VPC CIDR."
  type        = list(string)
}

variable "c2_vpc_id" {
  type = string
}

variable "c2_vpc_cidr" {
  type = string
}

variable "c2_region" {
  type = string
}

variable "c2_private_route_table_ids" {
  type = list(string)
}

variable "c2_cluster_security_group_id" {
  description = "C2 EKS cluster security group (shared by nodes/Pods) to receive the scoped ingress rule."
  type        = string
}

variable "ledger_service_ports" {
  type = list(number)
}

variable "tags" {
  type    = map(string)
  default = {}
}
