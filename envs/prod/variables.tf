variable "environment" {
  type    = string
  default = "prod"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "family_id" {
  type    = string
  default = "belchers"
}

variable "table_name" {
  type    = string
  default = "pokemaker"
}

variable "lambda_zip_path" {
  description = "Built by ../pokemaker-api/scripts/build_lambda.sh."
  type        = string
  default     = "../../../pokemaker-api/dist/lambda.zip"
}

variable "lambda_reserved_concurrency" {
  description = "Cap on concurrent Lambda invocations (e.g. 5). Leave null on new accounts with a 10-concurrency limit."
  type        = number
  default     = null
}

variable "artwork_provider" {
  description = "openai, or mock to deploy without spending on image generation."
  type        = string
  default     = "openai"
}

variable "openai_api_key_ssm_parameter" {
  description = "SecureString parameter holding the OpenAI API key. Create it with the AWS CLI; never in Terraform."
  type        = string
  default     = "/pokemaker/prod/openai-api-key"
}

variable "pin_token_secret_ssm_parameter" {
  description = "SecureString parameter with the secret that signs profile-unlock tokens. Create it with the AWS CLI; never in Terraform."
  type        = string
  default     = "/pokemaker/prod/pin-token-secret"
}

variable "openai_image_model" {
  type    = string
  default = "gpt-image-1-mini"
}

variable "openai_image_quality" {
  type    = string
  default = "medium"
}

variable "daily_generation_limit" {
  type    = number
  default = 10
}

variable "api_throttle_burst" {
  type    = number
  default = 20
}

variable "api_throttle_rate" {
  type    = number
  default = 10
}

# Gates the custom domain (ACM certificate + Cloudflare DNS) so the first
# apply can stand up everything on the default *.cloudfront.net URL, before a
# Cloudflare token exists and with zero DNS risk. Flip to true afterwards.
variable "enable_custom_domain" {
  type    = bool
  default = false
}

variable "domain_name" {
  description = "The Cloudflare zone (registered and DNS-hosted there). Its apex and www are reserved for the marketing site."
  type        = string
  default     = "pokemaker.fun"
}

variable "app_subdomain" {
  description = "The app is served at <app_subdomain>.<domain_name>, e.g. app.pokemaker.fun."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.app_subdomain)) && var.app_subdomain != "www"
    error_message = "app_subdomain must be a single DNS label other than www (the apex and www belong to the marketing site)."
  }
}

variable "cloudflare_zone_id" {
  description = "Zone ID of domain_name (Cloudflare dashboard -> the domain's Overview page, right sidebar)."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_custom_domain || var.cloudflare_zone_id != null
    error_message = "cloudflare_zone_id is required when enable_custom_domain = true."
  }
}

# Scoped to Zone:DNS:Edit on this one zone only (Cloudflare -> My Profile ->
# API Tokens -> "Edit zone DNS" template), never the account-wide Global API Key.
# The default is a well-formed placeholder: the provider is always configured,
# but with enable_custom_domain = false nothing ever calls Cloudflare.
variable "cloudflare_api_token" {
  type      = string
  sensitive = true
  default   = "unsetunsetunsetunsetunsetunsetunsetunset"
}

variable "budget_alert_email" {
  description = "Email for AWS cost alerts; null disables the budget."
  type        = string
  default     = null
}

variable "monthly_budget_usd" {
  type    = number
  default = 10
}
