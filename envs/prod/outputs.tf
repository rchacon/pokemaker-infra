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

output "instance_id" {
  description = "The API server (deploys run on it through SSM Run Command)."
  value       = module.server.instance_id
}

output "api_hostname" {
  description = "CloudFront's origin for /api/*. Only accepts requests from CloudFront."
  value       = local.api_host
}

output "server_public_ip" {
  value = module.server.public_ip
}

output "api_log_group" {
  value = module.server.log_group
}

output "api_config_parameter" {
  description = "SSM parameter holding the API's settings (applied on the next deploy)."
  value       = module.server.config_parameter
}

output "table_name" {
  value = module.storage.table_name
}

output "artwork_bucket" {
  value = module.storage.artwork_bucket_name
}
