variable "project" {
  description = "Project name used for resource naming"
  type        = string
  default     = "forge"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "service_name" {
  description = "Name of the ECS service (e.g., api, worker, frontend, celery)"
  type        = string
}

variable "cluster_id" {
  description = "ID of the ECS cluster"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the ECS task execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the service will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the service"
  type        = list(string)
}

variable "container_image" {
  description = "Full ECR image URI with tag"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 3000
}

variable "cpu" {
  description = "Fargate CPU units"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate memory in MiB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of running tasks"
  type        = number
  default     = 1
}

variable "environment_variables" {
  description = "List of environment variables for the container"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "secrets" {
  description = "List of secrets from Secrets Manager or SSM Parameter Store"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "enable_load_balancer" {
  description = "Whether to attach this service to a load balancer"
  type        = bool
  default     = false
}

variable "alb_target_group_arn" {
  description = "ARN of an existing ALB target group (only used if enable_load_balancer is true)"
  type        = string
  default     = ""
}

variable "health_check_path" {
  description = "Health check path for the target group"
  type        = string
  default     = "/"
}

variable "log_group_name" {
  description = "CloudWatch log group name for container logs"
  type        = string
}

variable "allowed_security_group_ids" {
  description = "Additional security group IDs allowed to reach this service"
  type        = list(string)
  default     = []
}

variable "assign_public_ip" {
  description = "Whether to assign a public IP to the task ENI"
  type        = bool
  default     = false
}

variable "listener_arn" {
  description = "ARN of the ALB listener for creating routing rules"
  type        = string
  default     = ""
}

variable "host_header" {
  description = "Host header value for ALB listener rule routing"
  type        = string
  default     = ""
}

variable "ephemeral_storage_gib" {
  description = "Ephemeral storage size in GiB for the Fargate task (default 21, max 200)"
  type        = number
  default     = 21
}
