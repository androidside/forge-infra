variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used for resource naming"
  type        = string
  default     = "forge"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "domain_name" {
  description = "Root domain name (e.g., example.com)"
  type        = string
}

# Networking
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# RDS
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "rds_publicly_accessible" {
  description = "Whether RDS should be publicly accessible (for direct DB access)"
  type        = bool
  default     = false
}

variable "rds_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to RDS directly (e.g. VPN IPs)"
  type        = list(string)
  default     = []
}

# ElastiCache
variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"
}
