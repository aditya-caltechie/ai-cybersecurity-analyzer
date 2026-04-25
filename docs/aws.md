# Deploy on AWS (Terraform)

This project’s container needs **long-running** processes (**Uvicorn**, **Semgrep MCP**, OpenAI Agents). That matches **Azure Container Apps** and **GCP Cloud Run**. On AWS, the closest **simple** managed option is **AWS App Runner** backed by **Amazon ECR**, which is what `terraform/aws` implements.

> **Why not copy [ai-digital-twin/terraform](https://github.com/aditya-caltechie/ai-digital-twin/tree/main/terraform)?**  
> That stack uses **Lambda + HTTP API Gateway + S3 + CloudFront** ([`main.tf` reference](https://github.com/aditya-caltechie/ai-digital-twin/blob/main/terraform/main.tf)). Lambda has **short timeouts** and is a **zip** or container **handler** model—poor fit for a **single FastAPI process** that spawns **Semgrep** and holds **~2 GiB** memory. App Runner + ECR mirrors how this repo already deploys on Azure/GCP: **one image**, **port 8000**, **Terraform Docker build/push**.

---

## What you need from AWS

| Item | Purpose |
|------|---------|
| **AWS account** | Billing and IAM. |
| **IAM principal with permissions** | Create ECR, App Runner, IAM roles, pass roles. A broad lab policy is `AdministratorAccess` on a throwaway account; tighter production policies would scope to `ecr:*`, `apprunner:*`, `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PassRole` on specific ARNs. |
| **Region** | Default `us-east-1` (App Runner [supported regions](https://docs.aws.amazon.com/general/latest/gr/apprunner.html)). Override with `-var="aws_region=us-west-2"` if needed. |
| **AWS CLI v2** | `aws configure` or environment credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optional `AWS_SESSION_TOKEN`). |
| **Docker Desktop** (or engine) | Terraform **kreuzwerker/docker** builds `linux/amd64` and pushes to ECR from your laptop (same pattern as `terraform/azure` / `terraform/gcp`). |

You still use **OpenAI** and **Semgrep** as **SaaS APIs** (keys in `.env`), not **Amazon Bedrock** or a VPC-bound Semgrep appliance—same as the other clouds in this repo.

---

## AWS services created by `terraform/aws`

```text
  Your laptop (Terraform + Docker)
        |
        | docker build --platform linux/amd64 ; docker push
        v
  Amazon ECR (private repository: service name, default `cyber-analyzer`)
        |
        | image pull on deploy / update
        v
  AWS App Runner (managed HTTPS, runs 1 vCPU / 2 GiB container on port 8000)
        ^
        |
  IAM role (App Runner → ECR pull) + AWS managed policy AWSAppRunnerServicePolicyForECRAccess
```

| Service | Resource | Role |
|---------|----------|------|
| **Amazon ECR** | `aws_ecr_repository` | Stores the built image; scan-on-push enabled. |
| **AWS App Runner** | `aws_apprunner_service` | Runs the container, public HTTPS URL, health check on `/health`. |
| **AWS App Runner** | `aws_apprunner_auto_scaling_configuration_version` | `min_size` / `max_size` = 1 (provider requires `min_size >= 1`). |
| **IAM** | `aws_iam_role` + attachment | Lets **build.apprunner.amazonaws.com** pull from ECR. |

**Not included:** VPC, ALB (App Runner provides ingress), RDS, **AWS Secrets Manager** (secrets are plain container env vars for the lab, like the existing Azure/GCP stacks—upgrade path is Secrets Manager + execution role).

---

## One-time: Terraform workspace

From repo root (after loading `.env`):

```bash
cd terraform/aws
terraform init
terraform workspace new aws   # once
terraform workspace select aws
```

---

## Deploy

**macOS / Linux** (from repo root):

```bash
export $(grep -v '^#' .env | xargs)
cd terraform/aws

terraform apply \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"
```

**Windows (PowerShell)** from repo root:

```powershell
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
  $n, $v = $_.Split('=', 2)
  Set-Item -Path "env:$n" -Value $v
}
Set-Location terraform\aws
terraform apply `
  -var ("openai_api_key=" + $Env:OPENAI_API_KEY) `
  -var ("semgrep_app_token=" + $Env:SEMGREP_APP_TOKEN)
```

Optional: change region or image tag:

```bash
terraform apply \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN" \
  -var="aws_region=us-west-2" \
  -var="docker_image_tag=v2"
```

**Convenience script** (plan + apply + print URL):

```bash
./scripts/deploy-aws.sh
# non-interactive:
./scripts/deploy-aws.sh -auto-approve
```

**Output URL:**

```bash
terraform output -raw service_url
```

### If you previously ran the older AWS stack

Earlier versions of `terraform/aws` used the Terraform **docker provider** (`docker_image.app`). If you ran that and later updated the stack, Terraform may still have a `docker_image.app` entry in state and fail trying to refresh it via `/var/run/docker.sock` on macOS.

Fix once:

```bash
cd terraform/aws
terraform workspace select aws
terraform state rm docker_image.app
```

---

## Rebuild after code changes

Same caveat as Azure/GCP: the Docker provider may not notice source changes. Either bump **`docker_image_tag`** and apply, or:

```bash
terraform taint docker_image.app
terraform taint docker_registry_image.app
terraform apply -var="openai_api_key=$OPENAI_API_KEY" -var="semgrep_app_token=$SEMGREP_APP_TOKEN"
```

---

## Destroy (stop charges)

> **Important note (App Runner availability change)**: AWS App Runner is no longer open to new customers starting **Mar 31, 2026**, and becomes unavailable to **new** customers starting **Apr 30, 2026** (moves to maintenance). Existing customers can continue to use the service. Because of this, the default “cleanup” flow in this repo **pauses** the App Runner service instead of deleting it. See AWS docs: [`manage-pause`](https://docs.aws.amazon.com/apprunner/latest/dg/manage-pause.html) and [`PauseService`](https://docs.aws.amazon.com/apprunner/latest/api/API_PauseService.html).

```bash
export $(grep -v '^#' .env | xargs)
cd terraform/aws
terraform workspace select aws

terraform destroy \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"
```

Or:

```bash
./scripts/destroy-aws.sh
```

### Pause instead of deleting (recommended)

Pausing reduces compute to zero but keeps the App Runner service + domain, so you can resume later without recreating it:

```bash
./scripts/destroy-aws.sh
```

To resume:

```bash
aws apprunner resume-service --service-arn "$(cd terraform/aws && terraform output -raw apprunner_service_arn)"
```

### If you really want to delete everything

```bash
./scripts/destroy-aws.sh destroy
```

---

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `ExpiredToken` / `InvalidClientTokenId` | `aws sts get-caller-identity`; refresh credentials. |
| `AccessDenied` on ECR / App Runner | IAM user/role needs create + pass-role for App Runner access role. |
| App **Running** but 5xx | CloudWatch Logs → App Runner service → **Application logs** (startup, Semgrep, OpenAI). |
| Image pull errors | Ensure `linux/amd64` build (already set in Terraform) matches App Runner architecture. |

---

## Related files

| Path | Purpose |
|------|---------|
| [`terraform/aws/`](../terraform/aws/) | `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` |
| [`scripts/deploy-aws.sh`](../scripts/deploy-aws.sh) | Init, `aws` workspace, plan, apply |
| [`scripts/destroy-aws.sh`](../scripts/destroy-aws.sh) | `terraform destroy` |
| [`scripts/check-aws-deploy.sh`](../scripts/check-aws-deploy.sh) | Verify App Runner + ECR are healthy |
| [`scripts/check-aws-cleanup.sh`](../scripts/check-aws-cleanup.sh) | Verify pause-only vs full destroy cleanup |
| [`README.md`](../README.md) | Short AWS snippet next to Azure/GCP |
