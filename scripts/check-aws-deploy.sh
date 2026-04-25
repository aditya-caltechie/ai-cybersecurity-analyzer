#!/usr/bin/env bash
# Validate AWS deployment for this repo (ECR + App Runner).
#
# Usage (repo root):
#   ./scripts/check-aws-deploy.sh
#   SERVICE_NAME=my-service AWS_REGION=us-east-1 ./scripts/check-aws-deploy.sh
#
# Exits non-zero on failure.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SERVICE_NAME="${SERVICE_NAME:-cyber-analyzer}"
AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "Checking AWS deployment"
echo "  Service: ${SERVICE_NAME}"
echo "  Region:  ${AWS_REGION}"
echo

aws sts get-caller-identity >/dev/null

tf_dir="${ROOT}/terraform/aws"
tf_outputs="{}"
if [[ -d "${tf_dir}" ]]; then
  tf_outputs="$(cd "${tf_dir}" && terraform output -json 2>/dev/null || echo '{}')"
fi

apprunner_arn="$(echo "${tf_outputs}" | jq -r '.apprunner_service_arn.value // empty')"
service_url="$(echo "${tf_outputs}" | jq -r '.service_url.value // empty')"
ecr_repo_name="$(echo "${tf_outputs}" | jq -r '.ecr_repository_name.value // empty')"

if [[ -z "${ecr_repo_name}" ]]; then
  ecr_repo_name="${SERVICE_NAME}"
fi

if [[ -z "${apprunner_arn}" ]]; then
  apprunner_arn="$(aws apprunner list-services \
    --region "${AWS_REGION}" \
    --query "ServiceSummaryList[?ServiceName=='${SERVICE_NAME}'].ServiceArn | [0]" \
    --output text 2>/dev/null || true)"
  [[ "${apprunner_arn}" == "None" ]] && apprunner_arn=""
fi

if [[ -z "${service_url}" ]]; then
  url_host="$(aws apprunner list-services \
    --region "${AWS_REGION}" \
    --query "ServiceSummaryList[?ServiceName=='${SERVICE_NAME}'].ServiceUrl | [0]" \
    --output text 2>/dev/null || true)"
  [[ "${url_host}" == "None" ]] && url_host=""
  if [[ -n "${url_host}" ]]; then
    service_url="https://${url_host}"
  fi
fi

fail() { echo "FAIL: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }
ok() { echo "OK:   $*"; }

# --- App Runner ---
if [[ -z "${apprunner_arn}" ]]; then
  fail "App Runner service '${SERVICE_NAME}' not found in ${AWS_REGION}."
fi

status="$(aws apprunner describe-service \
  --region "${AWS_REGION}" \
  --service-arn "${apprunner_arn}" \
  --query 'Service.Status' \
  --output text)"

ok "App Runner exists: ${apprunner_arn}"
ok "App Runner status: ${status}"

if [[ "${status}" == "PAUSED" ]]; then
  warn "Service is PAUSED (no compute). Resume with:"
  echo "  aws apprunner resume-service --region \"${AWS_REGION}\" --service-arn \"${apprunner_arn}\""
elif [[ "${status}" == "OPERATION_IN_PROGRESS" ]]; then
  warn "Service is still provisioning. Re-run this check in ~1-3 minutes."
elif [[ "${status}" != "RUNNING" ]]; then
  warn "Unexpected status '${status}'. Check the App Runner console logs."
fi

# Optional health probe when RUNNING and URL known
if [[ "${status}" == "RUNNING" && -n "${service_url}" ]]; then
  if curl -fsS "${service_url}/health" >/dev/null 2>&1; then
    ok "Health check responds: ${service_url}/health"
  else
    warn "Health check did not succeed yet at ${service_url}/health"
  fi
fi

echo

# --- ECR ---
if aws ecr describe-repositories --region "${AWS_REGION}" --repository-names "${ecr_repo_name}" >/dev/null 2>&1; then
  ok "ECR repo exists: ${ecr_repo_name}"
else
  fail "ECR repo '${ecr_repo_name}' not found in ${AWS_REGION}."
fi

image_count="$(aws ecr list-images --region "${AWS_REGION}" --repository-name "${ecr_repo_name}" --query 'length(imageIds)' --output text 2>/dev/null || echo 0)"
if [[ "${image_count}" == "None" ]]; then image_count="0"; fi

if [[ "${image_count}" -gt 0 ]]; then
  ok "ECR images present: ${image_count}"
else
  warn "ECR repo has 0 images. App Runner may fail to (re)start if it can't pull the tag."
fi

echo
echo "Deployment check complete."
