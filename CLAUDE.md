# Forge Infrastructure

Terraform IaC for deploying the Forge platform to AWS (ECS Fargate, RDS, ElastiCache, S3, ALB).

## Tech Stack

- **Terraform** >= 1.5 with AWS provider ~> 5.0
- **AWS** - ECS Fargate, RDS MySQL 8.0, ElastiCache Redis 7.0, S3, ALB, ACM, Route53
- **Remote State** - S3 bucket (`forge-terraform-state`) + DynamoDB (`forge-terraform-locks`)

## Directory Layout

```
forge-infra/
├── modules/           # Reusable Terraform modules (8 modules)
│   ├── networking/    # VPC, subnets, NAT, IGW, route tables
│   ├── ecr/           # ECR repositories with lifecycle policies
│   ├── ecs-cluster/   # ECS cluster, CloudWatch logs, IAM roles
│   ├── ecs-service/   # Generic Fargate service (reused 4x)
│   ├── rds/           # MySQL instance + Secrets Manager
│   ├── elasticache/   # Redis cluster + Secrets Manager
│   ├── s3/            # Content bucket (replaces MinIO)
│   └── alb/           # ALB, ACM cert, HTTPS, Route53 DNS
├── environments/      # Environment-specific compositions
│   └── dev/
│       ├── shared/    # VPC, RDS, Redis, S3, ECR, ECS cluster, ALB, secrets
│       └── services/  # 4 ECS services (api, worker, frontend, celery)
├── scripts/           # Deployment automation
│   ├── setup-state.sh # One-time: create S3 + DynamoDB for TF state
│   ├── build-push.sh  # Build Docker image & push to ECR
│   └── deploy.sh      # Terraform init/plan/apply orchestrator
└── .github/workflows/ # CI/CD pipelines
```

## Two-Workspace Architecture

Infrastructure is split into two independent Terraform workspaces:

- **shared** - Resources that rarely change (VPC, RDS, Redis, S3, ALB, ECR, secrets). Apply infrequently.
- **services** - ECS task definitions and services that change on every deploy (image tags, env vars). Apply on each deployment.

The `services` workspace reads outputs from `shared` via `terraform_remote_state`.

## Key Conventions

- Resource naming: `${var.project}-${var.environment}-<resource>` (e.g., `forge-dev-vpc`)
- All resources tagged with `Project`, `Environment`, `ManagedBy`
- Modules declare `required_providers` but NOT the `provider` block (inherited from root)
- Secrets created with `CHANGE_ME` placeholders - update via AWS CLI before first deploy
- ECR repos are named without env prefix (shared across environments): `forge-api`, `forge-frontend`, `forge-worker`

## Related Repos

| Repo | Role |
|------|------|
| `forge-nestjs` | NestJS API + BullMQ worker (APP_TYPE=api\|worker) |
| `forge-frontend` | React SPA served via nginx |
| `content-forge` | Python Celery worker for video processing |

## Common Tasks

```bash
# Deploy infrastructure
./scripts/deploy.sh dev shared plan
./scripts/deploy.sh dev shared apply

# Build and push a service image
./scripts/build-push.sh api
./scripts/build-push.sh frontend
./scripts/build-push.sh worker

# Deploy services (after pushing images)
./scripts/deploy.sh dev services plan
./scripts/deploy.sh dev services apply

# Update a secret
aws secretsmanager update-secret --secret-id forge/jwt --secret-string '{"secret":"...","access_expiration":"15m","refresh_expiration":"7d"}'
```

## Important Files

- `environments/dev/shared/main.tf` - Main composition: all modules + secrets
- `environments/dev/services/main.tf` - 4 ECS services with env vars and secret injection
- `modules/ecs-service/main.tf` - Generic Fargate service (task def, SG, target group, listener rule)
- `scripts/build-push.sh` - Maps service names to source dirs and ECR repos
