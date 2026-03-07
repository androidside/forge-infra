# AWS Setup Guide

Complete step-by-step guide from a fresh AWS account to a running Forge deployment.

---

## Part 1: AWS Console Setup

### Step 1: Create an IAM User for Terraform

You need an IAM user with programmatic access to run Terraform from your terminal.

1. Go to **IAM** → **Users** → **Create user**
2. User name: `forge-terraform`
3. Click **Next**
4. Select **Attach policies directly**
5. Attach these managed policies:
   - `AdministratorAccess` (for initial setup; you can scope down later)
6. Click **Next** → **Create user**
7. Click on the user → **Security credentials** tab → **Create access key**
8. Select **Command Line Interface (CLI)**
9. Check the acknowledgment → **Next** → **Create access key**
10. **Save the Access Key ID and Secret Access Key** - you won't see them again

### Step 2: Install & Configure AWS CLI

On your machine (WSL/Linux):

```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure with your IAM user credentials
aws configure
```

It will prompt you:

```
AWS Access Key ID:     <paste from Step 1>
AWS Secret Access Key: <paste from Step 1>
Default region name:   us-east-1
Default output format: json
```

Verify it works:

```bash
aws sts get-caller-identity
```

You should see your account ID and user ARN.

### Step 3: Register or Transfer Your Domain to Route 53

**Option A: Buy a new domain in Route 53**

1. Go to **Route 53** → **Registered domains** → **Register domains**
2. Search for your domain → **Select** → **Proceed to checkout**
3. Fill in contact details → **Submit**
4. Route 53 automatically creates a **Hosted Zone** for the domain

**Option B: Use an existing domain (registered elsewhere)**

1. Go to **Route 53** → **Hosted zones** → **Create hosted zone**
2. Domain name: `yourdomain.com` → **Create hosted zone**
3. Note the 4 **NS (Name Server) records** shown
4. Go to your domain registrar (GoDaddy, Namecheap, etc.)
5. Update the domain's nameservers to the 4 Route 53 NS values
6. Wait for DNS propagation (can take up to 48 hours, usually ~1 hour)

### Step 4: Get Your Route 53 Zone ID

1. Go to **Route 53** → **Hosted zones**
2. Click on your domain
3. Copy the **Hosted zone ID** (looks like `Z0123456789ABCDEFGHIJ`)
4. You'll need this for the Terraform variables

### Step 5: Install Terraform

```bash
# Add HashiCorp GPG key and repo
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Verify
terraform version
```

### Step 6: Install Docker

```bash
# If not already installed in WSL
sudo apt update
sudo apt install docker.io
sudo usermod -aG docker $USER
# Log out and back in for group to take effect

# Verify
docker --version
```

---

## Part 2: Deploy Infrastructure (Terminal)

### Step 7: Bootstrap Terraform State

```bash
cd ~/git_wsl/forge-nestjs/forge-infra
./scripts/setup-state.sh
```

This creates an S3 bucket and DynamoDB table for Terraform to store its state. Run once, never again.

**Verify in AWS Console:** Go to **S3** → you should see `forge-terraform-state` bucket.

### Step 8: Configure Terraform Variables

```bash
# Shared infrastructure variables
cd ~/git_wsl/forge-nestjs/forge-infra/environments/dev/shared
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region      = "us-east-1"
project         = "forge"
environment     = "dev"
domain_name     = "yourdomain.com"          # <-- YOUR DOMAIN
route53_zone_id = "Z0123456789ABCDEFGHIJ"   # <-- FROM STEP 4
```

```bash
# Services variables
cd ~/git_wsl/forge-nestjs/forge-infra/environments/dev/services
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region  = "us-east-1"
project     = "forge"
environment = "dev"
domain_name = "yourdomain.com"    # <-- SAME DOMAIN
```

### Step 9: Deploy Shared Infrastructure

```bash
cd ~/git_wsl/forge-nestjs/forge-infra

# Preview what will be created (~30 resources)
./scripts/deploy.sh dev shared plan

# Review the plan output, then apply
./scripts/deploy.sh dev shared apply
```

This takes ~10-15 minutes. It creates:
- VPC with subnets, NAT Gateway
- RDS MySQL database
- ElastiCache Redis cluster
- S3 content bucket
- ECR container registries
- ECS cluster with IAM roles
- ALB with HTTPS certificate
- Route53 DNS records (app.yourdomain.com, api.yourdomain.com)
- Secrets Manager secrets (with placeholder values)

