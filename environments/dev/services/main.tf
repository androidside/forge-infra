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
# Read shared infrastructure state
# -----------------------------------------------------------------------------
data "terraform_remote_state" "shared" {
  backend = "s3"

  config = {
    bucket = "forge-terraform-state-263618685979"
    key    = "dev/shared/terraform.tfstate"
    region = var.aws_region
  }
}

# -----------------------------------------------------------------------------
# Local values from shared state
# -----------------------------------------------------------------------------
locals {
  shared = data.terraform_remote_state.shared.outputs

  # ECR image URIs
  api_image      = "${local.shared.ecr_repository_urls["forge-api"]}:${var.api_image_tag}"
  frontend_image = "${local.shared.ecr_repository_urls["forge-frontend"]}:${var.frontend_image_tag}"
  worker_image   = "${local.shared.ecr_repository_urls["forge-worker"]}:${var.worker_image_tag}"

  # Common env vars for NestJS services
  nestjs_env_vars = [
    { name = "NODE_ENV", value = "production" },
    { name = "DATABASE_HOST", value = local.shared.rds_endpoint },
    { name = "DATABASE_PORT", value = tostring(local.shared.rds_port) },
    { name = "DATABASE_NAME", value = "forge" },
    { name = "REDIS_HOST", value = local.shared.redis_endpoint },
    { name = "REDIS_PORT", value = tostring(local.shared.redis_port) },
    { name = "S3_BUCKET_NAME", value = local.shared.s3_bucket_name },
    { name = "MINIO_ENDPOINT", value = "s3.${var.aws_region}.amazonaws.com" },
    { name = "MINIO_SECURE", value = "true" },
    { name = "MINIO_ACCESS_KEY", value = "" },
    { name = "MINIO_SECRET_KEY", value = "" },
    { name = "API_BASE_URL", value = "https://api.${var.domain_name}" },
    { name = "FRONTEND_URL", value = "https://app.${var.domain_name}" },
    { name = "RUN_MIGRATIONS", value = "false" },
  ]

  # Secrets for NestJS services (from Secrets Manager)
  nestjs_secrets = [
    { name = "DATABASE_USER", valueFrom = "${local.shared.rds_secret_arn}:username::" },
    { name = "DATABASE_PASSWORD", valueFrom = "${local.shared.rds_secret_arn}:password::" },
    { name = "JWT_SECRET", valueFrom = "${local.shared.jwt_secret_arn}:secret::" },
    { name = "JWT_ACCESS_EXPIRATION", valueFrom = "${local.shared.jwt_secret_arn}:access_expiration::" },
    { name = "JWT_REFRESH_EXPIRATION", valueFrom = "${local.shared.jwt_secret_arn}:refresh_expiration::" },
    { name = "GOOGLE_CLIENT_ID", valueFrom = "${local.shared.google_oauth_secret_arn}:client_id::" },
    { name = "GOOGLE_CLIENT_SECRET", valueFrom = "${local.shared.google_oauth_secret_arn}:client_secret::" },
    { name = "SOCIAL_ENCRYPTION_KEY", valueFrom = "${local.shared.social_encryption_secret_arn}:key::" },
    { name = "TWITTER_CLIENT_ID", valueFrom = "${local.shared.twitter_secret_arn}:client_id::" },
    { name = "TWITTER_CLIENT_SECRET", valueFrom = "${local.shared.twitter_secret_arn}:client_secret::" },
    { name = "TWITTER_CONSUMER_KEY", valueFrom = "${local.shared.twitter_secret_arn}:consumer_key::" },
    { name = "TWITTER_CONSUMER_SECRET", valueFrom = "${local.shared.twitter_secret_arn}:consumer_secret::" },
    { name = "TWITTER_ACCESS_TOKEN", valueFrom = "${local.shared.twitter_secret_arn}:access_token::" },
    { name = "TWITTER_ACCESS_TOKEN_SECRET", valueFrom = "${local.shared.twitter_secret_arn}:access_token_secret::" },
    { name = "FACEBOOK_APP_ID", valueFrom = "${local.shared.facebook_secret_arn}:app_id::" },
    { name = "FACEBOOK_APP_SECRET", valueFrom = "${local.shared.facebook_secret_arn}:app_secret::" },
    { name = "TIKTOK_CLIENT_KEY", valueFrom = "${local.shared.tiktok_secret_arn}:client_key::" },
    { name = "TIKTOK_CLIENT_SECRET", valueFrom = "${local.shared.tiktok_secret_arn}:client_secret::" },
    { name = "LINKEDIN_CLIENT_ID", valueFrom = "${local.shared.linkedin_secret_arn}:client_id::" },
    { name = "LINKEDIN_CLIENT_SECRET", valueFrom = "${local.shared.linkedin_secret_arn}:client_secret::" },
  ]
}

