variable "name" {
  description = "Base name, e.g. pokemaker-prod."
  type        = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "family_id" {
  type = string
}

variable "table_name" {
  type = string
}

variable "table_arn" {
  type = string
}

variable "artwork_bucket_name" {
  type = string
}

variable "artwork_bucket_arn" {
  type = string
}

variable "api_hostname" {
  description = "The server's own hostname (CloudFront's origin), e.g. api.pokemaker.fun."
  type        = string
}

variable "instance_type" {
  description = "Graviton (arm64) type; the image is built for linux/arm64."
  type        = string
  default     = "t4g.micro"

  validation {
    condition     = can(regex("^[a-z0-9]+g[a-z0-9]*\\.", var.instance_type))
    error_message = "Use a Graviton (arm64) instance type such as t4g.micro: the image is built for linux/arm64."
  }
}

variable "root_volume_gb" {
  type    = number
  default = 10
}

variable "acme_email" {
  description = "Email for Let's Encrypt expiry notices (optional)."
  type        = string
  default     = null
}

variable "cloudflare_dns_token_ssm_parameter" {
  description = "SecureString with a Cloudflare token (Zone:DNS:Edit) that certbot uses for the DNS check."
  type        = string
}

variable "openai_api_key_ssm_parameter" {
  type = string
}

variable "pin_token_secret_ssm_parameter" {
  type = string
}

variable "artwork_provider" {
  type    = string
  default = "openai"

  validation {
    condition     = contains(["openai", "mock"], var.artwork_provider)
    error_message = "artwork_provider must be openai or mock."
  }
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

variable "rate_limit_per_minute" {
  description = "Per client IP. A family shares one home IP address."
  type        = number
  default     = 600
}

variable "unattended_reboot_utc" {
  description = "When security updates may reboot the server (HH:MM, UTC)."
  type        = string
  default     = "10:00" # 3 AM Pacific (daylight time)
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "tags" {
  type    = map(string)
  default = {}
}