**Verify in AWS Console:**
- **VPC** → you should see `forge-dev-vpc`
- **RDS** → you should see `forge-dev-mysql` (creating/available)
- **ElastiCache** → you should see `forge-dev-redis`
- **S3** → you should see `forge-dev-content`
- **ECR** → you should see `forge-api`, `forge-frontend`, `forge-worker`
- **ECS** → you should see `forge-dev-cluster`
- **EC2 → Load Balancers** → you should see `forge-dev-alb`
- **Certificate Manager** → you should see `*.yourdomain.com` (status: Issued)
- **Secrets Manager** → you should see 11 secrets starting with `forge/`

### Step 10: Update Secrets with Real Values

Generate a JWT secret and encryption key:

```bash
# Generate random values
echo "JWT Secret:        $(openssl rand -hex 32)"
echo "Encryption Key:    $(openssl rand -hex 32)"
```

Now update each secret (replace the placeholder values):

```bash
# JWT configuration
aws secretsmanager update-secret --secret-id forge/jwt \
  --secret-string '{"secret":"PASTE_JWT_SECRET_HERE","access_expiration":"15m","refresh_expiration":"7d"}'

# Google OAuth (from Google Cloud Console → APIs & Services → Credentials)
aws secretsmanager update-secret --secret-id forge/google-oauth \
  --secret-string '{"client_id":"YOUR_GOOGLE_CLIENT_ID","client_secret":"YOUR_GOOGLE_CLIENT_SECRET"}'

# Social media encryption key
aws secretsmanager update-secret --secret-id forge/social-encryption \
  --secret-string '{"key":"PASTE_ENCRYPTION_KEY_HERE"}'

# OpenAI API key (for content-forge video analysis)
aws secretsmanager update-secret --secret-id forge/openai \
  --secret-string '{"api_key":"sk-..."}'

# HuggingFace token (for speaker diarization)
aws secretsmanager update-secret --secret-id forge/huggingface \
  --secret-string '{"token":"hf_..."}'
```

Social platform secrets - update only the ones you use:

```bash
# Twitter/X
aws secretsmanager update-secret --secret-id forge/social-twitter \
  --secret-string '{"client_id":"...","client_secret":"...","consumer_key":"...","consumer_secret":"...","access_token":"...","access_token_secret":"..."}'

# Facebook/Instagram
aws secretsmanager update-secret --secret-id forge/social-facebook \
  --secret-string '{"app_id":"...","app_secret":"..."}'

# TikTok
aws secretsmanager update-secret --secret-id forge/social-tiktok \
  --secret-string '{"client_key":"...","client_secret":"..."}'

# LinkedIn
aws secretsmanager update-secret --secret-id forge/social-linkedin \
  --secret-string '{"client_id":"...","client_secret":"..."}'
```

### Step 11: Build and Push Docker Images

```bash
cd ~/git_wsl/forge-nestjs/forge-infra

# Build and push the NestJS API image
./scripts/build-push.sh api

# Build and push the frontend (with your actual domain)
VITE_API_URL=https://api.yourdomain.com \
VITE_GOOGLE_CLIENT_ID=your-google-client-id.apps.googleusercontent.com \
./scripts/build-push.sh frontend

# Build and push the Celery worker
./scripts/build-push.sh worker
```

**Verify in AWS Console:** Go to **ECR** → click each repository → you should see images tagged with a git SHA and `latest`.

### Step 12: Deploy Services

```bash
cd ~/git_wsl/forge-nestjs/forge-infra

# Preview what will be created (4 ECS services + security group rules)
./scripts/deploy.sh dev services plan

# Apply
./scripts/deploy.sh dev services apply
```

This takes ~3-5 minutes. It creates 4 ECS Fargate services and connects them to the ALB, RDS, and Redis.

**Verify in AWS Console:**
- **ECS** → **forge-dev-cluster** → **Services** → you should see 4 services all showing `ACTIVE` with 1/1 running tasks
- **EC2 → Target Groups** → `forge-dev-api-tg` and `forge-dev-frontend-tg` should show healthy targets

### Step 13: Verify Everything Works

```bash
# Frontend should load
curl -I https://app.yourdomain.com

# API should respond (Swagger docs won't load in production, but base URL works)
curl -I https://api.yourdomain.com

# Check ECS service status
aws ecs describe-services --cluster forge-dev-cluster \
  --services forge-dev-api forge-dev-frontend forge-dev-worker forge-dev-celery \
  --query 'services[*].{Name:serviceName,Status:status,Running:runningCount,Desired:desiredCount}' \
  --output table
```

### Step 14: Update OAuth Callback URLs

Go to each platform's developer console and update callback URLs:

**Google Cloud Console** (console.cloud.google.com):
1. Go to **APIs & Services** → **Credentials**
2. Click your OAuth 2.0 Client ID
3. Add to **Authorized redirect URIs**:
   - `https://api.yourdomain.com/auth/google/callback`
