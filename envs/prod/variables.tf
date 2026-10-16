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

# --- Domain (DNS hosted at Cloudflare) ------------------------------------------

variable "domain_name" {
  description = "The Cloudflare zone. Its apex and www are reserved for the marketing site."
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

variable "api_subdomain" {
  description = "The API server's own hostname, <api_subdomain>.<domain_name>: CloudFront's origin for /api/*, not used by browsers."
  type        = string
  default     = "api"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.api_subdomain)) && var.api_subdomain != "www"
    error_message = "api_subdomain must be a single DNS label other than www."
  }
}

variable "cloudflare_zone_id" {
  description = "Zone ID of domain_name (Cloudflare dashboard -> the domain's Overview page, right sidebar)."
  type        = string
}

# Scoped to Zone:DNS:Edit on this one zone only (Cloudflare -> My Profile ->
# API Tokens -> "Edit zone DNS" template), never the account-wide Global API Key.
variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

# --- Server -----------------------------------------------------------------------

variable "instance_type" {
  description = "Graviton (arm64) instance type for the API server."
  type        = string
  default     = "t4g.micro"
}

variable "acme_email" {
  description = "Email for Let's Encrypt certificate expiry notices (optional)."
  type        = string
  default     = null
}

variable "rate_limit_per_minute" {
  description = "API requests per minute per client IP (a family shares one IP)."
  type        = number
  default     = 600
}

# --- Secrets: created with the AWS CLI, never in Terraform -----------------------

variable "openai_api_key_ssm_parameter" {
  type    = string
  default = "/pokemaker/prod/openai-api-key"
}

variable "pin_token_secret_ssm_parameter" {
  type    = string
  default = "/pokemaker/prod/pin-token-secret"
}

variable "cloudflare_dns_token_ssm_parameter" {
  description = "SecureString with a Cloudflare token (Zone:DNS:Edit on the zone) the server uses to get its TLS certificate."
  type        = string
  default     = "/pokemaker/prod/cloudflare-dns-token"
}

# --- Artwork ----------------------------------------------------------------------

variable "artwork_provider" {
  description = "openai, or mock to deploy without spending on image generation."
  type        = string
  default     = "openai"
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

# --- Cost alert -------------------------------------------------------------------

variable "budget_alert_email" {
  description = "Email for AWS cost alerts; null disables the budget."
  type        = string
  default     = null
}

variable "monthly_budget_usd" {
  type    = number
  default = 20
}
