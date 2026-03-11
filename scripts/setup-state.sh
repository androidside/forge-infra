#!/usr/bin/env bash
# Creates S3 bucket and DynamoDB table for Terraform state management.
# Run once before first terraform init.

set -euo pipefail

BUCKET_NAME="forge-terraform-state-263618685979"
TABLE_NAME="forge-terraform-locks"
REGION="us-east-1"

# ---------------------------------------------------------------------------
# Preflight: check AWS CLI
# ---------------------------------------------------------------------------
if ! command -v aws &>/dev/null; then
  echo "ERROR: AWS CLI is not installed. Install it from https://aws.amazon.com/cli/" >&2
  exit 1
fi

echo "==> Creating S3 bucket: ${BUCKET_NAME} in ${REGION}"

# us-east-1 does not accept a LocationConstraint; every other region requires one.
if [[ "${REGION}" == "us-east-1" ]]; then
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}"
else
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"
fi

echo "==> Enabling versioning on ${BUCKET_NAME}"
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

echo "==> Enabling default AES256 encryption on ${BUCKET_NAME}"
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

echo "==> Blocking all public access on ${BUCKET_NAME}"
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "==> Creating DynamoDB table: ${TABLE_NAME} in ${REGION}"
aws dynamodb create-table \
  --table-name "${TABLE_NAME}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${REGION}"

echo ""
echo "Terraform remote state backend is ready."
echo "  Bucket : ${BUCKET_NAME}"
echo "  Table  : ${TABLE_NAME}"
echo "  Region : ${REGION}"
