# The app's hostname (app.pokemaker.fun) on the CloudFront site, with DNS
# hosted at Cloudflare.
#
# This module only ever manages records for that one hostname. The apex
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
      condition     = var.hostname != var.zone_name && var.hostname != "www.${var.zone_name}"
      error_message = "${var.zone_name} and www.${var.zone_name} are reserved for the marketing site; use a subdomain such as app.${var.zone_name}."
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
