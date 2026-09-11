# Cross-region VPC Peering: the Phase 1 (baseline) private-connectivity
# mechanism between C1 and C2. This module needs both regions' providers
# simultaneously (requester + accepter live in different regions/provider
# configs), so it declares configuration_aliases and the root passes both
# in via the `providers = {}` block at the call site.
#
# Least-privilege is enforced at three layers here:
#   1. Routing: only the specific private route tables that need it get a
#      route to the peer VPC — not a blanket "route everything" default.
#   2. Security group: C2's ingress rule only allows the ledger service
#      ports, and only from C1's specific frontend-hosting subnet CIDRs
#      (not the whole C1 VPC).
#   3. Kubernetes NetworkPolicy (applied at the app-deploy stage, see
#      /k8s) narrows this further to pod-level: even within the allowed
#      SG/port, only the intended Pods can be reached.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.c1, aws.c2]
    }
  }
}

resource "aws_vpc_peering_connection" "this" {
  provider = aws.c1

  vpc_id      = var.c1_vpc_id
  peer_vpc_id = var.c2_vpc_id
  peer_region = var.c2_region

  tags = merge(var.tags, {
    Name = "c1-c2-peering"
  })
}

resource "aws_vpc_peering_connection_accepter" "this" {
  provider = aws.c2

  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
  auto_accept               = true

  tags = merge(var.tags, {
    Name = "c1-c2-peering-accepter"
  })
}

# --- Routes: C1 private subnets -> C2 VPC CIDR ------------------------------

resource "aws_route" "c1_to_c2" {
  provider = aws.c1

  count                     = length(var.c1_private_route_table_ids)
  route_table_id            = var.c1_private_route_table_ids[count.index]
  destination_cidr_block    = var.c2_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id

  depends_on = [aws_vpc_peering_connection_accepter.this]
}

# --- Routes: C2 private subnets -> C1 VPC CIDR ------------------------------

resource "aws_route" "c2_to_c1" {
  provider = aws.c2

  count                     = length(var.c2_private_route_table_ids)
  route_table_id            = var.c2_private_route_table_ids[count.index]
  destination_cidr_block    = var.c1_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id

  depends_on = [aws_vpc_peering_connection_accepter.this]
}

# --- Security group: allow only C1's frontend subnets -> C2 ledger ports ---

resource "aws_security_group_rule" "c1_to_ledger" {
  provider = aws.c2

  for_each          = toset([for p in var.ledger_service_ports : tostring(p)])
  type              = "ingress"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  protocol          = "tcp"
  cidr_blocks       = var.c1_source_cidrs
  security_group_id = var.c2_cluster_security_group_id
  description       = "C1 frontend -> C2 ledger tier (port ${each.value}) over VPC peering only"
}
