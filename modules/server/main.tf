# The API server: one small EC2 instance running the pokemaker-api Docker image
# behind CloudFront. No SSH (port 22 is closed; shell access is SSM Session
# Manager), no load balancer, no NAT Gateway.

data "aws_caller_identity" "current" {}

locals {
  ssm_arn = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter"
  # Parameters the server reads: secrets created outside Terraform, plus the
  # app config and origin secret managed below.
  readable_parameters = [
    var.openai_api_key_ssm_parameter,
    var.pin_token_secret_ssm_parameter,
    var.cloudflare_dns_token_ssm_parameter,
    aws_ssm_parameter.config.name,
    aws_ssm_parameter.origin_secret.name,
    local.image_parameter,
  ]
  # Written by the deploy command: the image currently running, so a replaced
  # instance comes back up on the same version.
  image_parameter = "/pokemaker/${var.environment}/api-image"
}

# --- Placement: the default VPC, in a zone that offers the instance type --------

data "aws_vpc" "default" {
  default = true
}

data "aws_ec2_instance_type_offerings" "zones" {
  location_type = "availability-zone"
  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
  filter {
    name   = "availability-zone"
    values = data.aws_ec2_instance_type_offerings.zones.locations
  }
}

# Canonical publishes the current Ubuntu AMI ID as a public SSM parameter.
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
}

# --- Network: only CloudFront can reach the server -------------------------------

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "server" {
  name        = "${var.name}-server"
  description = "HTTPS from CloudFront only; all outbound (DynamoDB, S3, OpenAI, GHCR, updates)"
  vpc_id      = data.aws_vpc.default.id
  tags        = var.tags
}

# These address ranges are shared by every CloudFront distribution, which is why
# the app also checks a secret header that only *our* distribution sends.
resource "aws_vpc_security_group_ingress_rule" "https_from_cloudfront" {
  security_group_id = aws_security_group.server.id
  description       = "HTTPS from CloudFront"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.server.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv6" {
  security_group_id = aws_security_group.server.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

# --- Identity: an instance role instead of access keys --------------------------

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "server" {
  name               = "${var.name}-server"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
  tags               = var.tags
}

# Shell access and `aws ssm send-command` deploys, with no SSH.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "server" {
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
    # HeadBucket (health check) is authorized by ListBucket.
    sid       = "ArtworkList"
    actions   = ["s3:ListBucket"]
    resources = [var.artwork_bucket_arn]
  }

  statement {
    # SecureStrings use the AWS-managed aws/ssm key, whose key policy already
    # lets this account's principals decrypt through SSM.
    sid       = "ReadParameters"
    actions   = ["ssm:GetParameter"]
    resources = [for name in local.readable_parameters : "${local.ssm_arn}${name}"]
  }

  statement {
    sid       = "RecordDeployedImage"
    actions   = ["ssm:PutParameter"]
    resources = ["${local.ssm_arn}${local.image_parameter}"]
  }

  statement {
    # Docker's awslogs driver ships the container's stdout here.
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.api.arn}:*"]
  }
}

resource "aws_iam_role_policy" "server" {
  name   = "${var.name}-server"
  role   = aws_iam_role.server.id
  policy = data.aws_iam_policy_document.server.json
}

resource "aws_iam_instance_profile" "server" {
  name = "${var.name}-server"
  role = aws_iam_role.server.name
  tags = var.tags
}

# --- Configuration ----------------------------------------------------------------

resource "aws_cloudwatch_log_group" "api" {
  name              = "/pokemaker/${var.environment}/api"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# CloudFront sends this header with every request it forwards; the app refuses
# requests without it. It is generated here because CloudFront's configuration
# needs the value (so it is in Terraform state; it only proves "came through our
# distribution" and grants nothing else).
resource "random_password" "origin_secret" {
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "origin_secret" {
  name  = "/pokemaker/${var.environment}/origin-verify-secret"
  type  = "SecureString"
  value = random_password.origin_secret.result
  tags  = var.tags
}

# The app's settings, as an env file. Changing one is `terraform apply` followed
# by a redeploy (which re-reads this), not a new instance. Secrets are not here:
# only the names of the parameters that hold them.
resource "aws_ssm_parameter" "config" {
  name = "/pokemaker/${var.environment}/api-config"
  type = "String"
  value = join("\n", [for key, value in {
    APP_ENV                            = var.environment
    LOG_LEVEL                          = "INFO"
    FAMILY_ID                          = var.family_id
    AWS_REGION                         = var.aws_region
    TABLE_NAME                         = var.table_name
    ARTWORK_BUCKET                     = var.artwork_bucket_name
    ARTWORK_PROVIDER                   = var.artwork_provider
    OPENAI_API_KEY_SSM_PARAMETER       = var.openai_api_key_ssm_parameter
    OPENAI_IMAGE_MODEL                 = var.openai_image_model
    OPENAI_IMAGE_QUALITY               = var.openai_image_quality
    OPENAI_IMAGE_SIZE                  = "1536x1024"
    OPENAI_TIMEOUT_SECONDS             = "90"
    DAILY_GENERATION_LIMIT             = tostring(var.daily_generation_limit)
    PIN_TOKEN_SECRET_SSM_PARAMETER     = var.pin_token_secret_ssm_parameter
    ORIGIN_VERIFY_SECRET_SSM_PARAMETER = aws_ssm_parameter.origin_secret.name
    RATE_LIMIT_PER_MINUTE              = tostring(var.rate_limit_per_minute)
    TRUST_FORWARDED_FOR                = "true" # only CloudFront can connect
    CORS_ALLOW_ORIGINS                 = "[]"   # same origin via CloudFront
  } : "${key}=${value}"])
  tags = var.tags
}

# --- The instance -----------------------------------------------------------------

resource "aws_instance" "server" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = var.instance_type
  subnet_id              = sort(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids = [aws_security_group.server.id]
  iam_instance_profile   = aws_iam_instance_profile.server.name

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region                     = var.aws_region
    api_hostname               = var.api_hostname
    acme_email                 = var.acme_email == null ? "" : var.acme_email
    cloudflare_token_param     = var.cloudflare_dns_token_ssm_parameter
    config_param               = aws_ssm_parameter.config.name
    origin_secret_param        = aws_ssm_parameter.origin_secret.name
    image_param                = local.image_parameter
    log_group                  = aws_cloudwatch_log_group.api.name
    unattended_reboot_utc_hhmm = var.unattended_reboot_utc
  })
  # The bootstrap script only runs on first boot, so changing it means a fresh
  # instance. That's cheap: the server holds no data (DynamoDB and S3 do), and
  # the new instance redeploys the last image on its own.
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required" # IMDSv2 only
    # 2 hops: the container reaches the instance role through Docker's bridge.
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
  }

  tags = merge(var.tags, { Name = "${var.name}-api" })

  lifecycle {
    # New Ubuntu AMIs appear often; don't replace a running server for them.
    # Security updates are applied in place by unattended-upgrades.
    ignore_changes = [ami]
  }
}

# A stable address for the DNS record CloudFront connects to.
resource "aws_eip" "server" {
  domain   = "vpc"
  instance = aws_instance.server.id
  tags     = merge(var.tags, { Name = "${var.name}-api" })
}
