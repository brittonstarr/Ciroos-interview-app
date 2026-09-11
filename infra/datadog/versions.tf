terraform {
  required_version = ">= 1.7.0"

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.39, < 6.0.0"
    }
  }
}
