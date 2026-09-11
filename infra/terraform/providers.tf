# Two aliased AWS providers, one per region/cluster. There is no "default"
# (unaliased) provider on purpose — every resource and module call must be
# explicit about which region it targets. This is what lets us stand up
# C1 and C2 from a single `terraform apply` while keeping the modules
# region-agnostic and reusable.

provider "aws" {
  alias  = "c1"
  region = var.c1_region

  default_tags {
    tags = {
      Project   = var.project_name
      Cluster   = "c1"
      ManagedBy = "terraform"
    }
  }
}

provider "aws" {
  alias  = "c2"
  region = var.c2_region

  default_tags {
    tags = {
      Project   = var.project_name
      Cluster   = "c2"
      ManagedBy = "terraform"
    }
  }
}
