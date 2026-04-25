# AWS stack: how `terraform/aws` wires services together

This document describes **which AWS services** the Cybersecurity Analyzer AWS deployment uses, **which Terraform files** define them, and **how `main.tf` connects** data sources, IAM, ECR, the local image build, and App Runner.

For deploy commands and prerequisites, see [`aws.md`](aws.md).

---

## Terraform file map

| File | Responsibility |
|------|----------------|
| [`terraform/aws/versions.tf`](../terraform/aws/versions.tf) | Terraform and **hashicorp/aws** provider version constraints; declares `provider "aws"` with `region = var.aws_region`. |
| [`terraform/aws/variables.tf`](../terraform/aws/variables.tf) | Input variables: region, service name, secrets (`openai_api_key`, `semgrep_app_token`), image tag, optional `docker_host`. |
| [`terraform/aws/outputs.tf`](../terraform/aws/outputs.tf) | Outputs after apply: HTTPS `service_url`, App Runner ARN, ECR URL/name, region. |
| [`terraform/aws/main.tf`](../terraform/aws/main.tf) | All **resources**: ECR repo, IAM role for ECR pull, `null_resource` Docker build/push, App Runner autoscaling config, App Runner service. |

There is **no** separate `backend.tf` in this folder by default; backend is whatever you configure locally (often local state unless you add a remote backend).

---

## End-to-end flow (ASCII)

Traffic and image flow from your machine to users:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│  Your machine                                                           │
│  terraform apply  +  Docker CLI (see null_resource in main.tf)        │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
        1) aws ecr get-login-password | docker login
        2) docker build --platform linux/amd64  (repo root Dockerfile)
        3) docker push <account>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>
                                │
                                v
┌─────────────────────────────────────────────────────────────────────────┐
│  Amazon ECR                                                             │
│  Private image repository (name = service_name, default cyber-analyzer)│
│  Scan on push enabled                                                   │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
        App Runner service account uses IAM access role (below)
        to pull image on create / manual deployment
                                │
                                v
┌─────────────────────────────────────────────────────────────────────────┐
│  AWS App Runner                                                         │
│  Runs container: port 8000, 1 vCPU, 2 GiB                               │
│  Health check: HTTP GET /health                                          │
│  Public HTTPS default domain (*.awsapprunner.com)                       │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                v
                          Internet / browser
```

IAM sits **beside** the pull path (not in the HTTP request path):

```text
┌──────────────────────────┐         assume role          ┌──────────────────────────┐
│  IAM role                │  <──────────────────────────  │  build.apprunner.        │
│  (trust: App Runner      │                                 │  amazonaws.com           │
│   build service)         │  attach                         └──────────────────────────┘
│                          │------> AWSAppRunnerServicePolicyForECRAccess
└───────────┬──────────────┘
            │
            │  access_role_arn in apprunner source_configuration
            v
    App Runner can authenticate to ECR and pull the image
