# Forge Infrastructure

Terraform-managed AWS infrastructure for the Forge video processing platform. This repository provisions all cloud resources needed to run the NestJS API, React frontend, and Python Celery worker as containerized services on ECS Fargate.

## Architecture

```
                          ┌──────────────┐
                          │   Route 53   │
                          │  DNS Records │
                          └──────┬───────┘
                                 │
                          ┌──────▼───────┐
                          │     ALB      │
                          │  (public)    │
                          │  HTTPS :443  │
                          └──┬───────┬───┘
                             │       │
              ┌──────────────▼─┐   ┌─▼──────────────┐
              │  ECS Service   │   │  ECS Service    │
              │  forge-api     │   │  forge-frontend │
              │  (Fargate)     │   │  (Fargate)      │
              └───────┬────────┘   └─────────────────┘
                      │
          ┌───────────┼───────────┐
          │           │           │
   ┌──────▼──┐  ┌─────▼────┐  ┌──▼──────────┐
   │   RDS   │  │  Redis   │  │     S3      │
   │  MySQL  │  │ElastiCa. │  │   Content   │
   │  8.0    │  │  7.0     │  │   Bucket    │
   └─────────┘  └──────────┘  └─────────────┘
                      │
              ┌───────▼────────┐
              │  ECS Service   │
              │  forge-worker  │
              │  (Fargate)     │
              └────────────────┘
```

All data-plane resources (RDS, ElastiCache, ECS tasks) run in **private subnets**. Only the ALB sits in public subnets. A single NAT Gateway provides outbound internet access for private resources.

## Prerequisites

- **AWS CLI** v2 -- configured with credentials (`aws configure`)
- **Terraform** >= 1.5
- **Docker** -- for building and pushing container images
- **Domain** -- registered and hosted in Route 53

## Quick Start

```bash
# 1. Bootstrap Terraform remote state (one-time)
./scripts/setup-state.sh

# 2. Deploy shared infrastructure (VPC, RDS, Redis, ECR, S3, ECS cluster)
./scripts/deploy.sh dev shared plan
./scripts/deploy.sh dev shared apply

# 3. Build and push Docker images
./scripts/build-push.sh api
./scripts/build-push.sh frontend
./scripts/build-push.sh worker

# 4. Deploy ECS services (API, frontend, worker)
./scripts/deploy.sh dev services plan
./scripts/deploy.sh dev services apply
```

## Repository Structure

```
forge-infra/
├── README.md
├── environments/
│   └── dev/
│       ├── shared/         # VPC, RDS, Redis, ECR, S3, ECS cluster, ALB
│       └── services/       # ECS service definitions (api, frontend, worker)
├── modules/
│   ├── networking/         # VPC, subnets, NAT, route tables
│   ├── alb/                # Application Load Balancer, HTTPS, DNS
│   ├── ecr/                # Container registries
│   ├── ecs-cluster/        # ECS cluster, IAM roles, CloudWatch logs
│   ├── ecs-service/        # ECS task definitions, services, auto-scaling
│   ├── rds/                # MySQL 8.0, security group, Secrets Manager
│   ├── elasticache/        # Redis 7.0, security group, Secrets Manager
│   └── s3/                 # Content storage bucket
└── scripts/
    ├── setup-state.sh      # Bootstrap S3 + DynamoDB for Terraform state
    ├── build-push.sh       # Build Docker image and push to ECR
    └── deploy.sh           # Run terraform plan/apply/destroy
```

## Modules

| Module | Description |
|--------|-------------|
| **networking** | VPC with public/private subnets across 2 AZs, Internet Gateway, single NAT Gateway, route tables |
| **alb** | Application Load Balancer in public subnets, ACM certificate, HTTPS listener, Route 53 DNS records |
| **ecr** | ECR repositories for forge-api, forge-frontend, forge-worker with lifecycle policies (retain last 10 untagged) |
| **ecs-cluster** | ECS Fargate cluster with Container Insights, CloudWatch log group, execution role (ECR pull + Secrets Manager), task role (S3 access) |
| **ecs-service** | ECS task definitions and services for each container, target group registration, auto-scaling rules |
| **rds** | MySQL 8.0 on db.t4g.micro, gp3 storage, encrypted, private subnets only, auto-generated password stored in Secrets Manager |
| **elasticache** | Redis 7.0 on cache.t4g.micro, private subnets only, connection details stored in Secrets Manager |
| **s3** | S3 bucket for video/clip content storage, versioning, server-side encryption |

## Environments

Infrastructure is split into two Terraform workspaces per environment:

### shared

Provisions foundational resources that rarely change:
- VPC and networking
- RDS MySQL database
- ElastiCache Redis cluster
- ECR container registries
- S3 content bucket
- ECS cluster and IAM roles
- ALB and DNS

