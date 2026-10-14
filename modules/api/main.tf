# FastAPI on Lambda (via Mangum) behind an API Gateway HTTP API.
# No VPC, no NAT Gateway: Lambda reaches DynamoDB, S3, SSM and OpenAI over
# AWS's public endpoints, and costs nothing while idle.

data "aws_caller_identity" "current" {}

locals {
  ssm_arn_prefix = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter"
  ssm_parameter_arns = [
    "${local.ssm_arn_prefix}${var.openai_api_key_ssm_parameter}",
    "${local.ssm_arn_prefix}${var.pin_token_secret_ssm_parameter}",
  ]
}

# --- Lambda ---------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "api" {
  function_name    = var.name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  architectures    = ["arm64"] # Graviton: ~20% cheaper per GB-second
  handler          = "pokemaker.main.handler"
  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  memory_size      = var.memory_mb
  # API Gateway stops waiting after 30 s, but a slow image generation keeps
  # running to completion; the app polls for the result. See pokemaker-api README.
  timeout = 120
  # Caps parallel invocations (and so worst-case spend). null = account pool.
  reserved_concurrent_executions = var.reserved_concurrency

  logging_config {
    log_format = "Text" # the app already writes one JSON object per line
    log_group  = aws_cloudwatch_log_group.lambda.name
  }

  environment {
    variables = {
      APP_ENV                        = var.environment
      LOG_LEVEL                      = "INFO"
      FAMILY_ID                      = var.family_id
      TABLE_NAME                     = var.table_name
      ARTWORK_BUCKET                 = var.artwork_bucket_name
      ARTWORK_PROVIDER               = var.artwork_provider
      OPENAI_API_KEY_SSM_PARAMETER   = var.openai_api_key_ssm_parameter
      PIN_TOKEN_SECRET_SSM_PARAMETER = var.pin_token_secret_ssm_parameter
      OPENAI_IMAGE_MODEL             = var.openai_image_model
      OPENAI_IMAGE_QUALITY           = var.openai_image_quality
      OPENAI_IMAGE_SIZE              = var.openai_image_size
      OPENAI_TIMEOUT_SECONDS         = "90"
      DAILY_GENERATION_LIMIT         = tostring(var.daily_generation_limit)
      CORS_ALLOW_ORIGINS             = "[]" # same origin via CloudFront; no CORS needed
    }
  }

  tags = var.tags
}

# --- IAM (least privilege) ------------------------------------------------------

data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name}-lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid = "Table"
    # TransactWriteItems is authorized per item via PutItem/UpdateItem/ConditionCheckItem.
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:ConditionCheckItem",
      "dynamodb:DescribeTable",
    ]
    resources = [var.table_arn]
  }

  statement {
    sid       = "ArtworkObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.artwork_bucket_arn}/families/${var.family_id}/*"]
  }

  statement {
    # Listing is needed to delete every artwork version of a card, and
    # HeadBucket (health check) is authorized by ListBucket. The bucket holds
    # only this app's artwork, so no prefix condition.
    sid       = "ArtworkList"
    actions   = ["s3:ListBucket"]
    resources = [var.artwork_bucket_arn]
  }

  statement {
    sid       = "Secrets" # OpenAI key + PIN token signing secret
    actions   = ["ssm:GetParameter"]
    resources = local.ssm_parameter_arns
    # SecureString with the AWS-managed aws/ssm key: its key policy already lets
    # this account's principals decrypt via SSM, so no kms:Decrypt grant is needed.
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.name}-lambda"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

# --- API Gateway HTTP API -------------------------------------------------------

resource "aws_apigatewayv2_api" "http" {
  name          = var.name
  protocol_type = "HTTP"
  # No CORS block: browsers reach the API through CloudFront on the site's own origin.
  tags = var.tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

resource "aws_apigatewayv2_route" "api" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /api/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/aws/apigateway/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  # Throttling bounds abuse and cost. It is not authentication.
  default_route_settings {
    throttling_burst_limit = var.throttle_burst
    throttling_rate_limit  = var.throttle_rate
  }

  # Request metadata only — never bodies (they contain the kids' card text).
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId = "$context.requestId"
      time      = "$context.requestTime"
      method    = "$context.httpMethod"
      path      = "$context.path"
      status    = "$context.status"
      latencyMs = "$context.responseLatency"
      error     = "$context.integrationErrorMessage"
    })
  }

  tags = var.tags
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}
