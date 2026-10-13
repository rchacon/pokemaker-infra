locals {
  name = "pokemaker-${var.environment}"
  tags = {
    app         = "pokemaker"
    environment = var.environment
    managed_by  = "terraform"
  }
  # Browser origins allowed to load artwork (needed for PNG/PDF export).
  site_origins = concat(
    ["https://${module.frontend.domain_name}"],
    var.enable_custom_domain ? ["https://${var.domain_name}", "https://www.${var.domain_name}"] : [],
  )
}

data "aws_caller_identity" "current" {}

module "storage" {
  source = "../../modules/storage"

  table_name           = var.table_name
  artwork_bucket_name  = "${local.name}-artwork-${data.aws_caller_identity.current.account_id}"
  cors_allowed_origins = local.site_origins
  deletion_protection  = true
}

module "api" {
  source = "../../modules/api"

  name                           = local.name
  environment                    = var.environment
  aws_region                     = var.aws_region
  family_id                      = var.family_id
  table_name                     = module.storage.table_name
  table_arn                      = module.storage.table_arn
  artwork_bucket_name            = module.storage.artwork_bucket_name
  artwork_bucket_arn             = module.storage.artwork_bucket_arn
  lambda_zip_path                = var.lambda_zip_path
  reserved_concurrency           = var.lambda_reserved_concurrency
  artwork_provider               = var.artwork_provider
  openai_api_key_ssm_parameter   = var.openai_api_key_ssm_parameter
  pin_token_secret_ssm_parameter = var.pin_token_secret_ssm_parameter
  openai_image_model             = var.openai_image_model
  openai_image_quality           = var.openai_image_quality
  daily_generation_limit         = var.daily_generation_limit
  throttle_burst                 = var.api_throttle_burst
  throttle_rate                  = var.api_throttle_rate
}

module "frontend" {
  source = "../../modules/frontend"

  name                = local.name
  site_bucket_name    = "${local.name}-site-${data.aws_caller_identity.current.account_id}"
  api_endpoint        = module.api.api_endpoint
  aliases             = var.enable_custom_domain ? module.domain[0].aliases : []
  acm_certificate_arn = var.enable_custom_domain ? module.domain[0].certificate_arn : null
  # www and the raw *.cloudfront.net name redirect to the apex.
  canonical_host = var.enable_custom_domain ? var.domain_name : null
}

module "domain" {
  source = "../../modules/domain"
  count  = var.enable_custom_domain ? 1 : 0

  providers = {
    aws = aws.us_east_1
  }

  domain_name            = var.domain_name
  cloudflare_zone_id     = var.cloudflare_zone_id
  cloudfront_domain_name = module.frontend.domain_name
}

# An AWS-side safety net: email when the month's AWS bill looks unusual.
# (OpenAI charges are separate — set a budget in the OpenAI dashboard too.)
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
