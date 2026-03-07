# Terraform Modules

## networking

VPC with public and private subnets across 2 availability zones.

**Inputs:**
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `project` | string | `"forge"` | Project name |
| `environment` | string | `"dev"` | Environment name |
| `vpc_cidr` | string | `"10.0.0.0/16"` | VPC CIDR block |
| `availability_zones` | list(string) | `["us-east-1a", "us-east-1b"]` | AZs |
| `public_subnet_cidrs` | list(string) | `["10.0.1.0/24", "10.0.2.0/24"]` | Public CIDRs |
| `private_subnet_cidrs` | list(string) | `["10.0.10.0/24", "10.0.11.0/24"]` | Private CIDRs |

**Outputs:** `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `nat_gateway_id`

**Resources:** VPC, 2 public subnets, 2 private subnets, IGW, NAT Gateway (single), EIP, route tables, associations.

---

## ecr

ECR container repositories with lifecycle policies.

**Inputs:**
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `project` | string | `"forge"` | Project name |
| `environment` | string | `"dev"` | Environment name |
| `repository_names` | list(string) | `["forge-api", "forge-frontend", "forge-worker"]` | Repo names |
| `image_retention_count` | number | `10` | Untagged images to keep |

**Outputs:** `repository_urls` (map), `repository_arns` (map)

**Note:** Repo names are used directly (no project/env prefix) since repos are typically shared across environments.

---

## ecs-cluster

ECS Fargate cluster with CloudWatch logging and IAM roles.

**Inputs:**
| Variable | Type | Default |
|----------|------|---------|
| `project` | string | `"forge"` |
| `environment` | string | `"dev"` |

**Outputs:** `cluster_id`, `cluster_name`, `log_group_name`, `execution_role_arn`, `task_role_arn`

**IAM Roles:**
- **Execution role** - Pulls images from ECR, writes CloudWatch logs, reads Secrets Manager (`forge/*`)
- **Task role** - S3 access for the content bucket (`forge-*`)

---

## ecs-service

Generic, reusable Fargate service module. Called 4 times with different configurations.

**Key Inputs:**
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `service_name` | string | required | `api`, `worker`, `frontend`, `celery` |
| `cluster_id` | string | required | ECS cluster ID |
| `container_image` | string | required | Full ECR URI with tag |
| `container_port` | number | `3000` | Set to `0` for workers (no port) |
| `cpu` | number | `256` | Fargate CPU units |
| `memory` | number | `512` | Fargate memory MiB |
| `environment_variables` | list(object) | `[]` | Env vars as `{name, value}` |
| `secrets` | list(object) | `[]` | Secrets as `{name, valueFrom}` |
| `enable_load_balancer` | bool | `false` | Attach to ALB |
| `listener_arn` | string | `""` | ALB HTTPS listener ARN |
| `host_header` | string | `""` | Host-based routing value |

**Outputs:** `service_name`, `service_id`, `task_definition_arn`, `security_group_id`, `target_group_arn`

**Conditional Resources:** Target group and listener rule are only created when `enable_load_balancer = true`.

---

## rds

MySQL 8.0 database with auto-generated credentials stored in Secrets Manager.

**Inputs:**
| Variable | Type | Default |
|----------|------|---------|
| `vpc_id` | string | required |
| `private_subnet_ids` | list(string) | required |
| `allowed_security_group_ids` | list(string) | required |
| `instance_class` | string | `"db.t4g.micro"` |
| `allocated_storage` | number | `20` |
| `db_name` | string | `"forge"` |
| `db_username` | string | `"forge_admin"` |

**Outputs:** `endpoint`, `port`, `database_name`, `security_group_id`, `secret_arn`

**Secret:** `forge/db-credentials` containing `{host, port, username, password, database}`

---

## elasticache

Redis 7.0 single-node cluster for Celery broker, BullMQ, and pub/sub.

**Inputs:**
| Variable | Type | Default |
|----------|------|---------|
| `vpc_id` | string | required |
| `private_subnet_ids` | list(string) | required |
| `allowed_security_group_ids` | list(string) | required |
| `node_type` | string | `"cache.t4g.micro"` |

**Outputs:** `endpoint`, `port`, `security_group_id`, `secret_arn`

**Secret:** `forge/redis` containing `{host, port}`

---

## s3

S3 bucket for video and clip content storage (replaces MinIO in production).

**Inputs:**
| Variable | Type | Default |
|----------|------|---------|
| `bucket_name` | string | `""` (auto: `{project}-{env}-content`) |
| `force_destroy` | bool | `true` |

**Outputs:** `bucket_name`, `bucket_arn`, `bucket_regional_domain_name`

**Features:** Versioning, AES256 encryption, CORS for presigned URLs, lifecycle (STANDARD_IA after 90 days for `runs/` prefix), public access blocked.

---

## alb

Application Load Balancer with ACM wildcard certificate and Route53 DNS.

**Inputs:**
| Variable | Type | Description |
|----------|------|-------------|
| `vpc_id` | string | VPC ID |
| `public_subnet_ids` | list(string) | Public subnets for ALB |
| `domain_name` | string | Root domain (e.g., `example.com`) |
| `route53_zone_id` | string | Route53 hosted zone ID |

**Outputs:** `alb_arn`, `alb_dns_name`, `alb_zone_id`, `https_listener_arn`, `security_group_id`, `app_domain`, `api_domain`

**Features:** Wildcard ACM cert (`*.domain`), DNS validation, HTTP→HTTPS redirect, default 404 response, A-record aliases for `app.` and `api.` subdomains.
