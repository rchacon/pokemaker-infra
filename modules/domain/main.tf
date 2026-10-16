# PokeMaker's hostnames in the pokemaker.fun zone (DNS hosted at Cloudflare):
#
#   app.pokemaker.fun  → CloudFront (the site, with /api/* routed to the server)
#   api.pokemaker.fun  → the API server's Elastic IP. CloudFront's origin; not
#                        for browsers (the server only accepts CloudFront).
#
# This module only ever manages records for those two hostnames. The apex
# (pokemaker.fun) and www are reserved for a separate marketing site and must
# not be claimed here.
#
# - ACM certificate for the hostname (CloudFront only accepts certificates from
#   us-east-1, so the caller passes a us-east-1 aws provider).
# - Validation record and the hostname's CNAME are created in Cloudflare by
#   Terraform, so the certificate is issued within the same apply.
# - Records are DNS-only (proxied = false): CloudFront is already the CDN and
#   terminates TLS with the ACM certificate; Cloudflare's proxy in front would
#   be a second CDN for no benefit.

resource "aws_acm_certificate" "app" {
  domain_name       = var.hostname
  validation_method = "DNS"
  tags              = var.tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition = alltrue([
        for host in [var.hostname, var.api_hostname] :
        host != var.zone_name && host != "www.${var.zone_name}"
      ])
      error_message = "${var.zone_name} and www.${var.zone_name} are reserved for the marketing site; use subdomains such as app.${var.zone_name} and api.${var.zone_name}."
    }
  }
}

resource "cloudflare_dns_record" "validation" {
  for_each = {
    for option in aws_acm_certificate.app.domain_validation_options : option.domain_name => option
  }

  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(each.value.resource_record_name, ".")
  type    = each.value.resource_record_type
  content = trimsuffix(each.value.resource_record_value, ".")
  ttl     = 300
  proxied = false
  comment = "ACM validation for ${each.key} (pokemaker-infra)"
}

resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in cloudflare_dns_record.validation : record.name]
}

resource "cloudflare_dns_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = var.hostname
  type    = "CNAME"
  content = var.cloudfront_domain_name
  ttl     = 300
  proxied = false
  comment = "PokeMaker app (pokemaker-infra)"
}

# The server's certificate comes from Let's Encrypt (issued on the server
# itself), so this record only needs to point at its address.
resource "cloudflare_dns_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = var.api_hostname
  type    = "A"
  content = var.api_ip
  ttl     = 300
  proxied = false
  comment = "PokeMaker API server, CloudFront origin (pokemaker-infra)"
}
