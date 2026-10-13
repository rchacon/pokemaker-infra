output "site_url" {
  value = var.enable_custom_domain ? "https://${var.domain_name}" : "https://${module.frontend.domain_name}"
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

output "api_endpoint" {
  description = "Direct API Gateway URL. Also public — see README security notes."
  value       = module.api.api_endpoint
}

output "table_name" {
  value = module.storage.table_name
}

output "artwork_bucket" {
  value = module.storage.artwork_bucket_name
}

output "lambda_function_name" {
  value = module.api.lambda_function_name
}
