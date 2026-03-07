#!/usr/bin/env bash
# Usage: ./deploy.sh <environment> <workspace> <plan|apply|destroy>
# Example: ./deploy.sh dev shared plan
#          ./deploy.sh dev services apply

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
  echo "Usage: $0 <environment> <workspace> <action>"
  echo "  environment : dev | staging | prod"
  echo "  workspace   : shared | services"
  echo "  action      : plan | apply | destroy"
  exit 1
}

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
if [[ $# -ne 3 ]]; then
  usage
fi

ENVIRONMENT="$1"
WORKSPACE="$2"
ACTION="$3"

# Validate environment
case "${ENVIRONMENT}" in
  dev|staging|prod) ;;
  *)
    echo "ERROR: Invalid environment '${ENVIRONMENT}'. Must be dev, staging, or prod." >&2
    usage
    ;;
esac

# Validate workspace
case "${WORKSPACE}" in
  shared|services) ;;
  *)
    echo "ERROR: Invalid workspace '${WORKSPACE}'. Must be shared or services." >&2
    usage
    ;;
esac

# Validate action
case "${ACTION}" in
  plan|apply|destroy) ;;
  *)
    echo "ERROR: Invalid action '${ACTION}'. Must be plan, apply, or destroy." >&2
    usage
    ;;
esac

# ---------------------------------------------------------------------------
# Locate Terraform directory
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../environments/${ENVIRONMENT}/${WORKSPACE}"

if [[ ! -d "${TF_DIR}" ]]; then
  echo "ERROR: Terraform directory not found: ${TF_DIR}" >&2
  exit 1
fi

echo "==> Working directory: ${TF_DIR}"
cd "${TF_DIR}"

# ---------------------------------------------------------------------------
# Initialize
# ---------------------------------------------------------------------------
echo "==> Running terraform init -reconfigure"
terraform init -reconfigure

# ---------------------------------------------------------------------------
# Execute action
# ---------------------------------------------------------------------------
case "${ACTION}" in
  plan)
    echo "==> Running terraform plan"
    terraform plan -out=tfplan
    echo ""
    echo "Plan saved to ${TF_DIR}/tfplan"
    echo "Run '$0 ${ENVIRONMENT} ${WORKSPACE} apply' to apply."
    ;;
  apply)
    if [[ ! -f tfplan ]]; then
      echo "ERROR: No plan file found. Run '$0 ${ENVIRONMENT} ${WORKSPACE} plan' first." >&2
      exit 1
    fi
    echo "==> Running terraform apply"
    terraform apply tfplan
    echo ""
    echo "Apply complete for ${ENVIRONMENT}/${WORKSPACE}."
    ;;
  destroy)
    echo ""
    echo "WARNING: This will destroy all resources in ${ENVIRONMENT}/${WORKSPACE}."
    read -rp "Type 'yes' to confirm: " CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
      echo "Aborted."
      exit 0
    fi
    echo "==> Running terraform destroy"
    terraform destroy
    echo ""
    echo "Destroy complete for ${ENVIRONMENT}/${WORKSPACE}."
    ;;
esac
