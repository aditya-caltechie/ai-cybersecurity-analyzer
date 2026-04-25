#!/usr/bin/env bash
# Validate AWS cleanup for this repo.
#
# Modes:
#   paused-only (default): expects App Runner service exists and is PAUSED
#   destroyed:             expects App Runner + ECR + IAM resources are gone
#
# Usage (repo root):
#   ./scripts/check-aws-cleanup.sh
#   ./scripts/check-aws-cleanup.sh destroyed
#   SERVICE_NAME=cyber-analyzer AWS_REGION=us-east-1 ./scripts/check-aws-cleanup.sh paused-only
#
# Exits non-zero on failure.

set -euo pipefail

MODE="${1:-paused-only}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SERVICE_NAME="${SERVICE_NAME:-cyber-analyzer}"
AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
AWS_REGION="${AWS_REGION:-us-east-1}"

fail() { echo "FAIL: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }
ok() { echo "OK:   $*"; }

echo "Checking AWS cleanup"
echo "  Mode:    ${MODE}"
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

role_name="${SERVICE_NAME}-apprunner-ecr-access"

service_exists=false
if [[ -n "${apprunner_arn}" ]]; then
  service_exists=true
fi

ecr_exists=false
if aws ecr describe-repositories --region "${AWS_REGION}" --repository-names "${ecr_repo_name}" >/dev/null 2>&1; then
  ecr_exists=true
fi

role_exists=false
if aws iam get-role --role-name "${role_name}" >/dev/null 2>&1; then
  role_exists=true
fi

if [[ "${MODE}" == "paused-only" ]]; then
  if [[ "${service_exists}" != "true" ]]; then
    fail "Expected App Runner service '${SERVICE_NAME}' to exist so it can be resumed later."
  fi

  status="$(aws apprunner describe-service --region "${AWS_REGION}" --service-arn "${apprunner_arn}" --query 'Service.Status' --output text)"
  if [[ "${status}" != "PAUSED" ]]; then
    fail "Expected App Runner status PAUSED, got '${status}'. Pause it with: aws apprunner pause-service --region \"${AWS_REGION}\" --service-arn \"${apprunner_arn}\""
  fi

  ok "App Runner exists and is PAUSED: ${apprunner_arn}"

  # Cost note: ECR storage can still incur small costs; it's typically required if you plan to resume.
  if [[ "${ecr_exists}" == "true" ]]; then
    image_count="$(aws ecr list-images --region "${AWS_REGION}" --repository-name "${ecr_repo_name}" --query 'length(imageIds)' --output text 2>/dev/null || echo 0)"
    ok "ECR repo exists (may incur storage costs): ${ecr_repo_name} (images: ${image_count})"
  else
    warn "ECR repo '${ecr_repo_name}' is missing. Resuming App Runner may fail if the image can't be pulled."
  fi

  echo
  echo "Resume later:"
  echo "  aws apprunner resume-service --region \"${AWS_REGION}\" --service-arn \"${apprunner_arn}\""
  echo

elif [[ "${MODE}" == "destroyed" ]]; then
  if [[ "${service_exists}" == "true" ]]; then
    fail "Expected App Runner service to be deleted, but found: ${apprunner_arn}"
  fi
  ok "App Runner service not found."

  if [[ "${role_exists}" == "true" ]]; then
    fail "Expected IAM role to be deleted, but it still exists: ${role_name}"
  fi
  ok "IAM role not found: ${role_name}"

  if [[ "${ecr_exists}" == "true" ]]; then
    fail "Expected ECR repo to be deleted, but it still exists: ${ecr_repo_name} (ECR storage can incur cost)"
  fi
  ok "ECR repo not found: ${ecr_repo_name}"

else
  fail "Unknown mode '${MODE}'. Use 'paused-only' or 'destroyed'."
fi

echo "Cleanup check complete."
