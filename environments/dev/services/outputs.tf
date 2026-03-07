# Service details
output "frontend_service_name" {
  description = "Frontend ECS service name"
  value       = module.frontend.service_name
}

output "api_service_name" {
  description = "API ECS service name"
  value       = module.api.service_name
}

output "worker_service_name" {
  description = "Worker ECS service name"
  value       = module.worker.service_name
}

output "celery_service_name" {
  description = "Celery ECS service name"
  value       = module.celery.service_name
}

output "api_security_group_id" {
  description = "API service security group ID"
  value       = module.api.security_group_id
}

output "worker_security_group_id" {
  description = "Worker service security group ID"
  value       = module.worker.security_group_id
}

output "celery_security_group_id" {
  description = "Celery service security group ID"
  value       = module.celery.security_group_id
}
