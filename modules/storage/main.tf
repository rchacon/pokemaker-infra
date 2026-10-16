# DynamoDB single table + private artwork bucket.

resource "aws_dynamodb_table" "main" {
  name                        = var.table_name
  billing_mode                = "PAY_PER_REQUEST" # on-demand: pay per request, nothing when idle
  hash_key                    = "PK"
  range_key                   = "SK"
  deletion_protection_enabled = var.deletion_protection

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  # Cleans up old quota and generation-request items. The API never relies on
  # TTL for correctness (quotas reset because each UTC day has its own item).
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  # Kids' cards are precious, and point-in-time recovery costs pennies at this size.
  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = var.tags
}

resource "aws_s3_bucket" "artwork" {
  bucket        = var.artwork_bucket_name
  force_destroy = false
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "artwork" {
  bucket = aws_s3_bucket.artwork.id
  rule {
    object_ownership = "BucketOwnerEnforced" # no ACLs
  }
}

resource "aws_s3_bucket_public_access_block" "artwork" {
  bucket                  = aws_s3_bucket.artwork.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artwork" {
  bucket = aws_s3_bucket.artwork.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artwork" {
  bucket = aws_s3_bucket.artwork.id
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# The browser loads artwork through short-lived presigned URLs and draws it into
# a canvas for PNG/PDF export, which requires CORS from the site's origin.
resource "aws_s3_bucket_cors_configuration" "artwork" {
  count  = length(var.cors_allowed_origins) > 0 ? 1 : 0
  bucket = aws_s3_bucket.artwork.id
  cors_rule {
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = var.cors_allowed_origins
    allowed_headers = ["*"]
    max_age_seconds = 3600
  }
}
