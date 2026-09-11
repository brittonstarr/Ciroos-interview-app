output "c1_cluster_name" {
  value = module.eks_c1.cluster_name
}

output "c2_cluster_name" {
  value = module.eks_c2.cluster_name
}

output "c1_region" {
  value = var.c1_region
}

output "c2_region" {
  value = var.c2_region
}

output "c1_vpc_id" {
  value = module.network_c1.vpc_id
}

output "c2_vpc_id" {
  value = module.network_c2.vpc_id
}

output "c1_alb_controller_role_arn" {
  value = module.eks_c1.alb_controller_role_arn
}

output "c2_alb_controller_role_arn" {
  value = module.eks_c2.alb_controller_role_arn
}

output "peering_connection_id" {
  value = module.peering.peering_connection_id
}

output "waf_web_acl_arn" {
  value = module.waf.web_acl_arn
}

output "waf_associated_with_alb" {
  value = module.waf.associated
}

output "kubeconfig_commands" {
  description = "Run these to point kubectl at each cluster."
  value = <<-EOT
    aws eks update-kubeconfig --name ${module.eks_c1.cluster_name} --region ${var.c1_region} --alias c1
    aws eks update-kubeconfig --name ${module.eks_c2.cluster_name} --region ${var.c2_region} --alias c2
  EOT
}
