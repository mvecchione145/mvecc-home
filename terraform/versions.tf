terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws_ecs_express_gateway_service landed in the 6.x line.
      version = ">= 6.62.0, < 7.0.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # State is local by default. Once you have a bucket, uncomment and
  # `terraform init -migrate-state`.
  #
  # backend "s3" {
  #   bucket       = "mvecc-tfstate"
  #   key          = "mvecc-home/terraform.tfstate"
  #   region       = "us-east-2"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# CloudFront reads its certificates only from us-east-1, so the ACM
# certificate for the custom domain is created through this alias.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# Short-lived ECR credentials for the Docker provider. This reads the registry
# by account id rather than from aws_ecr_repository, because a provider block
# cannot depend on a value that is only known after apply.
data "aws_ecr_authorization_token" "ecr" {
  registry_id = data.aws_caller_identity.current.account_id
}

# Docker Desktop on macOS listens on a socket in the user's home directory and
# advertises it through a Docker CLI "context". The Terraform Docker provider
# does not read contexts — it assumes /var/run/docker.sock, which Docker
# Desktop only creates when "Allow the default Docker socket to be used" is
# enabled. Point the provider at the real socket instead.
locals {
  docker_host = coalesce(
    var.docker_host,
    "unix://${pathexpand("~/.docker/run/docker.sock")}",
  )
}

provider "docker" {
  host = local.docker_host

  registry_auth {
    address  = data.aws_ecr_authorization_token.ecr.proxy_endpoint
    username = data.aws_ecr_authorization_token.ecr.user_name
    password = data.aws_ecr_authorization_token.ecr.password
  }
}
