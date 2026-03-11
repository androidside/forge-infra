terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Random Password
# -----------------------------------------------------------------------------

resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|;:,.<>?"
}

# -----------------------------------------------------------------------------
# DB Subnet Group
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.environment}-db-subnet-group"
  subnet_ids = var.publicly_accessible ? var.public_subnet_ids : var.private_subnet_ids

  tags = {
    Name        = "${var.project}-${var.environment}-db-subnet-group"
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds-sg"
  description = "Security group for RDS MySQL instance"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project}-${var.environment}-rds-sg"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_security_group_rule" "rds_ingress" {
  count = length(var.allowed_security_group_ids)

  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_group_ids[count.index]
  security_group_id        = aws_security_group.rds.id
}

resource "aws_security_group_rule" "rds_ingress_cidr" {
  count = length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  description       = "Direct access from whitelisted IPs"
  security_group_id = aws_security_group.rds.id
}

resource "aws_security_group_rule" "rds_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
}

# -----------------------------------------------------------------------------
# RDS Instance
# -----------------------------------------------------------------------------

resource "aws_db_instance" "main" {
  identifier = "${var.project}-${var.environment}-mysql"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = false
  publicly_accessible = var.publicly_accessible

  backup_retention_period = 7
  skip_final_snapshot     = true

  tags = {
    Name        = "${var.project}-${var.environment}-mysql"
    Project     = var.project
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# Secrets Manager
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.project}/db-credentials"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    username = var.db_username
    password = random_password.db_password.result
    database = var.db_name
  })
}
