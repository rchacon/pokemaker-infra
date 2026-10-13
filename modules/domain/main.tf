# Custom domain for the CloudFront site, with DNS hosted at Cloudflare.
#
# - ACM certificate for the apex and www (CloudFront only accepts certificates
#   from us-east-1, so the caller passes a us-east-1 aws provider).
# - Validation records and the site's CNAMEs are created in Cloudflare by
#   Terraform, so the certificate is issued within the same apply.
# - Records are DNS-only (proxied = false): CloudFront is already the CDN and
#   terminates TLS with the ACM certificate; Cloudflare's proxy in front would
#   be a second CDN for no benefit.

locals {
  www = "www.${var.domain_name}"
}

resource "aws_acm_certificate" "site" {
  domain_name               = var.domain_name
  subject_alternative_names = [local.www]
  validation_method         = "DNS"
  tags                      = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_dns_record" "validation" {
  for_each = {
    for option in aws_acm_certificate.site.domain_validation_options : option.domain_name => option
  }

  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(each.value.resource_record_name, ".")
  type    = each.value.resource_record_type
  content = trimsuffix(each.value.resource_record_value, ".")
  ttl     = 300
  proxied = false
  comment = "ACM validation for ${each.key} (pokemaker-infra)"
}

resource "aws_acm_certificate_validation" "site" {
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in cloudflare_dns_record.validation : record.name]
}

# The apex is a CNAME too: Cloudflare flattens CNAMEs at the zone apex, so no
# Route53-style ALIAS record is needed.
resource "cloudflare_dns_record" "site" {
  for_each = toset([var.domain_name, local.www])

  zone_id = var.cloudflare_zone_id
  name    = each.value
  type    = "CNAME"
  content = var.cloudfront_domain_name
  ttl     = 300
  proxied = false
  comment = "PokeMaker site (pokemaker-infra)"
}
