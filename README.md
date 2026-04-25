# AI Cybersecurity Analyzer 🛡️ 

Web app that analyzes Python code for security issues using **Semgrep** (static analysis) and an **OpenAI Agents** workflow with the **Semgrep MCP** server.

**Recommended deployment path (this repo): AWS App Runner + ECR** using the scripts in `scripts/`.

Azure and GCP Terraform stacks are included as optional later paths.

![Course image](docs/assets/cyber.png)

## Architecture (high level)

```text
  User
    |
    v
+-------------+     HTTP      +----------------------+
|  Next.js    | ------------> |  FastAPI + AI agent  |
|  (browser)  |   /api/...    +----------+-----------+
+-------------+                          |
                                         |
                         +---------------+---------------+
                         v                               v
                  +-------------+                 +----------------+
                  |  OpenAI API |                 | Semgrep (MCP)  |
                  |  (analysis) |                 | static scan    |
                  +-------------+                 +----------------+
```

In **production Docker**, the built Next.js app is served as static files from the same FastAPI process on port `8000` (one container). In **local dev**, the UI usually runs on `3000` and talks to the API on `8000`.

## What you get

- Upload or paste Python; get Semgrep-backed findings plus AI-assisted context
- Single **Docker** image: Next.js static export served by **FastAPI** on port `8000`
- **Cloud deploy**: primarily `terraform/aws` (AWS App Runner + ECR); Azure/GCP optional

## Stack

| Layer        | Tech                          |
| ------------ | ------------------------------- |
| Frontend     | Next.js (TypeScript), Tailwind |
| Backend      | Python 3.12, FastAPI, uv       |
| Analysis     | Semgrep, MCP, OpenAI Agents    |
| Infra        | Terraform (Azure, GCP, AWS)      |

## Prerequisites

- **Python 3.12+** and [uv](https://github.com/astral-sh/uv)
- **Node.js 20+** and npm
- **Docker** (optional, for container run)
- **Terraform** (optional, for cloud deploy)

## Environment

Create a `.env` in the repo root:

- `OPENAI_API_KEY` — OpenAI API access  
- `SEMGREP_APP_TOKEN` — Semgrep (Semgrep Cloud / App token as required by your setup)

## Run locally

**Backend** (port `8000`):

```bash
cd backend
uv sync
uv run server.py
```

**Frontend** (port `3000`, separate terminal):

```bash
cd frontend
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Run with Docker

From the repo root (with `.env` present):

```bash
docker build -t cyber-analyzer .
docker run --rm -p 8000:8000 --env-file .env cyber-analyzer
```

Open [http://localhost:8000](http://localhost:8000).

## Repo layout

```
├── backend/     # FastAPI app, MCP / agent wiring
├── frontend/    # Next.js UI (static export in production)
├── terraform/   # azure/, gcp/, aws/ — infra as code
├── scripts/     # deploy-aws.sh, destroy-aws.sh
├── Dockerfile   # Single-container production build
└── docs/        # workshop notes, aws.md, azure.md, …
```

## Cloud deploy

Terraform stacks live under `terraform/aws`, `terraform/azure`, and `terraform/gcp`.

For now, this repo’s **primary** supported cloud deployment is **AWS App Runner + ECR**:
- **AWS deploy guide:** [`docs/aws.md`](docs/aws.md)
- **Terraform summary:** [`terraform/README.md`](terraform/README.md)

Azure and GCP are included as optional later paths:
- Azure workshop guide: [`docs/workshop/week3/day1.part2.md`](docs/workshop/week3/day1.part2.md)
- GCP workshop guide: [`docs/workshop/week3/day2.part2.md`](docs/workshop/week3/day2.part2.md)
- Azure resource list: [`docs/azure.md`](docs/azure.md)

### AWS deployment (recommended)

#### High-level AWS architecture (ASCII)

```text
Developer machine (Terraform + Docker)
  |
  |  docker build (linux/amd64) + docker push
  v
Amazon ECR (private repo: cyber-analyzer)
  |
  |  image pull on deploy / resume
  v
AWS App Runner service (public HTTPS)
  - runs container on port 8000 (FastAPI + static Next.js)
  - env vars: OPENAI_API_KEY, SEMGREP_APP_TOKEN
  - health check: /health
```

#### Deploy with scripts (recommended)

From the repo root:

```bash
aws sts get-caller-identity
docker ps
./scripts/deploy-aws.sh
```

It prints the **Service URL** at the end.

#### Pause instead of deleting (recommended)

Because of AWS App Runner availability changes for new customers after Apr 30, 2026, this repo’s default cleanup action is to **pause** the service (compute to zero) so it can be resumed later:

```bash
./scripts/destroy-aws.sh
```

Resume later:

```bash
aws apprunner resume-service --service-arn "$(cd terraform/aws && terraform output -raw apprunner_service_arn)"
```

#### Validate deploy / cleanup

```bash
./scripts/check-aws-deploy.sh
./scripts/check-aws-cleanup.sh          # paused-only (default)
./scripts/check-aws-cleanup.sh destroyed
```

---

### Azure (Container Apps)

From the **repo root**, load API keys into your shell (macOS / Linux):

```bash
export $(grep -v '^#' .env | xargs)
```

**1. Initialize Terraform and use the Azure workspace** (first time, from `terraform/azure`):

```bash
cd terraform/azure
terraform init

terraform workspace new azure   # only if workspace does not exist yet
terraform workspace select azure
terraform workspace show        # should print: azure
```

**2. Log in to Azure** (browser flow):

```bash
az login
az account show
```

Register **Microsoft.App** and **Microsoft.OperationalInsights** once per subscription if you have not already (see the Week 3 guide). Wait until both show `Registered` before applying.

**3. Plan and deploy** (still in `terraform/azure`):

```bash
terraform plan \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"

terraform apply \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"
```

**4. Open the app** (HTTPS URL from Terraform):

```bash
terraform output app_url
```

#### Rebuild and redeploy

Terraform may not rebuild the image when only application code changes. Either **bump the image tag** and apply again:

```bash
terraform apply \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN" \
  -var="docker_image_tag=v2"
```

…or **`terraform taint`** the Docker image resources as described in [`docs/workshop/week3/day1.part2.md`](docs/workshop/week3/day1.part2.md), then run `terraform apply` again with the same `-var` arguments as above.

#### Clean up (important for cost)

When you are finished with the lab, destroy everything Terraform created (from `terraform/azure`):

```bash
terraform destroy \
  -var="openai_api_key=$OPENAI_API_KEY" \
  -var="semgrep_app_token=$SEMGREP_APP_TOKEN"
```

Confirm with `yes` when prompted. You can keep an empty resource group in Azure at no charge, or delete it with `az group delete` if you no longer need it.

### GCP

Use `terraform/gcp` with your GCP credentials and variables; see [`docs/workshop/week3/day2.part2.md`](docs/workshop/week3/day2.part2.md).
