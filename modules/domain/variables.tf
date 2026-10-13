variable "zone_name" {
  description = "The Cloudflare zone, e.g. pokemaker.fun. Its apex and www are reserved for the marketing site."
  type        = string
}

variable "hostname" {
  description = "The app's hostname inside the zone, e.g. app.pokemaker.fun."
  type        = string
}

variable "cloudflare_zone_id" {
  type = string
}

variable "cloudfront_domain_name" {
  description = "The distribution's *.cloudfront.net name that the CNAME points to."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
