variable "name" {
  type = string
}

variable "site_bucket_name" {
  type = string
}

variable "api_origin_hostname" {
  description = "The API server's hostname (e.g. api.pokemaker.fun), served under /api/* on the site."
  type        = string
}

variable "origin_verify_secret" {
  description = "Value of the X-Origin-Verify header CloudFront adds to API requests."
  type        = string
  sensitive   = true
}

variable "aliases" {
  description = "Optional custom hostname(s), e.g. [\"app.pokemaker.fun\"]. Requires acm_certificate_arn."
  type        = list(string)
  default     = []
}

variable "canonical_host" {
  description = "If set (e.g. app.pokemaker.fun), requests for any other host are redirected here."
  type        = string
  default     = null
}

variable "acm_certificate_arn" {
  description = "ACM certificate in us-east-1 covering the aliases."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
