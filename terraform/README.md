# Terraform deployments

This repo supports deploying the same **single Docker image** (FastAPI serving the static frontend on **port 8000**) to:

- **Azure Container Apps** (`terraform/azure`)
- **GCP Cloud Run** (`terraform/gcp`)
- **AWS App Runner** + **ECR** (`terraform/aws`)

All stacks pass secrets as Terraform variables (recommended: load them from your local `.env` into your shell).

---

## Common prerequisites

- **Docker** running locally (Terraform builds and pushes the image from your machine)
- **Terraform** installed
- Repo-root **`.env`** with:
  - `OPENAI_API_KEY`
  - `SEMGREP_APP_TOKEN`

macOS / Linux (from repo root):

```bash
export $(grep -v '^#' .env | xargs)
```

---

## Azure (Container Apps) — `terraform/azure`

### What gets created

- **Azure Container Registry (ACR)** (stores the image)
- **Log Analytics workspace** (logs/monitoring sink)
- **Container Apps Environment**
- **Container App** (public HTTPS ingress → container port `8000`, **1 vCPU / 2 GiB**, min replicas 0 / max 1)

### One-time setup

- Create a resource group (default `cyber-analyzer-rg`)
- Register providers once per subscription:
  - `Microsoft.App`
  - `Microsoft.OperationalInsights`

### Commands

```bash
cd terraform/azure
terraform init

terraform workspace new azure   # only once
terraform workspace select azure

az login

terraform plan \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"

terraform apply \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"

terraform output app_url
```

### Rebuild / redeploy after code changes

```bash
terraform apply \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN" \
  -var="docker_image_tag=v2"
```

### Cleanup

```bash
terraform destroy \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"
```

Docs: `docs/workshop/week3/day1.part2.md` and `docs/azure.md`.

---

## GCP (Cloud Run) — `terraform/gcp`

### What gets created

- **Artifact Registry** (Docker repository)
- **Cloud Run service** (public HTTPS, container port `8000`, **1 vCPU / 2 GiB**, min instances 0 / max 1)
- Required APIs enabled (Cloud Run / Artifact Registry / Cloud Build)

### One-time setup

- Create a GCP Project and enable billing
- Set `TF_VAR_project_id` (project ID, not name)
- Authenticate with `gcloud` (including application-default credentials)

### Commands

```bash
export TF_VAR_project_id="your-gcp-project-id"
cd terraform/gcp
terraform init

terraform workspace new gcp   # only once
terraform workspace select gcp

terraform apply \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"

terraform output service_url
```

### Cleanup

```bash
terraform destroy \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"
```

Docs: `docs/workshop/week3/day2.part2.md`.

---

## AWS (App Runner + ECR) — `terraform/aws`

### What gets created

- **Amazon ECR repository** (stores the image)
- **IAM role** that App Runner assumes to pull from ECR
- **App Runner service** (public HTTPS, container port `8000`, **1 vCPU / 2 GiB**)

> Note: the Terraform AWS provider requires App Runner `min_size >= 1`, so this stack does **not** scale to zero.

### Commands

```bash
cd terraform/aws
terraform init

terraform workspace new aws   # only once
terraform workspace select aws

terraform apply \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"

terraform output -raw service_url
```

### Helper scripts (repo root)

```bash
./scripts/deploy-aws.sh
./scripts/destroy-aws.sh
```

### Cleanup

```bash
terraform destroy \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"
```

Docs: `docs/aws.md`.

