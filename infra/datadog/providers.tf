# The Datadog provider reads DD_API_KEY and DD_APP_KEY from the
# environment automatically — nothing to configure here, and nothing
# credential-shaped ever needs to land in a .tf/.tfvars file. Export both
# before running `terraform apply` in this directory:
#
#   export DD_API_KEY=...
#   export DD_APP_KEY=...   # Application key — separate from the API key,
#                            # needed because this directory *manages*
#                            # Datadog resources (dashboards/monitors/
#                            # integrations), not just sends data to them.

provider "datadog" {
  api_url = "https://api.${var.dd_site}/"
}

# Separate, unaliased AWS provider (IAM is a global service, so region
# only matters for where the provider itself talks to STS/IAM endpoints).
# This is deliberately a separate Terraform root from infra/terraform —
# different concern, different provider set, own state file — while still
# reading that root's outputs via terraform_remote_state below, so nothing
# has to be retyped.
provider "aws" {
  region = var.aws_region
}

data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "${path.module}/../terraform/terraform.tfstate"
  }
}
