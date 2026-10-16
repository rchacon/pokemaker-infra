locals {
  name     = "pokemaker-${var.environment}"
  app_host = "${var.app_subdomain}.${var.domain_name}"
  api_host = "${var.api_subdomain}.${var.domain_name}"
  tags = {
    app         = "pokemaker"
    environment = var.environment
    managed_by  = "terraform"
  }
}

data "aws_caller_identity" "current" {}

module "storage" {
  source = "../../modules/storage"

  table_name          = var.table_name
  artwork_bucket_name = "${local.name}-artwork-${data.aws_caller_identity.current.account_id}"
  # Browser origin allowed to load artwork (needed for PNG/PDF export).
  cors_allowed_origins = ["https://${local.app_host}"]
  deletion_protection  = true
}

# The API: the pokemaker-api Docker image on one small EC2 instance.
module "server" {
  source = "../../modules/server"

  name                               = local.name
  environment                        = var.environment
  aws_region                         = var.aws_region
  family_id                          = var.family_id
  table_name                         = module.storage.table_name
  table_arn                          = module.storage.table_arn
  artwork_bucket_name                = module.storage.artwork_bucket_name
  artwork_bucket_arn                 = module.storage.artwork_bucket_arn
  api_hostname                       = local.api_host
  instance_type                      = var.instance_type
  acme_email                         = var.acme_email
  cloudflare_dns_token_ssm_parameter = var.cloudflare_dns_token_ssm_parameter
  openai_api_key_ssm_parameter       = var.openai_api_key_ssm_parameter
  pin_token_secret_ssm_parameter     = var.pin_token_secret_ssm_parameter
  artwork_provider                   = var.artwork_provider
  openai_image_model                 = var.openai_image_model
  openai_image_quality               = var.openai_image_quality
  daily_generation_limit             = var.daily_generation_limit
  rate_limit_per_minute              = var.rate_limit_per_minute
  tags                               = local.tags
}

# The site: S3 + CloudFront, with /api/* routed to the server.
module "frontend" {
  source = "../../modules/frontend"

  name                 = local.name
  site_bucket_name     = "${local.name}-site-${data.aws_caller_identity.current.account_id}"
  api_origin_hostname  = local.api_host
  origin_verify_secret = module.server.origin_secret
  aliases              = [local.app_host]
  acm_certificate_arn  = module.domain.certificate_arn
  # The raw *.cloudfront.net name redirects to the app's hostname.
  canonical_host = local.app_host
}

# app.pokemaker.fun (certificate + CNAME to CloudFront) and api.pokemaker.fun
# (A record to the server). The apex and www are left for the marketing site.
module "domain" {
  source = "../../modules/domain"

  providers = {
    aws = aws.us_east_1 # CloudFront certificates must live in us-east-1
  }

  zone_name              = var.domain_name
  hostname               = local.app_host
  api_hostname           = local.api_host
  api_ip                 = module.server.public_ip
  cloudflare_zone_id     = var.cloudflare_zone_id
  cloudfront_domain_name = module.frontend.domain_name
}

# An AWS-side safety net: email when the month's AWS bill looks unusual.
# (OpenAI charges are separate; set a budget in the OpenAI dashboard too.)
resource "aws_budgets_budget" "monthly" {
  count        = var.budget_alert_email == null ? 0 : 1
  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:app$pokemaker"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
