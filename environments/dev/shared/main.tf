terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
module "networking" {
  source = "../../../modules/networking"

  project            = var.project
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

# -----------------------------------------------------------------------------
# ECR Repositories
# -----------------------------------------------------------------------------
module "ecr" {
  source = "../../../modules/ecr"

  project          = var.project
  environment      = var.environment
  repository_names = ["forge-api", "forge-frontend", "forge-worker"]
}

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------
module "ecs_cluster" {
  source = "../../../modules/ecs-cluster"

  project     = var.project
  environment = var.environment
}

# -----------------------------------------------------------------------------
# RDS MySQL
# -----------------------------------------------------------------------------
module "rds" {
  source = "../../../modules/rds"

  project                    = var.project
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  public_subnet_ids          = module.networking.public_subnet_ids
  allowed_security_group_ids = [] # Will be populated by ECS service SGs
  instance_class             = var.db_instance_class
  allocated_storage          = var.db_allocated_storage
  publicly_accessible        = var.rds_publicly_accessible
  allowed_cidr_blocks        = var.rds_allowed_cidr_blocks
}

# -----------------------------------------------------------------------------
# ElastiCache Redis
# -----------------------------------------------------------------------------
module "elasticache" {
  source = "../../../modules/elasticache"

  project                    = var.project
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  allowed_security_group_ids = [] # Will be populated by ECS service SGs
  node_type                  = var.redis_node_type
}

# -----------------------------------------------------------------------------
# S3 Bucket (replaces MinIO)
# -----------------------------------------------------------------------------
module "s3" {
  source = "../../../modules/s3"

  project     = var.project
  environment = var.environment
}

# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------
module "alb" {
  source = "../../../modules/alb"

  project           = var.project
  environment       = var.environment
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  domain_name       = var.domain_name
}

# -----------------------------------------------------------------------------
# Secrets Manager - Application Secrets
# These are created with placeholder values. Update them manually or via CLI.
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "jwt" {
  name = "forge/jwt"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id = aws_secretsmanager_secret.jwt.id
  secret_string = jsonencode({
    secret             = "CHANGE_ME"
    access_expiration  = "15m"
    refresh_expiration = "7d"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "google_oauth" {
  name = "forge/google-oauth"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "google_oauth" {
  secret_id = aws_secretsmanager_secret.google_oauth.id
  secret_string = jsonencode({
    client_id     = "CHANGE_ME"
    client_secret = "CHANGE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "social_encryption" {
  name = "forge/social-encryption"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "social_encryption" {
  secret_id = aws_secretsmanager_secret.social_encryption.id
  secret_string = jsonencode({
    key = "CHANGE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "twitter" {
  name = "forge/social-twitter"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "twitter" {
  secret_id = aws_secretsmanager_secret.twitter.id
  secret_string = jsonencode({
    client_id            = "CHANGE_ME"
    client_secret        = "CHANGE_ME"
    consumer_key         = "CHANGE_ME"
    consumer_secret      = "CHANGE_ME"
    access_token         = "CHANGE_ME"
    access_token_secret  = "CHANGE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "facebook" {
  name = "forge/social-facebook"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "facebook" {
  secret_id = aws_secretsmanager_secret.facebook.id
  secret_string = jsonencode({
    app_id     = "CHANGE_ME"
    app_secret = "CHANGE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "tiktok" {
  name = "forge/social-tiktok"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "tiktok" {
  secret_id = aws_secretsmanager_secret.tiktok.id
  secret_string = jsonencode({
    client_key    = "CHANGE_ME"
    client_secret = "CHANGE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "linkedin" {
  name = "forge/social-linkedin"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "linkedin" {
  secret_id = aws_secretsmanager_secret.linkedin.id
  secret_string = jsonencode({
    client_id     = "CHANGE_ME"
    client_secret = "CHANGE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "openai" {
  name = "forge/openai"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "openai" {
  secret_id = aws_secretsmanager_secret.openai.id
  secret_string = jsonencode({
    api_key = "CHANGE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "huggingface" {
  name = "forge/huggingface"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "huggingface" {
  secret_id = aws_secretsmanager_secret.huggingface.id
  secret_string = jsonencode({
    token = "CHANGE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "google_ai" {
  name = "forge/google-ai"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "google_ai" {
  secret_id = aws_secretsmanager_secret.google_ai.id
  secret_string = jsonencode({
    api_key = "CHANGE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "anthropic" {
  name = "forge/anthropic"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "anthropic" {
  secret_id = aws_secretsmanager_secret.anthropic.id
  secret_string = jsonencode({
    api_key = "CHANGE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# -----------------------------------------------------------------------------
# YouTube API Key (for YouTube Data API v3)
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "youtube_api_key" {
  name = "forge/youtube-api-key"

  tags = {
    Project     = var.project
    Environment = var.environment
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_secretsmanager_secret_version" "youtube_api_key" {
  secret_id     = aws_secretsmanager_secret.youtube_api_key.id
  secret_string = jsonencode({ apiKey = "CHANGE_ME" })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# YouTube Cookies (for yt-dlp bot detection bypass)
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "youtube_cookies" {
  name = "forge/youtube-cookies"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "youtube_cookies" {
  secret_id     = aws_secretsmanager_secret.youtube_cookies.id
  secret_string = "CHANGE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}
