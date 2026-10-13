variable "domain_name" {
  description = "Apex domain, e.g. pokemaker.fun. www.<domain> is included and redirects to it."
  type        = string
}

variable "cloudflare_zone_id" {
  type = string
}

variable "cloudfront_domain_name" {
  description = "The distribution's *.cloudfront.net name that the CNAMEs point to."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
