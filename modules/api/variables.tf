variable "name" {
  description = "Base name for the Lambda, API and log groups, e.g. pokemaker-prod."
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

variable "lambda_zip_path" {
  description = "Path to the zip built by pokemaker-api/scripts/build_lambda.sh."
  type        = string
}

variable "memory_mb" {
  type    = number
  default = 512
}

variable "reserved_concurrency" {
  description = "Max concurrent invocations; null uses the shared account pool (new accounts often can't reserve)."
  type        = number
  default     = null
}

variable "artwork_provider" {
  type    = string
  default = "openai"
  validation {
    condition     = contains(["openai", "mock"], var.artwork_provider)
    error_message = "artwork_provider must be openai or mock."
  }
}

variable "openai_api_key_ssm_parameter" {
  description = "Name of the SecureString parameter holding the OpenAI key (created outside Terraform)."
  type        = string
}

variable "pin_token_secret_ssm_parameter" {
  description = "Name of the SecureString parameter holding the PIN unlock-token signing secret (created outside Terraform)."
  type        = string
}

variable "openai_image_model" {
  type    = string
  default = "gpt-image-1-mini"
}

variable "openai_image_quality" {
  type    = string
  default = "medium"
}

variable "openai_image_size" {
  type    = string
  default = "1536x1024"
}

variable "daily_generation_limit" {
  type    = number
  default = 10
}

variable "throttle_burst" {
  type    = number
  default = 20
}

variable "throttle_rate" {
  description = "Steady-state requests per second across the whole API."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "tags" {
  type    = map(string)
  default = {}
}
