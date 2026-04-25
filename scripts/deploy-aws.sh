#!/usr/bin/env bash
# Deploy Cybersecurity Analyzer to AWS (ECR + App Runner) via Terraform.
# Prerequisites: AWS CLI configured (`aws configure` or env vars), Docker running,
# repo-root `.env` with OPENAI_API_KEY and SEMGREP_APP_TOKEN.

set -euo pipefail

START_EPOCH="$(date +%s)"
START_HUMAN="$(date)"
echo "AWS deploy start: ${START_HUMAN}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Create it with OPENAI_API_KEY and SEMGREP_APP_TOKEN." >&2
  exit 1
fi

# shellcheck disable=SC2046
export $(grep -v '^#' "${ENV_FILE}" | xargs)

DOCKER_HOST_FROM_CONTEXT="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"

cd "${ROOT}/terraform/aws"

terraform init
# Prefer selecting the workspace; create only if missing.
if ! terraform workspace select aws >/dev/null 2>&1; then
  terraform workspace new aws >/dev/null
  terraform workspace select aws >/dev/null
fi

terraform plan \
  -var="openai_api_key=${OPENAI_API_KEY}" \
  -var="semgrep_app_token=${SEMGREP_APP_TOKEN}" \
  -var="docker_host=${DOCKER_HOST_FROM_CONTEXT}"

# Extra args (e.g. -auto-approve) apply only to terraform apply
terraform apply \
  -var="openai_api_key=${OPENAI_API_KEY}" \
  -var="semgrep_app_token=${SEMGREP_APP_TOKEN}" \
  -var="docker_host=${DOCKER_HOST_FROM_CONTEXT}" \
  "$@"

echo
echo "Service URL:"
terraform output -raw service_url
echo

END_EPOCH="$(date +%s)"
END_HUMAN="$(date)"
ELAPSED="$((END_EPOCH - START_EPOCH))"
echo "AWS deploy end:   ${END_HUMAN}"
echo "AWS deploy time:  ${ELAPSED}s"
