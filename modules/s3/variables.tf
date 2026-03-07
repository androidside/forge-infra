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

variable "bucket_name" {
  description = "S3 bucket name. If empty, defaults to {project}-{environment}-content"
  type        = string
  default     = ""
}

variable "force_destroy" {
  description = "Allow bucket to be destroyed even when it contains objects (for dev)"
  type        = bool
  default     = true
}
