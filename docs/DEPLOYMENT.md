# Deployment Guide

## Prerequisites

1. **AWS CLI v2** configured with credentials (`aws configure`)
2. **Terraform** >= 1.5 installed
3. **Docker** installed and running
4. **Domain** registered and hosted in Route 53

## First-Time Setup

### 1. Bootstrap Terraform State

```bash
cd forge-infra
./scripts/setup-state.sh
```

This creates:
- S3 bucket `forge-terraform-state` (versioned, encrypted)
- DynamoDB table `forge-terraform-locks`

### 2. Configure Variables

```bash
cd environments/dev/shared
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your domain and Route53 zone ID
```

```bash
cd environments/dev/services
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your domain
```

### 3. Deploy Shared Infrastructure

```bash
./scripts/deploy.sh dev shared plan    # Review the plan
./scripts/deploy.sh dev shared apply   # Create VPC, RDS, Redis, S3, ALB, ECR, secrets
```

### 4. Update Secrets

After shared infrastructure is created, update placeholder secrets with real values:

```bash
# JWT
aws secretsmanager update-secret --secret-id forge/jwt \
  --secret-string '{"secret":"YOUR_JWT_SECRET","access_expiration":"15m","refresh_expiration":"7d"}'

# Google OAuth
aws secretsmanager update-secret --secret-id forge/google-oauth \
  --secret-string '{"client_id":"YOUR_CLIENT_ID","client_secret":"YOUR_CLIENT_SECRET"}'

# Social encryption key (generate: openssl rand -hex 32)
aws secretsmanager update-secret --secret-id forge/social-encryption \
  --secret-string '{"key":"YOUR_AES_256_KEY"}'

# Social platform OAuth (update each as needed)
aws secretsmanager update-secret --secret-id forge/social-twitter \
  --secret-string '{"client_id":"...","client_secret":"...","consumer_key":"...","consumer_secret":"...","access_token":"...","access_token_secret":"..."}'

# OpenAI (for content-forge)
aws secretsmanager update-secret --secret-id forge/openai \
  --secret-string '{"api_key":"YOUR_OPENAI_KEY"}'

# HuggingFace (for content-forge diarization)
aws secretsmanager update-secret --secret-id forge/huggingface \
  --secret-string '{"token":"YOUR_HF_TOKEN"}'
```

### 5. Build and Push Docker Images

```bash
# API (used by both api and worker services)
./scripts/build-push.sh api

# Frontend (requires build args)
VITE_API_URL=https://api.yourdomain.com \
VITE_GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com \
./scripts/build-push.sh frontend

# Celery worker
./scripts/build-push.sh worker
```

### 6. Deploy Services

```bash
./scripts/deploy.sh dev services plan
./scripts/deploy.sh dev services apply
```

### 7. Update OAuth Callback URLs

Update callback URLs for all OAuth integrations to use the production domain:

| Provider | Callback URL |
|----------|-------------|
| Google | `https://api.yourdomain.com/auth/google/callback` |
| Twitter | `https://api.yourdomain.com/social-media/callback/twitter` |
| Facebook | `https://api.yourdomain.com/social-media/callback/facebook` |
| TikTok | `https://api.yourdomain.com/social-media/callback/tiktok` |
| LinkedIn | `https://api.yourdomain.com/social-media/callback/linkedin` |

## Redeployment

### Update a Service Image

```bash
# Build new image
./scripts/build-push.sh api --tag v1.2.3

# Update services workspace with new tag
cd environments/dev/services
terraform apply -var="api_image_tag=v1.2.3"
```

### Force Redeploy (same image)

```bash
aws ecs update-service \
  --cluster forge-dev-cluster \
  --service forge-dev-api \
  --force-new-deployment
```

### Update Infrastructure

```bash
# Edit module or shared config, then:
./scripts/deploy.sh dev shared plan
./scripts/deploy.sh dev shared apply
```

## Teardown

Destroy in reverse order (services first, then shared):

```bash
./scripts/deploy.sh dev services destroy
./scripts/deploy.sh dev shared destroy
```

**Warning:** Destroying shared will delete the RDS database and all data. Take a snapshot first if needed.

## Troubleshooting

### ECS Task Won't Start

```bash
# Check task stopped reason
aws ecs describe-tasks --cluster forge-dev-cluster \
  --tasks $(aws ecs list-tasks --cluster forge-dev-cluster --service-name forge-dev-api --query 'taskArns[0]' --output text)

# Check CloudWatch logs
aws logs tail /ecs/forge-dev --follow --filter-pattern "ERROR"
```

### Database Connection Issues

```bash
# Verify security group rules allow ECS → RDS on port 3306
aws ec2 describe-security-groups --group-ids <rds-sg-id>

# Check RDS is running
aws rds describe-db-instances --db-instance-identifier forge-dev-mysql
```

### Service Not Reachable via ALB

```bash
# Check target group health
aws elbv2 describe-target-health --target-group-arn <tg-arn>

# Check listener rules
aws elbv2 describe-rules --listener-arn <https-listener-arn>
```
