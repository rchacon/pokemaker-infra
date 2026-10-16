output "certificate_arn" {
  description = "ARN of the *validated* certificate (waits for issuance)."
  value       = aws_acm_certificate_validation.app.certificate_arn
}

output "hostname" {
  value = var.hostname
}
