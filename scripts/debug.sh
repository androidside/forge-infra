#!/usr/bin/env bash
# Usage: ./scripts/debug.sh <subcommand> [args]
# Debugging utility for Forge ECS services (app.viralclips.ai)

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
CLUSTER="forge-dev-cluster"
LOG_GROUP="/ecs/forge-dev"
S3_BUCKET="forge-dev-content-263618685979"
REGION="us-east-1"
SERVICES=(api worker frontend celery)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 <command> [args]

Commands:
  logs <service>      Tail live CloudWatch logs (api|worker|celery|frontend)
  status              Show running task count, health, and deployment status
  bucket [prefix]     List S3 bucket contents (optionally filtered by prefix)
  exec <service>      Open interactive shell in a running container
  events <service>    Show recent ECS service events
  urls                Print AWS Console links for quick access

Services: ${SERVICES[*]}
EOF
  exit 1
}

validate_service() {
  local svc="$1"
  for s in "${SERVICES[@]}"; do
    [[ "$s" == "$svc" ]] && return 0
  done
  echo "ERROR: Invalid service '${svc}'. Must be one of: ${SERVICES[*]}" >&2
  exit 1
}

ecs_service_name() {
  echo "forge-dev-$1"
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------
cmd_logs() {
  [[ $# -lt 1 ]] && { echo "Usage: $0 logs <service>" >&2; exit 1; }
  local svc="$1"
  validate_service "$svc"

  echo "==> Tailing logs for ${svc} (Ctrl+C to stop)..."
  aws logs tail "$LOG_GROUP" \
    --region "$REGION" \
    --filter-pattern "\"${svc}\"" \
    --follow \
    --format short \
    --since 30m
}

cmd_status() {
  echo "==> Service status for cluster: ${CLUSTER}"
  echo ""

  local svc_names=()
  for svc in "${SERVICES[@]}"; do
    svc_names+=("$(ecs_service_name "$svc")")
  done

  aws ecs describe-services \
    --region "$REGION" \
    --cluster "$CLUSTER" \
    --services "${svc_names[@]}" \
    --query 'services[].{
      Service: serviceName,
      Status: status,
      Running: runningCount,
      Desired: desiredCount,
      Pending: pendingCount,
      Health: healthCheckGracePeriodSeconds,
      LastDeployment: deployments[0].rolloutState,
      TaskDef: taskDefinition
    }' \
    --output table
}

cmd_bucket() {
  local prefix="${1:-}"
  if [[ -n "$prefix" ]]; then
    echo "==> Listing s3://${S3_BUCKET}/${prefix}"
    aws s3 ls "s3://${S3_BUCKET}/${prefix}" --region "$REGION" --recursive --human-readable
  else
    echo "==> Listing s3://${S3_BUCKET}/"
    aws s3 ls "s3://${S3_BUCKET}/" --region "$REGION" --human-readable
  fi
}

cmd_exec() {
  [[ $# -lt 1 ]] && { echo "Usage: $0 exec <service>" >&2; exit 1; }
  local svc="$1"
  validate_service "$svc"

  local ecs_svc
  ecs_svc="$(ecs_service_name "$svc")"

  echo "==> Finding running task for ${ecs_svc}..."
  local task_arn
  task_arn=$(aws ecs list-tasks \
    --region "$REGION" \
    --cluster "$CLUSTER" \
    --service-name "$ecs_svc" \
    --desired-status RUNNING \
    --query 'taskArns[0]' \
    --output text)

  if [[ -z "$task_arn" || "$task_arn" == "None" ]]; then
    echo "ERROR: No running tasks found for ${ecs_svc}" >&2
    exit 1
  fi

  echo "==> Connecting to task: ${task_arn##*/}"
  echo "    (Requires ECS Exec to be enabled on the service)"
  aws ecs execute-command \
    --region "$REGION" \
    --cluster "$CLUSTER" \
    --task "$task_arn" \
    --container "$svc" \
    --command "/bin/sh" \
    --interactive
}

cmd_events() {
  [[ $# -lt 1 ]] && { echo "Usage: $0 events <service>" >&2; exit 1; }
  local svc="$1"
  validate_service "$svc"

  local ecs_svc
  ecs_svc="$(ecs_service_name "$svc")"

  echo "==> Recent events for ${ecs_svc}:"
  echo ""
  aws ecs describe-services \
    --region "$REGION" \
    --cluster "$CLUSTER" \
    --services "$ecs_svc" \
    --query 'services[0].events[:15].{At: createdAt, Message: message}' \
    --output table
}

cmd_urls() {
  cat <<EOF
==> AWS Console Links (us-east-1)

ECS Cluster:
  https://us-east-1.console.aws.amazon.com/ecs/v2/clusters/forge-dev-cluster/services?region=us-east-1

CloudWatch Logs:
  https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/\$252Fecs\$252Fforge-dev

S3 Bucket:
  https://s3.console.aws.amazon.com/s3/buckets/forge-dev-content-263618685979?region=us-east-1

RDS (MySQL):
  https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#database:id=forge-dev-mysql

ElastiCache (Redis):
  https://us-east-1.console.aws.amazon.com/elasticache/home?region=us-east-1#/redis/forge-dev-redis

ECS Services:
  API:      https://us-east-1.console.aws.amazon.com/ecs/v2/clusters/forge-dev-cluster/services/forge-dev-api?region=us-east-1
  Worker:   https://us-east-1.console.aws.amazon.com/ecs/v2/clusters/forge-dev-cluster/services/forge-dev-worker?region=us-east-1
  Frontend: https://us-east-1.console.aws.amazon.com/ecs/v2/clusters/forge-dev-cluster/services/forge-dev-frontend?region=us-east-1
  Celery:   https://us-east-1.console.aws.amazon.com/ecs/v2/clusters/forge-dev-cluster/services/forge-dev-celery?region=us-east-1
EOF
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
[[ $# -lt 1 ]] && usage

COMMAND="$1"
shift

case "$COMMAND" in
  logs)    cmd_logs "$@" ;;
  status)  cmd_status ;;
  bucket)  cmd_bucket "$@" ;;
  exec)    cmd_exec "$@" ;;
  events)  cmd_events "$@" ;;
  urls)    cmd_urls ;;
  *)       echo "ERROR: Unknown command '${COMMAND}'" >&2; usage ;;
esac