# -----------------------------------------------------------------------------
# Frontend Service (nginx, port 80)
# -----------------------------------------------------------------------------
module "frontend" {
  source = "../../../modules/ecs-service"

  project            = var.project
  environment        = var.environment
  service_name       = "frontend"
  cluster_id         = local.shared.ecs_cluster_id
  execution_role_arn = local.shared.ecs_execution_role_arn
  task_role_arn      = local.shared.ecs_task_role_arn
  vpc_id             = local.shared.vpc_id
  private_subnet_ids = local.shared.private_subnet_ids
  container_image    = local.frontend_image
  container_port     = 8080
  cpu                = 256
  memory             = 512
  desired_count      = 1
  log_group_name     = local.shared.ecs_log_group_name

  enable_load_balancer = true
  listener_arn         = local.shared.alb_https_listener_arn
  host_header          = "app.${var.domain_name}"
  health_check_path    = "/health"

  allowed_security_group_ids = [local.shared.alb_security_group_id]

  environment_variables = []
  secrets               = []
}

# -----------------------------------------------------------------------------
# API Service (NestJS, port 3000)
# -----------------------------------------------------------------------------
module "api" {
  source = "../../../modules/ecs-service"

  project            = var.project
  environment        = var.environment
  service_name       = "api"
  cluster_id         = local.shared.ecs_cluster_id
  execution_role_arn = local.shared.ecs_execution_role_arn
  task_role_arn      = local.shared.ecs_task_role_arn
  vpc_id             = local.shared.vpc_id
  private_subnet_ids = local.shared.private_subnet_ids
  container_image    = local.api_image
  container_port     = 3000
  cpu                = 256
  memory             = 512
  desired_count      = 1
  log_group_name     = local.shared.ecs_log_group_name

  enable_load_balancer = true
  listener_arn         = local.shared.alb_https_listener_arn
  host_header          = "api.${var.domain_name}"
  health_check_path    = "/health"

  allowed_security_group_ids = [local.shared.alb_security_group_id]

  environment_variables = concat(local.nestjs_env_vars, [
    { name = "APP_TYPE", value = "api" },
    { name = "RUN_MIGRATIONS", value = "true" },
  ])

  secrets = local.nestjs_secrets
}

# -----------------------------------------------------------------------------
# Worker Service (NestJS BullMQ worker, no ALB)
# -----------------------------------------------------------------------------
module "worker" {
  source = "../../../modules/ecs-service"

  project            = var.project
  environment        = var.environment
  service_name       = "worker"
  cluster_id         = local.shared.ecs_cluster_id
  execution_role_arn = local.shared.ecs_execution_role_arn
  task_role_arn      = local.shared.ecs_task_role_arn
  vpc_id             = local.shared.vpc_id
  private_subnet_ids = local.shared.private_subnet_ids
  container_image    = local.api_image
  container_port     = 0
  cpu                = 256
  memory             = 512
  desired_count      = 1
  log_group_name     = local.shared.ecs_log_group_name

  enable_load_balancer = false

  environment_variables = concat(local.nestjs_env_vars, [
    { name = "APP_TYPE", value = "worker" },
  ])

  secrets = local.nestjs_secrets
}

# -----------------------------------------------------------------------------
# Celery Worker (content-forge, Python, no ALB)
# -----------------------------------------------------------------------------
module "celery" {
  source = "../../../modules/ecs-service"

