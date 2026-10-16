output "table_name" {
  value = aws_dynamodb_table.main.name
}

output "table_arn" {
  value = aws_dynamodb_table.main.arn
}

output "artwork_bucket_name" {
  value = aws_s3_bucket.artwork.bucket
}

output "artwork_bucket_arn" {
  value = aws_s3_bucket.artwork.arn
}
