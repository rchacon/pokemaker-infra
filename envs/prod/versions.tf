terraform {
  required_version = ">= 1.10" # S3 backend native locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Partial configuration: bucket, key and region come from the gitignored
  # backend.hcl (see backend.hcl.example).  terraform init -backend-config=backend.hcl
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

# CloudFront only accepts ACM certificates from us-east-1, whatever aws_region is.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}

# pokemaker.fun's DNS is hosted at Cloudflare. This provider only creates the
# records for app.pokemaker.fun and api.pokemaker.fun (modules/domain); the apex
# and www belong to the marketing site.
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
