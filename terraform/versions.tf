terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Optional: uncomment to use a remote backend
  # backend "s3" {
  #   bucket = "my-tf-state"
  #   key    = "zeppelin-eks-gitops/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project   = "zeppelin-spark"
        ManagedBy = "terraform"
      },
      var.tags
    )
  }
}
