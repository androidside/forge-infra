terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Data: VPC CIDR for internal ingress
# -----------------------------------------------------------------------------

data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "service" {
  name        = "${var.project}-${var.environment}-${var.service_name}-sg"
  description = "Security group for ${var.service_name} ECS service"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project}-${var.environment}-${var.service_name}-sg"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_security_group_rule" "service_ingress_from_sg" {
  count = length(var.allowed_security_group_ids)

  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_group_ids[count.index]
  security_group_id        = aws_security_group.service.id
}

resource "aws_security_group_rule" "service_ingress_from_vpc" {
  count = var.enable_load_balancer ? 1 : 0

  type              = "ingress"
  from_port         = var.container_port
  to_port           = var.container_port
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.selected.cidr_block]
  security_group_id = aws_security_group.service.id
}

resource "aws_security_group_rule" "service_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.service.id
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "service" {
  family                   = "${var.project}-${var.environment}-${var.service_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  dynamic "ephemeral_storage" {
    for_each = var.ephemeral_storage_gib > 21 ? [var.ephemeral_storage_gib] : []
    content {
      size_in_gib = ephemeral_storage.value
    }
  }

  container_definitions = jsonencode([
    {
      name      = var.service_name
      image     = var.container_image
      essential = true

      portMappings = var.container_port > 0 ? [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ] : []

      environment = var.environment_variables
      secrets     = var.secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = var.service_name
        }
      }
    }
  ])

  tags = {
    Name        = "${var.project}-${var.environment}-${var.service_name}"
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# ALB Target Group (only if load balancer is enabled)
# -----------------------------------------------------------------------------

resource "aws_lb_target_group" "service" {
  count = var.enable_load_balancer ? 1 : 0

  name_prefix = substr("${var.service_name}-", 0, 6)
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project}-${var.environment}-${var.service_name}-tg"
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# ALB Listener Rule (only if load balancer is enabled)
# -----------------------------------------------------------------------------

resource "aws_lb_listener_rule" "service" {
  count = var.enable_load_balancer ? 1 : 0

  listener_arn = var.listener_arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[0].arn
  }

  condition {
    host_header {
      values = [var.host_header]
    }
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "service" {
  name                   = "${var.project}-${var.environment}-${var.service_name}"
  cluster                = var.cluster_id
  task_definition        = aws_ecs_task_definition.service.arn
  desired_count          = var.desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = var.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = var.enable_load_balancer ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.service[0].arn
      container_name   = var.service_name
      container_port   = var.container_port
    }
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  force_new_deployment               = true

  tags = {
    Name        = "${var.project}-${var.environment}-${var.service_name}"
    Project     = var.project
    Environment = var.environment
  }
}
