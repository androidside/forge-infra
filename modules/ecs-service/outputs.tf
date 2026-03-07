output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.service.name
}

output "service_id" {
  description = "ID of the ECS service"
  value       = aws_ecs_service.service.id
}

output "task_definition_arn" {
  description = "ARN of the task definition"
  value       = aws_ecs_task_definition.service.arn
}

output "security_group_id" {
  description = "ID of the service security group"
  value       = aws_security_group.service.id
}

output "target_group_arn" {
  description = "ARN of the target group (empty string if no load balancer)"
  value       = var.enable_load_balancer ? aws_lb_target_group.service[0].arn : ""
}