```

---

## What `main.tf` does, block by block

### 1. Data sources (read-only)

- **`data.aws_caller_identity.current`** — resolves your **AWS account ID** so Terraform can build the ECR registry hostname (`<account>.dkr.ecr.<region>.amazonaws.com`).
- **`data.aws_ecr_authorization_token.token`** — declared in this module for completeness; the **actual** login in the build step uses `aws ecr get-login-password` in the `local-exec` script (same idea).

**`locals.ecr_registry_host`** — convenience string derived from account ID + region for `docker login`.

### 2. `aws_ecr_repository.app`

Creates the **private** container registry where the application image lives.

- Name defaults to `var.service_name` (default **`cyber-analyzer`**).
- **`force_delete = true`** — allows repository deletion on `terraform destroy` even if tags remain (useful for labs).
- **Scan on push** — ECR basic scanning after each push.

### 3. IAM: `aws_iam_role.apprunner_access` + policy attachment

App Runner does not use your laptop’s credentials at runtime. It needs an **IAM role** that:

- **Trust policy** allows **`build.apprunner.amazonaws.com`** to assume the role (this is the App Runner **image pull / deployment** side, as configured in AWS’s ECR access pattern for App Runner).
- **`AWSAppRunnerServicePolicyForECRAccess`** (AWS-managed) is attached so that role can **pull images from ECR**.

In `aws_apprunner_service.app`, **`authentication_configuration.access_role_arn`** points at this role so App Runner can pull **`image_identifier`** from ECR.

### 4. `null_resource.build_and_push` (not an AWS API resource)

This is a **Terraform provisioner** that runs **on your machine** during apply:

1. Optionally sets **`DOCKER_HOST`** (passed from `scripts/deploy-aws.sh` via `docker context inspect`, so Docker Desktop on macOS matches Terraform’s expectation).
2. **`aws ecr get-login-password`** piped to **`docker login`** against the ECR registry host.
3. **`docker build --platform linux/amd64`** from the **repository root** (`path.module/../..` → project root where the **`Dockerfile`** lives).
4. **`docker push`** to `repository_url:docker_image_tag`.

**When it re-runs:** the `null_resource` **triggers** include the full image reference string and a **hash of the Dockerfile**. Changing application source **without** changing the Dockerfile **does not** retrigger by default—bump **`docker_image_tag`** or touch the Dockerfile / taint the resource if you need a guaranteed rebuild (same pattern as other clouds in this repo).

### 5. `aws_apprunner_auto_scaling_configuration_version.app`

Defines **concurrency and instance bounds** for the service:

- **`max_concurrency`** 50.
- **`min_size` / `max_size`** both **1** (AWS provider requires `min_size >= 1`; this stack keeps **one** instance for predictable Semgrep memory use).

The App Runner service references this via **`auto_scaling_configuration_arn`**.

### 6. `aws_apprunner_service.app`

The **runtime** service users hit:

| Setting | Purpose |
|--------|---------|
| **`source_configuration.image_repository`** | Image from ECR; **`image_identifier`** = repo URL + tag. |
| **`image_configuration.port`** | **8000** — must match the container (FastAPI + static frontend). |
| **`runtime_environment_variables`** | `OPENAI_API_KEY`, `SEMGREP_APP_TOKEN`, `ENVIRONMENT=production`, `PYTHONUNBUFFERED=1`. |
| **`auto_deployments_enabled = false`** | Pushing a **new** image tag to ECR does **not** auto-roll the service; you start a deployment manually or change infra so Terraform updates the service. |
| **`instance_configuration`** | **1024** CPU units (1 vCPU), **2048** MB RAM (**2 GiB** for Semgrep rule load). |
| **`health_check_configuration`** | HTTP **`/health`**, 20s interval, 10s timeout, 5 unhealthy before fail. |

**`depends_on`**: ensures the ECR pull role is attached and the **`null_resource`** (build/push) completed **before** App Runner tries to create/update with that image reference.

---

## Dependency order (simplified)

```text
aws_caller_identity (data)
        │
        └──> locals.ecr_registry_host
        │
aws_ecr_repository.app
        │
        ├──────────────────────────────────────┐
        │                                      │
        v                                      v
null_resource.build_and_push          aws_iam_role.apprunner_access
        │                                      │
        │                                      v
        │                              aws_iam_role_policy_attachment
        │                                      │
        └──────────────────┬───────────────────┘
                           v
              aws_apprunner_auto_scaling_configuration_version.app
                           │
                           v
                   aws_apprunner_service.app
```

---

## How the deploy script ties in

[`scripts/deploy-aws.sh`](../scripts/deploy-aws.sh) (repo root):

1. Loads **`.env`** and exports variables.
2. Computes **`DOCKER_HOST`** from `docker context inspect` and passes **`docker_host`** into Terraform (matches `main.tf` provisioner).
3. Runs **`terraform init`**, selects workspace **`aws`**.
4. Optionally **resumes** a **PAUSED** App Runner service via AWS CLI instead of applying.
5. Otherwise **`terraform plan`** / **`terraform apply`** with **`-var` for secrets and docker_host** (secrets never need to live in `.tf` files).

Outputs printed at the end come from **`outputs.tf`**, especially **`service_url`**.

---

## Outputs (what connects to “the link”)

From [`outputs.tf`](../terraform/aws/outputs.tf):

- **`service_url`** — `https://` + App Runner’s **`service_url`** attribute (default domain).
- **`apprunner_service_arn`** — for CLI (`describe-service`, pause/resume) and support tickets.
- **`ecr_repository_url`** / **`ecr_repository_name`** — for manual `docker tag` / `docker push` or debugging pulls.

---

## What is intentionally *not* in `main.tf`

- **No VPC** — App Runner manages network edge; no ALB/NLB resources in this stack.
- **No Secrets Manager** — secrets are **container environment variables** for simplicity (aligns with lab-style Azure/GCP stacks here); production hardening could move to Secrets Manager + execution role.
- **No Route 53 / custom domain** — you get the default **`*.awsapprunner.com`** hostname unless you extend the stack.

---

## Related reading

- [`docs/aws.md`](aws.md) — account setup, apply/destroy, pause vs delete, troubleshooting table.
- [`terraform/README.md`](../terraform/README.md) — multi-cloud Terraform overview.
