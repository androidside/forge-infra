#!/usr/bin/env bash
# Usage: ./build-push.sh <service> [--tag <tag>]
# Services: api, frontend, worker

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
  echo "Usage: $0 <service> [--tag <tag>]"
  echo "  service: api | frontend | worker"
  echo "  --tag  : Docker image tag (default: git short SHA)"
  exit 1
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  usage
fi

SERVICE="$1"
shift

TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "${TAG}" ]]; then
  TAG="$(git rev-parse --short HEAD)"
fi

# ---------------------------------------------------------------------------
# Map service -> source directory & ECR repo name
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPOS_ROOT="$(cd "${INFRA_ROOT}/../.." && pwd)"

case "${SERVICE}" in
  api)
    CONTEXT_DIR="${REPOS_ROOT}/forge-nestjs"
    REPO_NAME="forge-api"
    ;;
  frontend)
    CONTEXT_DIR="${REPOS_ROOT}/forge-frontend"
    REPO_NAME="forge-frontend"
    ;;
  worker)
    CONTEXT_DIR="${REPOS_ROOT}/content-forge"
    REPO_NAME="forge-worker"
    ;;
  *)
    echo "ERROR: Unknown service '${SERVICE}'. Must be api, frontend, or worker." >&2
    usage
    ;;
esac

DOCKERFILE_PATH="${CONTEXT_DIR}/Dockerfile"

if [[ ! -f "${DOCKERFILE_PATH}" ]]; then
  echo "ERROR: Dockerfile not found at ${DOCKERFILE_PATH}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# AWS details
# ---------------------------------------------------------------------------
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
AWS_REGION="$(aws configure get region || echo "us-east-1")"
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}"

# ---------------------------------------------------------------------------
# ECR Login
# ---------------------------------------------------------------------------
echo "==> Logging in to ECR: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin \
    "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo "==> Building ${REPO_NAME}:${TAG} from ${CONTEXT_DIR}"

BUILD_ARGS=""
if [[ "${SERVICE}" == "frontend" ]]; then
  BUILD_ARGS="--build-arg VITE_API_URL=${VITE_API_URL:-} --build-arg VITE_GOOGLE_CLIENT_ID=${VITE_GOOGLE_CLIENT_ID:-}"
fi

# shellcheck disable=SC2086
docker build \
  ${BUILD_ARGS} \
  -t "${REPO_NAME}:${TAG}" \
  -f "${DOCKERFILE_PATH}" \
  "${CONTEXT_DIR}"

# ---------------------------------------------------------------------------
# Tag & Push
# ---------------------------------------------------------------------------
echo "==> Tagging ${REPO_NAME}:${TAG} -> ${ECR_URI}:${TAG}"
docker tag "${REPO_NAME}:${TAG}" "${ECR_URI}:${TAG}"

echo "==> Tagging ${REPO_NAME}:${TAG} -> ${ECR_URI}:latest"
docker tag "${REPO_NAME}:${TAG}" "${ECR_URI}:latest"

echo "==> Pushing ${ECR_URI}:${TAG}"
docker push "${ECR_URI}:${TAG}"

echo "==> Pushing ${ECR_URI}:latest"
docker push "${ECR_URI}:latest"

echo ""
echo "Done. Image pushed to:"
echo "  ${ECR_URI}:${TAG}"
echo "  ${ECR_URI}:latest"
