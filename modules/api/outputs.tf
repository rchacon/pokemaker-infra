output "api_endpoint" {
  description = "https://<id>.execute-api.<region>.amazonaws.com"
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "lambda_function_name" {
  value = aws_lambda_function.api.function_name
}

output "lambda_log_group" {
  value = aws_cloudwatch_log_group.lambda.name
}