  project            = var.project
  environment        = var.environment
  service_name       = "celery"
  cluster_id         = local.shared.ecs_cluster_id
  execution_role_arn = local.shared.ecs_execution_role_arn
  task_role_arn      = local.shared.ecs_task_role_arn
  vpc_id             = local.shared.vpc_id
  private_subnet_ids = local.shared.private_subnet_ids
  container_image    = local.worker_image
  container_port     = 0
  cpu                = 512
  memory             = 1024
  desired_count      = 1
  log_group_name     = local.shared.ecs_log_group_name

  enable_load_balancer = false

  environment_variables = [
    { name = "CELERY_BROKER_URL", value = "redis://${local.shared.redis_endpoint}:${local.shared.redis_port}/0" },
    { name = "CELERY_RESULT_BACKEND", value = "redis://${local.shared.redis_endpoint}:${local.shared.redis_port}/0" },
    { name = "S3_BUCKET_NAME", value = local.shared.s3_bucket_name },
    { name = "S3_ENDPOINT", value = "https://s3.${var.aws_region}.amazonaws.com" },
    { name = "S3_REGION", value = var.aws_region },
    { name = "REDIS_HOST", value = local.shared.redis_endpoint },
    { name = "REDIS_PORT", value = tostring(local.shared.redis_port) },
    { name = "REDIS_PUBSUB_PREFIX", value = "pipeline" },
    { name = "DIARIZATION_METHOD", value = "gemini" },
    { name = "GEMINI_MODEL", value = "gemini-3-flash-preview" },
    { name = "WHISPER_MODEL", value = "base" },
    { name = "WHISPER_DEVICE", value = "cpu" },
    { name = "WHISPER_COMPUTE_TYPE", value = "int8" },
    { name = "USE_GPU", value = "false" },
    { name = "ENABLE_FACE_TRACKING", value = "true" },
    { name = "FACE_DETECTION_DEVICE", value = "cpu" },
    { name = "OUTPUT_RESOLUTION", value = "1080x1920" },
    { name = "LOG_LEVEL", value = "INFO" },
    { name = "ENABLE_DEBUG_LOGS", value = "false" },
    { name = "MINIO_SECURE", value = "true" },
    { name = "MINIO_ENDPOINT", value = "s3.${var.aws_region}.amazonaws.com" },
    { name = "MINIO_ACCESS_KEY", value = "" },
    { name = "MINIO_SECRET_KEY", value = "" },
    { name = "DATABASE_HOST", value = local.shared.rds_endpoint },
    { name = "DATABASE_PORT", value = tostring(local.shared.rds_port) },
    { name = "DATABASE_NAME", value = "forge" },
  ]

  secrets = [
    { name = "OPENAI_API_KEY", valueFrom = "${local.shared.openai_secret_arn}:api_key::" },
    { name = "HF_TOKEN", valueFrom = "${local.shared.huggingface_secret_arn}:token::" },
    { name = "GOOGLE_AI_API_KEY", valueFrom = "${local.shared.google_ai_secret_arn}:api_key::" },
    { name = "DATABASE_USER", valueFrom = "${local.shared.rds_secret_arn}:username::" },
    { name = "DATABASE_PASSWORD", valueFrom = "${local.shared.rds_secret_arn}:password::" },
    { name = "YOUTUBE_COOKIES", valueFrom = local.shared.youtube_cookies_secret_arn },
  ]
}

# -----------------------------------------------------------------------------
# Security Group Rules: Allow ECS services to reach RDS and Redis
# -----------------------------------------------------------------------------
resource "aws_security_group_rule" "api_to_rds" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = module.api.security_group_id
  security_group_id        = local.shared.rds_security_group_id
}

resource "aws_security_group_rule" "worker_to_rds" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = module.worker.security_group_id
  security_group_id        = local.shared.rds_security_group_id
}

resource "aws_security_group_rule" "api_to_redis" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = module.api.security_group_id
  security_group_id        = local.shared.redis_security_group_id
}

resource "aws_security_group_rule" "worker_to_redis" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = module.worker.security_group_id
  security_group_id        = local.shared.redis_security_group_id
}

resource "aws_security_group_rule" "celery_to_rds" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = module.celery.security_group_id
  security_group_id        = local.shared.rds_security_group_id
}

resource "aws_security_group_rule" "celery_to_redis" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = module.celery.security_group_id
  security_group_id        = local.shared.redis_security_group_id
}
