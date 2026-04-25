#!/usr/bin/env bash
# Pause or destroy AWS resources created by terraform/aws.
#
# NOTE (App Runner availability change):
# AWS App Runner is no longer open to new customers starting Mar 31, 2026.
# Services moving to maintenance will no longer be accessible to new customers starting Apr 30, 2026.
# Existing customers can continue to use the service. See:
# - https://docs.aws.amazon.com/apprunner/latest/dg/manage-pause.html
# - https://docs.aws.amazon.com/apprunner/latest/api/API_PauseService.html
#
# Because of this, the default behavior is to PAUSE the App Runner service (keeping it)
# instead of deleting it.

set -euo pipefail

START_EPOCH="$(date +%s)"
START_HUMAN="$(date)"
echo "AWS destroy/pause start: ${START_HUMAN}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Keys are still required for destroy because variables are referenced." >&2
  exit 1
fi

# shellcheck disable=SC2046
export $(grep -v '^#' "${ENV_FILE}" | xargs)

DOCKER_HOST_FROM_CONTEXT="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"

cd "${ROOT}/terraform/aws"
terraform workspace select aws

MODE="${1:-pause}"
if [[ "${MODE}" == "destroy" ]]; then
  shift || true
  terraform destroy \
    -var="openai_api_key=${OPENAI_API_KEY}" \
    -var="semgrep_app_token=${SEMGREP_APP_TOKEN}" \
    -var="docker_host=${DOCKER_HOST_FROM_CONTEXT}" \
    "$@"
else
  # Default: pause App Runner service (compute to zero) and keep resources for later resume.
  SERVICE_ARN="$(terraform output -raw apprunner_service_arn 2>/dev/null || true)"
  AWS_REGION="$(terraform output -raw aws_region 2>/dev/null || true)"

  if [[ -z "${SERVICE_ARN}" ]]; then
    echo "No App Runner service ARN found in Terraform outputs. Nothing to pause." >&2
    echo "If you haven't deployed yet, run ./scripts/deploy-aws.sh first." >&2
    exit 0
  fi

  echo "Pausing App Runner service:"
  echo "  ARN:    ${SERVICE_ARN}"
  echo "  Region: ${AWS_REGION:-<default>}"

  if [[ -n "${AWS_REGION}" ]]; then
    aws apprunner pause-service --region "${AWS_REGION}" --service-arn "${SERVICE_ARN}" >/dev/null
  else
    aws apprunner pause-service --service-arn "${SERVICE_ARN}" >/dev/null
  fi

  echo "Paused. To resume later:"
  if [[ -n "${AWS_REGION}" ]]; then
    echo "  aws apprunner resume-service --region \"${AWS_REGION}\" --service-arn \"${SERVICE_ARN}\""
  else
    echo "  aws apprunner resume-service --service-arn \"${SERVICE_ARN}\""
  fi
fi

END_EPOCH="$(date +%s)"
END_HUMAN="$(date)"
ELAPSED="$((END_EPOCH - START_EPOCH))"
echo "AWS destroy/pause end:   ${END_HUMAN}"
echo "AWS destroy/pause time:  ${ELAPSED}s"
