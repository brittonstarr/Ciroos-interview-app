variable "name_prefix" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "az_count" {
  type    = number
  default = 2
}

variable "public_subnet_cidrs" {
  description = "Public subnets host only NAT Gateways (and, for C1, the ALB). No workload Pods/Services are ever placed here."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "EKS nodes and Pods live here. Outbound-only via NAT Gateway; no direct route to/from the internet."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "true = one shared NAT Gateway (cheaper, fine for a demo). false = one per AZ (more resilient, costs more)."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
