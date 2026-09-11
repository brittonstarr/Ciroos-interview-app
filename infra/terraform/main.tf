# Root module: wires the network, EKS, cross-region peering, and WAF
# modules together for both clusters in a single `terraform apply`. Kept
# intentionally flat (no separate per-env directories) — this is a
# single-environment build, and the composability the project calls for
# comes from the modules themselves, which are region-agnostic and take
# all identifying values as inputs.

locals {
  tags_c1 = { Cluster = "c1", Region = var.c1_region }
  tags_c2 = { Cluster = "c2", Region = var.c2_region }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

module "network_c1" {
  source = "./modules/network"
  providers = {
    aws = aws.c1
  }

  name_prefix           = "${var.project_name}-c1"
  vpc_cidr               = var.c1_vpc_cidr
  public_subnet_cidrs    = var.c1_public_subnet_cidrs
  private_subnet_cidrs   = var.c1_private_subnet_cidrs
  single_nat_gateway     = true
  tags                   = local.tags_c1
}

module "network_c2" {
  source = "./modules/network"
  providers = {
    aws = aws.c2
  }

  name_prefix           = "${var.project_name}-c2"
  vpc_cidr               = var.c2_vpc_cidr
  public_subnet_cidrs    = var.c2_public_subnet_cidrs
  private_subnet_cidrs   = var.c2_private_subnet_cidrs
  single_nat_gateway     = true
  tags                   = local.tags_c2
}

# ---------------------------------------------------------------------------
# EKS clusters
# ---------------------------------------------------------------------------

module "eks_c1" {
  source = "./modules/eks"
  providers = {
    aws = aws.c1
  }

  name_prefix                   = "${var.project_name}-c1"
  kubernetes_version             = var.kubernetes_version
  vpc_id                         = module.network_c1.vpc_id
  private_subnet_ids             = module.network_c1.private_subnet_ids
  public_subnet_ids              = module.network_c1.public_subnet_ids # C1 has an internet-facing ALB
  endpoint_public_access_cidrs   = var.cluster_endpoint_public_access_cidrs
  node_instance_type             = var.node_instance_type
  node_desired_size               = var.node_desired_size
  node_min_size                   = var.node_min_size
  node_max_size                   = var.node_max_size
  tags                            = local.tags_c1
}

module "eks_c2" {
  source = "./modules/eks"
  providers = {
    aws = aws.c2
  }

  name_prefix                   = "${var.project_name}-c2"
  kubernetes_version             = var.kubernetes_version
  vpc_id                         = module.network_c2.vpc_id
  private_subnet_ids             = module.network_c2.private_subnet_ids
  public_subnet_ids              = []  # C2 never gets an internet-facing ALB
  endpoint_public_access_cidrs   = var.cluster_endpoint_public_access_cidrs
  node_instance_type             = var.node_instance_type
  node_desired_size               = var.node_desired_size
  node_min_size                   = var.node_min_size
  node_max_size                   = var.node_max_size
  tags                            = local.tags_c2
}

# ---------------------------------------------------------------------------
# Private cross-region connectivity (Phase 1: VPC Peering baseline)
# ---------------------------------------------------------------------------

module "peering" {
  source = "./modules/peering"
  providers = {
    aws.c1 = aws.c1
    aws.c2 = aws.c2
  }

  c1_vpc_id                   = module.network_c1.vpc_id
  c1_vpc_cidr                 = var.c1_vpc_cidr
  c1_region                   = var.c1_region
  c1_private_route_table_ids  = module.network_c1.private_route_table_ids
  c1_source_cidrs             = var.c1_private_subnet_cidrs

  c2_vpc_id                   = module.network_c2.vpc_id
  c2_vpc_cidr                 = var.c2_vpc_cidr
  c2_region                   = var.c2_region
  c2_private_route_table_ids  = module.network_c2.private_route_table_ids
  c2_cluster_security_group_id = module.eks_c2.node_security_group_id

  ledger_service_ports = var.ledger_service_ports

  tags = { Purpose = "c1-c2-private-connectivity" }
}

# ---------------------------------------------------------------------------
# WAF (fronts the C1 ALB only)
# ---------------------------------------------------------------------------

module "waf" {
  source = "./modules/waf"
  providers = {
    aws = aws.c1
  }

  name_prefix                = var.project_name
  rule_action_mode           = var.waf_rule_action_mode
  include_anonymous_ip_list  = var.waf_include_anonymous_ip_list
  rate_limit_per_5min        = var.waf_rate_limit_per_5min
  alb_arn                    = var.c1_alb_arn

  tags = local.tags_c1
}
