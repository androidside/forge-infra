# Runbooks

Common operations and troubleshooting procedures.

## Deploying a New Version

### Single Service

```bash
# 1. Build and push
./scripts/build-push.sh api --tag $(git rev-parse --short HEAD)

# 2. Update the ECS service (force new deployment pulls latest image)
aws ecs update-service \
  --cluster forge-dev-cluster \
  --service forge-dev-api \
  --force-new-deployment

# 3. Watch the deployment
aws ecs wait services-stable --cluster forge-dev-cluster --services forge-dev-api
```

### All Services

```bash
./scripts/build-push.sh api
./scripts/build-push.sh frontend
./scripts/build-push.sh worker

./scripts/deploy.sh dev services plan
./scripts/deploy.sh dev services apply
```

## Viewing Logs

```bash
# Follow API logs
aws logs tail /ecs/forge-dev --follow --filter-pattern "api"

# Search for errors in the last hour
aws logs filter-log-events \
  --log-group-name /ecs/forge-dev \
  --start-time $(date -d '1 hour ago' +%s000) \
  --filter-pattern "ERROR"

# View specific task logs
aws logs get-log-events \
  --log-group-name /ecs/forge-dev \
  --log-stream-name "api/<task-id>"
```

## Database Operations

### Connect to RDS

Since RDS is in a private subnet, you need a bastion or SSM tunnel:

```bash
# Get RDS endpoint
aws rds describe-db-instances --db-instance-identifier forge-dev-mysql \
  --query 'DBInstances[0].Endpoint.Address' --output text

# Get credentials
aws secretsmanager get-secret-value --secret-id forge/db-credentials \
  --query SecretString --output text | jq

# Option 1: SSM port forwarding (requires an EC2 instance with SSM agent)
aws ssm start-session \
  --target <ec2-instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["forge-dev-mysql.xxx.us-east-1.rds.amazonaws.com"],"portNumber":["3306"],"localPortNumber":["3306"]}'

# Then connect locally
mysql -h 127.0.0.1 -u forge_admin -p forge
```

### Run Migrations

The API service runs migrations on startup when `RUN_MIGRATIONS=true` (set in the services environment). To trigger a migration:

```bash
# Force a new deployment of the API service
aws ecs update-service --cluster forge-dev-cluster --service forge-dev-api --force-new-deployment
```

## Scaling

### Manually Scale a Service

```bash
# Scale API to 2 tasks
aws ecs update-service --cluster forge-dev-cluster --service forge-dev-api --desired-count 2

# Scale Celery workers for heavy processing
aws ecs update-service --cluster forge-dev-cluster --service forge-dev-celery --desired-count 3
```

### Update via Terraform

Edit `desired_count` in `environments/dev/services/main.tf`, then:

```bash
./scripts/deploy.sh dev services plan
./scripts/deploy.sh dev services apply
```

## Checking Service Health

```bash
# List all services and their status
aws ecs list-services --cluster forge-dev-cluster --output table

# Describe a specific service
aws ecs describe-services --cluster forge-dev-cluster --services forge-dev-api \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Deployments:deployments[*].{Status:status,Running:runningCount}}'

# Check ALB target health
aws elbv2 describe-target-health --target-group-arn <tg-arn>
```

## Rotating Secrets

```bash
# 1. Update the secret value
aws secretsmanager update-secret --secret-id forge/jwt \
  --secret-string '{"secret":"new-jwt-secret","access_expiration":"15m","refresh_expiration":"7d"}'

# 2. Restart all services that use the secret
aws ecs update-service --cluster forge-dev-cluster --service forge-dev-api --force-new-deployment
aws ecs update-service --cluster forge-dev-cluster --service forge-dev-worker --force-new-deployment

# 3. Wait for stability
aws ecs wait services-stable --cluster forge-dev-cluster --services forge-dev-api forge-dev-worker
```

## Cost Monitoring

```bash
# Check current month costs by service
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Emergency: Rolling Back a Deployment

```bash
# Find the previous task definition revision
aws ecs list-task-definitions --family-prefix forge-dev-api --sort DESC --max-items 5

# Update service to use the previous revision
aws ecs update-service \
  --cluster forge-dev-cluster \
  --service forge-dev-api \
  --task-definition forge-dev-api:<previous-revision-number>
```