### services

Provisions application-layer resources that change on each deploy:
- ECS task definitions (image tags, environment variables)
- ECS services (desired count, health checks)
- Target group attachments
- Auto-scaling policies

This separation means you can redeploy services (update image tags) without risking changes to the database or networking layer.

## Scripts

### setup-state.sh

One-time bootstrap script. Creates the S3 bucket and DynamoDB table used for Terraform remote state and locking.

```bash
./scripts/setup-state.sh
```

### build-push.sh

Builds a Docker image for a service and pushes it to ECR. Tags with the git short SHA by default.

```bash
# Build and push the API image
./scripts/build-push.sh api

# Build with a specific tag
./scripts/build-push.sh frontend --tag v1.2.3

# Frontend requires VITE_API_URL and VITE_GOOGLE_CLIENT_ID env vars
VITE_API_URL=https://api.forge.example.com \
VITE_GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com \
  ./scripts/build-push.sh frontend
```

**Service mapping:**

| Service | Source Directory | ECR Repository |
|---------|-----------------|----------------|
| api | `forge-nestjs/` | forge-api |
| frontend | `forge-frontend/` | forge-frontend |
| worker | `content-forge/` | forge-worker |

### deploy.sh

Orchestrates Terraform operations against a specific environment and workspace.

```bash
# Preview changes
./scripts/deploy.sh dev shared plan

# Apply a previously generated plan
./scripts/deploy.sh dev shared apply

# Tear down (requires interactive confirmation)
./scripts/deploy.sh dev services destroy
```

## Secrets

All sensitive values are stored in AWS Secrets Manager and injected into ECS tasks at runtime.

| Secret Path | Contents | Source |
|-------------|----------|--------|
| `forge/db-credentials` | `host`, `port`, `username`, `password`, `database` | Auto-generated by RDS module |
| `forge/redis` | `host`, `port` | Auto-generated by ElastiCache module |
| `forge/jwt` | `secret`, `access_expiration`, `refresh_expiration` | Terraform (update values) |
| `forge/google-oauth` | `client_id`, `client_secret` | Terraform (update values) |
| `forge/social-encryption` | `key` (AES-256-GCM) | Terraform (update values) |
| `forge/social-twitter` | `client_id`, `client_secret`, `consumer_key`, `consumer_secret`, `access_token`, `access_token_secret` | Terraform (update values) |
| `forge/social-facebook` | `app_id`, `app_secret` | Terraform (update values) |
| `forge/social-tiktok` | `client_key`, `client_secret` | Terraform (update values) |
| `forge/social-linkedin` | `client_id`, `client_secret` | Terraform (update values) |
| `forge/openai` | `api_key` | Terraform (update values) |
| `forge/huggingface` | `token` | Terraform (update values) |

Secrets are created by Terraform with placeholder `CHANGE_ME` values. Update them via the AWS CLI before deploying services:

```bash
aws secretsmanager update-secret \
  --secret-id forge/jwt \
  --secret-string '{"secret":"your-jwt-secret","access_expiration":"15m","refresh_expiration":"7d"}'
```

## Cost Estimate

Estimated monthly cost for a minimal dev environment (us-east-1):

| Resource | Instance/Type | Monthly Cost |
|----------|--------------|-------------|
| NAT Gateway | Single AZ | ~$32 |
| ALB | 1 LB | ~$16 |
| RDS MySQL | db.t4g.micro | ~$12 |
| ElastiCache Redis | cache.t4g.micro | ~$12 |
| ECS Fargate (API) | 0.25 vCPU / 0.5 GB | ~$9 |
| ECS Fargate (Frontend) | 0.25 vCPU / 0.5 GB | ~$9 |
| ECS Fargate (Worker) | 0.5 vCPU / 1 GB | ~$18 |
| ECR | Storage | ~$1 |
| S3 | Storage + requests | ~$1 |
| CloudWatch | Logs | ~$2 |
| Secrets Manager | 4 secrets | ~$2 |
| **Total** | | **~$114/mo** |

Cost can be reduced by using a NAT Instance (t4g.nano ~$3/mo) instead of NAT Gateway, or by scheduling non-production environments to stop outside business hours.

## CI/CD

GitHub Actions workflows can automate the build-push-deploy cycle:

1. **On push to main** -- build all changed services, push to ECR, run `deploy.sh <env> services apply`
2. **On pull request** -- run `deploy.sh <env> services plan` and post the plan as a PR comment
3. **Manual dispatch** -- trigger a full deploy or destroy for any environment

Workflow files should be placed in `.github/workflows/` in this repository. The workflows use the same scripts documented above, with AWS credentials provided via GitHub OIDC federation or IAM access keys stored as repository secrets.
