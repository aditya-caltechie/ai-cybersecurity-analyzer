#!/usr/bin/env bash
# Tear down AWS resources created by terraform/aws (ECR images, App Runner, IAM, ECR repo).

set -euo pipefail

START_EPOCH="$(date +%s)"
START_HUMAN="$(date)"
echo "AWS destroy start: ${START_HUMAN}"

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

terraform destroy \
  -var="openai_api_key=${OPENAI_API_KEY}" \
  -var="semgrep_app_token=${SEMGREP_APP_TOKEN}" \
  -var="docker_host=${DOCKER_HOST_FROM_CONTEXT}" \
  "$@"

END_EPOCH="$(date +%s)"
END_HUMAN="$(date)"
ELAPSED="$((END_EPOCH - START_EPOCH))"
echo "AWS destroy end:   ${END_HUMAN}"
echo "AWS destroy time:  ${ELAPSED}s"
