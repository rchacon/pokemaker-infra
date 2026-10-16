output "site_url" {
  value = "https://${local.app_host}"
}

output "site_domain" {
  value = module.frontend.domain_name
}

output "site_bucket" {
  value = module.frontend.site_bucket
}

output "cloudfront_distribution_id" {
  value = module.frontend.distribution_id
}

output "aws_region" {
  value = var.aws_region
}

output "table_name" {
  value = module.storage.table_name
}

output "artwork_bucket" {
  value = module.storage.artwork_bucket_name
}
