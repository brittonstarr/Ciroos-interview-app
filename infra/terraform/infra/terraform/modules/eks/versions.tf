# Silences Terraform's "Reference to undefined provider" warning: the root
# passes an aliased provider (aws.c1 / aws.c2) into this module's default
# "aws" provider slot, which works fine implicitly, but Terraform wants an
# explicit declaration that this module expects a provider named "aws".
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}
