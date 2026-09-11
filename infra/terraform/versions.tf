terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # >= 5.39 for stable aws_eks_access_entry / aws_eks_access_policy_association support.
      version = ">= 5.39, < 6.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Remote state is intentionally left as local backend for this exercise.
  # For a longer-lived project, swap this for an S3 + DynamoDB backend:
  #
  # backend "s3" {
  #   bucket         = "REPLACE-ME-terraform-state-bucket"
  #   key            = "boa-challenge/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "REPLACE-ME-terraform-locks"
  #   encrypt        = true
  # }
}
