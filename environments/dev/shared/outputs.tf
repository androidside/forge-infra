# Networking
output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.networking.private_subnet_ids
}

# ECR
output "ecr_repository_urls" {
  description = "Map of ECR repository names to URLs"
  value       = module.ecr.repository_urls
}

# ECS Cluster
output "ecs_cluster_id" {
  description = "ECS cluster ID"
  value       = module.ecs_cluster.cluster_id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = module.ecs_cluster.execution_role_arn
}

output "ecs_task_role_arn" {
  description = "ECS task role ARN"
  value       = module.ecs_cluster.task_role_arn
}

output "ecs_log_group_name" {
  description = "CloudWatch log group name"
  value       = module.ecs_cluster.log_group_name
}

# RDS
output "rds_endpoint" {
  description = "RDS endpoint address"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS port"
  value       = module.rds.port
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN for DB credentials"
  value       = module.rds.secret_arn
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = module.rds.security_group_id
}

# ElastiCache
output "redis_endpoint" {
  description = "Redis endpoint address"
  value       = module.elasticache.endpoint
}

output "redis_port" {
  description = "Redis port"
  value       = module.elasticache.port
}

output "redis_secret_arn" {
  description = "Secrets Manager ARN for Redis"
  value       = module.elasticache.secret_arn
}

output "redis_security_group_id" {
  description = "Redis security group ID"
  value       = module.elasticache.security_group_id
}

# S3
output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = module.s3.bucket_name
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = module.s3.bucket_arn
}

# ALB
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "alb_https_listener_arn" {
  description = "ALB HTTPS listener ARN"
  value       = module.alb.https_listener_arn
}

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = module.alb.security_group_id
}

output "app_domain" {
  description = "Frontend app domain"
  value       = module.alb.app_domain
}

output "cert_validation_records" {
  description = "CNAME records to add to Namecheap for SSL certificate validation"
  value       = module.alb.cert_validation_records
}

output "api_domain" {
  description = "API domain"
  value       = module.alb.api_domain
}

# Secrets
output "jwt_secret_arn" {
  description = "JWT secret ARN"
  value       = aws_secretsmanager_secret.jwt.arn
}

output "google_oauth_secret_arn" {
  description = "Google OAuth secret ARN"
  value       = aws_secretsmanager_secret.google_oauth.arn
}

output "social_encryption_secret_arn" {
  description = "Social encryption key secret ARN"
  value       = aws_secretsmanager_secret.social_encryption.arn
}

output "twitter_secret_arn" {
  description = "Twitter OAuth secret ARN"
  value       = aws_secretsmanager_secret.twitter.arn
}

output "facebook_secret_arn" {
  description = "Facebook OAuth secret ARN"
  value       = aws_secretsmanager_secret.facebook.arn
}

output "tiktok_secret_arn" {
  description = "TikTok OAuth secret ARN"
  value       = aws_secretsmanager_secret.tiktok.arn
}

output "linkedin_secret_arn" {
  description = "LinkedIn OAuth secret ARN"
  value       = aws_secretsmanager_secret.linkedin.arn
}

output "openai_secret_arn" {
  description = "OpenAI secret ARN"
  value       = aws_secretsmanager_secret.openai.arn
}

output "huggingface_secret_arn" {
  description = "HuggingFace secret ARN"
  value       = aws_secretsmanager_secret.huggingface.arn
}

output "google_ai_secret_arn" {
  description = "Google AI (Gemini) secret ARN"
  value       = aws_secretsmanager_secret.google_ai.arn
}

output "youtube_api_key_secret_arn" {
  description = "YouTube API key secret ARN"
  value       = aws_secretsmanager_secret.youtube_api_key.arn
}

output "youtube_cookies_secret_arn" {
  description = "YouTube cookies secret ARN"
  value       = aws_secretsmanager_secret.youtube_cookies.arn
}
