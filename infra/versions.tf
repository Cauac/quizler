terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "quizler-terraform"
    key          = "terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "eu-north-1"

  default_tags {
    tags = { Project = "quizler", ManagedBy = "terraform" }
  }
}

# CloudFront only accepts ACM certificates from us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = { Project = "quizler", ManagedBy = "terraform" }
  }
}
