output "instance_id" {
  value = aws_instance.server.id
}

output "public_ip" {
  value = aws_eip.server.public_ip
}

output "origin_secret" {
  description = "Sent by CloudFront in X-Origin-Verify; the app refuses requests without it."
  value       = random_password.origin_secret.result
  sensitive   = true
}

output "log_group" {
  value = aws_cloudwatch_log_group.api.name
}

output "config_parameter" {
  value = aws_ssm_parameter.config.name
}