4. Add to **Authorized JavaScript origins**:
   - `https://app.yourdomain.com`

**Twitter Developer Portal** (developer.twitter.com):
- Callback URL: `https://api.yourdomain.com/social-media/callback/twitter`

**Facebook Developer** (developers.facebook.com):
- Valid OAuth Redirect URIs: `https://api.yourdomain.com/social-media/callback/facebook`

**TikTok Developer** (developers.tiktok.com):
- Redirect URI: `https://api.yourdomain.com/social-media/callback/tiktok`

**LinkedIn Developer** (linkedin.com/developers):
- Redirect URL: `https://api.yourdomain.com/social-media/callback/linkedin`

---

## Part 3: Set Up GitHub Auto-Deploy (CI/CD)

This enables automatic deployments when you push code to any repo.

### Step 15: Create GitHub OIDC Provider in AWS

This lets GitHub Actions authenticate to AWS without storing access keys.

**In AWS Console:**

1. Go to **IAM** → **Identity providers** → **Add provider**
2. Provider type: **OpenID Connect**
3. Provider URL: `https://token.actions.githubusercontent.com`
4. Click **Get thumbprint**
5. Audience: `sts.amazonaws.com`
6. Click **Add provider**

### Step 16: Create IAM Role for GitHub Actions

1. Go to **IAM** → **Roles** → **Create role**
2. Trusted entity type: **Web identity**
3. Identity provider: `token.actions.githubusercontent.com`
4. Audience: `sts.amazonaws.com`
5. Click **Next**
6. Attach these policies:
   - `AmazonEC2ContainerRegistryPowerUser` (push/pull images)
   - `AmazonECS_FullAccess` (update services)
7. Click **Next**
8. Role name: `forge-github-actions-deploy`
9. Click **Create role**
10. Click the role → **Trust relationships** → **Edit trust policy**
11. Replace the Condition block to restrict to your GitHub repos:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:YOUR_GITHUB_ORG/forge-nestjs:*",
            "repo:YOUR_GITHUB_ORG/forge-frontend:*",
            "repo:YOUR_GITHUB_ORG/content-forge:*",
            "repo:YOUR_GITHUB_ORG/forge-infra:*"
          ]
        }
      }
    }
  ]
}
```

Replace `YOUR_ACCOUNT_ID` and `YOUR_GITHUB_ORG` with your actual values.

12. Copy the **Role ARN** (e.g., `arn:aws:iam::123456789012:role/forge-github-actions-deploy`)

### Step 17: Add GitHub Secrets to Each Repo

For **each** of the 4 repos (forge-nestjs, forge-frontend, content-forge, forge-infra):

1. Go to the repo on GitHub → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add: `AWS_DEPLOY_ROLE_ARN` = `arn:aws:iam::123456789012:role/forge-github-actions-deploy`

For **forge-frontend** only, add two more secrets:

4. `VITE_API_URL` = `https://api.yourdomain.com`
5. `VITE_GOOGLE_CLIENT_ID` = `your-google-client-id.apps.googleusercontent.com`

### Step 18: Test Auto-Deploy

Make a small change to any repo and push to main:

```bash
# Example: push a change to forge-nestjs
cd ~/git_wsl/forge-nestjs
git add -A && git commit -m "test deploy" && git push

# Watch the GitHub Actions tab in the repo
# It should: build image → push to ECR → update ECS service
```

---

## Summary: What You Created in AWS

| AWS Service | Resource | Purpose |
|-------------|----------|---------|
| **VPC** | forge-dev-vpc | Isolated network |
| **Subnets** | 2 public + 2 private | ALB in public, everything else in private |
| **NAT Gateway** | forge-dev-nat | Outbound internet for private subnets |
| **RDS** | forge-dev-mysql | MySQL 8.0 database |
| **ElastiCache** | forge-dev-redis | Redis 7.0 (Celery broker + BullMQ + pub/sub) |
| **S3** | forge-dev-content | Video/clip storage (replaces MinIO) |
| **ECR** | 3 repositories | Docker image registry |
| **ECS** | forge-dev-cluster | Fargate cluster with 4 services |
| **ALB** | forge-dev-alb | HTTPS load balancer |
| **ACM** | *.yourdomain.com | TLS certificate |
| **Route 53** | app. + api. records | DNS routing |
| **Secrets Manager** | 11 secrets | All sensitive config |
| **IAM** | Execution + task roles | ECS permissions |
| **CloudWatch** | /ecs/forge-dev | Container logs |

## Monthly Cost

~$118/month for the dev environment. See the README for a detailed breakdown.
