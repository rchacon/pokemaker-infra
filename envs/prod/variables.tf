variable "environment" {
  type    = string
  default = "prod"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
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
