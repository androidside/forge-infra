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

variable "repository_names" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default     = ["forge-api", "forge-frontend", "forge-worker"]
}

variable "image_retention_count" {
  description = "Number of untagged images to retain per repository"
  type        = number
  default     = 10
}
