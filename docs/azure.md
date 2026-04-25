# Azure in this project (Week 3)

This page ties together **what Azure is**, **how the course uses it**, and **every Azure-related piece** involved in deploying the Cybersecurity Analyzer. It is based on the Week 3 workshop docs under [`docs/workshop/week3/`](./workshop/week3/), especially Day 1, and on the live Terraform code in [`terraform/azure/`](../terraform/azure/).

> **Scope:** [Day 1 Part 0](./workshop/week3/day1.part0.md) and [Part 1](./workshop/week3/day1.part1.md) prepare your machine and **Azure subscription** (account, billing, resource group, CLI). [Day 1 Part 2](./workshop/week3/day1.part2.md) deploys the app. **Day 2** in this workshop ([Part 1](./workshop/week3/day2.part1.md), [Part 2](./workshop/week3/day2.part2.md)) is **Google Cloud Platform**, not Azure—use this document when you want the Azure-only picture.

---

## Azure fundamentals (how to think about the platform)

### Hierarchy (from the workshop)

```text
Microsoft account (your sign-in)
  └── Subscription          ← billing boundary (credits, invoices)
        └── Resource group   ← logical folder (e.g. cyber-analyzer-rg) + default region
              └── Resources ← services you create (registry, logs, container app, …)
```

- **Subscription:** Where usage is billed and policies can apply.
- **Resource group:** Groups related resources for one project or environment. The Terraform stack in this repo **expects an existing resource group** (you create it in the portal first, per Part 1).
- **Region:** Each resource is deployed to an Azure region (e.g. **East US**). Keep related resources in the same region when possible.

### Resource providers (not “apps,” but required to create resources)

Before Terraform can create Container Apps and Log Analytics resources, the subscription must register the right **resource providers** (one-time per subscription, free to register):

| Namespace | Used for |
|-----------|----------|
| **Microsoft.App** | Azure Container Apps (including **managed environments** and **container apps**). |
| **Microsoft.OperationalInsights** | **Log Analytics workspaces** (monitoring backend for many Azure services). |

Commands from the workshop:

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
```

Wait until `az provider show ... --query registrationState` returns **Registered** for both.

### Cost and operations (portal / subscription level)

These are **not** separate resources inside your resource group in the same way as a VM, but they matter for the lab:

| Concept | Role |
|---------|------|
| **Cost Management + Billing** | View spend, **cost analysis**, budgets. Part 1 walks through creating a **budget** with email alerts. |
| **Azure Portal** | Web UI at [https://portal.azure.com](https://portal.azure.com) to browse subscriptions, resource groups, and resources. |
| **Azure CLI (`az`)** | Command-line tool for login, provider registration, and commands such as `az containerapp logs show`. |

---

## End-to-end flow (lab → running app)

```text
  You (local)
      |
      | 1. Create RG, budget, az login          [Day 1 Part 1 — portal + CLI]
      v
  Subscription (providers registered)
      |
      | 2. terraform init / workspace azure     [Day 1 Part 2]
      | 3. terraform apply (+ keys from .env)
      v
  ┌─────────────────────────────────────────────────────────────────┐
  │ Resource group (e.g. cyber-analyzer-rg)                         │
  │   • Azure Container Registry (ACR)                              │
  │   • Log Analytics workspace                                     │
  │   • Container Apps Environment                                  │
  │   • Container App (your image, env vars, public HTTPS)          │
  └─────────────────────────────────────────────────────────────────┘
      |
      | Docker build/push happens from your laptop via Terraform Docker provider
      v
  Internet ──HTTPS──▶ Container App FQDN (*.azurecontainerapps.io)
```

---

## Azure resources and services used by this project

Below is a **complete checklist** of what the Week 3 Azure path touches, split into “created manually / subscription,” “Terraform-managed,” and “external.”

### 1. Created in the portal before Terraform (workshop Part 1)

| Item | Azure concept | Notes |
|------|----------------|-------|
| **Resource group** | `Microsoft.Resources/resourceGroups` | Example name: **`cyber-analyzer-rg`**. Terraform uses a **data source** to reference it; it does not create the RG. |
| **Budget + alerts** (optional but recommended) | Cost Management | Scoped to subscription or resource group; sends email at thresholds. |

### 2. Created by Terraform (`terraform/azure/main.tf`)

These are the **billable / visible** Azure resources the stack provisions (names follow `var.project_name`, default **`cyber-analyzer`**):

| # | Resource type (portal / ARM) | Terraform resource | Typical name pattern | Purpose |
|---|------------------------------|--------------------|----------------------|---------|
| 1 | **Azure Container Registry** | `azurerm_container_registry` | Letters/digits only + random suffix (e.g. `cyberanalyzerm44y3`) | Stores the **Docker image** for the app. **SKU: Basic**. **Admin user** enabled so the Container App can pull with username/password (lab simplicity). |
| 2 | **Log Analytics workspace** | `azurerm_log_analytics_workspace` | `{project_name}-logs` → **`cyber-analyzer-logs`** | Receives **diagnostics and logs** from the Container Apps environment. **SKU PerGB2018**, retention **30 days** (as in Terraform). |
| 3 | **Container Apps Environment** | `azurerm_container_app_environment` | `{project_name}-env` → **`cyber-analyzer-env`** | **Shared boundary** for networking and observability wiring; hosts one or more **Container Apps**. Linked to the Log Analytics workspace. |
| 4 | **Container App** | `azurerm_container_app` | **`cyber-analyzer`** (same as `project_name`) | Runs your **container**: FastAPI + static UI on port **8000**, **external ingress**, scale **min 0 / max 1**, **1.0 CPU**, **2.0 Gi** memory (Semgrep needs the RAM). **Secrets:** registry password as a Container App **secret**; **env** vars for `OPENAI_API_KEY`, `SEMGREP_APP_TOKEN`, etc. |

**Terraform-only (not Azure):** the **Docker** and **random** providers build/push the image and generate a unique ACR name suffix. Those do not appear as extra rows in the Azure portal.

### 3. Explicitly *not* used in this repo’s Azure Terraform

The app still talks to **OpenAI** and **Semgrep** over the public internet using keys you pass in; there is **no** separate Azure resource for:

- **Azure OpenAI Service**
- **Azure Key Vault** (keys are injected as container environment variables for this lab)
- **Application Insights** as a standalone resource (Log Analytics is the primary logging sink wired here)
- **Virtual networks** you manage (the Container Apps environment uses **platform-managed** networking appropriate for the managed environment SKU)

If the course later adds Key Vault or Azure OpenAI, those would appear as additional resource types in Terraform.

---

## How the pieces connect at runtime

```text
                    ┌──────────────────────────────────────┐
                    │  Azure Container Registry (ACR)      │
                    │  Image: …/cyber-analyzer:<tag>       │
                    └──────────────────┬───────────────────┘
                                       │ pull on deploy / revision
                                       v
  Browser  ──HTTPS:443──▶  ┌───────────────────────────────┐
                           │  Container App                │
                           │  ingress → container :8000    │
                           └───────────────┬───────────────┘
                                           │
                           ┌───────────────▼────────────────┐
                           │  Container Apps Environment    │
                           └───────────────┬────────────────┘
                                           │ diagnostics
                           ┌───────────────▼────────────────┐
                           │  Log Analytics workspace       │
                           └────────────────────────────────┘

  Container outbound (not drawn): HTTPS to api.openai.com, Semgrep services, etc.
```

---

## Commands you use against Azure (from the workshop)

| Goal | Command / action |
|------|-------------------|
| Sign in | `az login` |
| Confirm subscription | `az account show` |
| Register providers | `az provider register --namespace Microsoft.App` (and `Microsoft.OperationalInsights`) |
| Live logs | `az containerapp logs show --name cyber-analyzer --resource-group cyber-analyzer-rg --follow` |
| List RG resources after destroy | `az resource list --resource-group cyber-analyzer-rg --output table` |
| Optional: delete empty RG | `az group delete --name cyber-analyzer-rg --yes` |

Terraform: `terraform plan` / `terraform apply` / `terraform destroy` from **`terraform/azure`**, with `-var` for API keys as in [Day 1 Part 2](./workshop/week3/day1.part2.md).

---

## Workshop vs Terraform naming

- The workshop sometimes shows a registry name like **`cyberanalyzeracr`** as an example. In **this repository**, ACR names are **globally unique** and built as a shortened base name plus a **random suffix** (see `local.acr_name` in `terraform/azure/main.tf`).
- Container App, environment, and Log Analytics names follow **`${project_name}`** defaults: **`cyber-analyzer`**, **`cyber-analyzer-env`**, **`cyber-analyzer-logs`**.

---

## Further reading in this repo

| Document | Content |
|----------|---------|
| [docs/workshop/week3/day1.part1.md](./workshop/week3/day1.part1.md) | Account, subscription, RG, budget, Azure CLI |
| [docs/workshop/week3/day1.part2.md](./workshop/week3/day1.part2.md) | Full deploy, verify, destroy, scaling and cost notes |
| [docs/overview.md](./overview.md) | High-level architecture and Azure vs AWS comparison |
| [docs/demo.md](./demo.md) | Demo narrative and portal screenshots |
| [README.md](../README.md) | Quick Terraform commands for Azure |
| [docs/aws.md](./aws.md) | Same app on **AWS App Runner** + **ECR** |

---

## Summary table: “everything Azure” for Week 3 Day 1

| Layer | What |
|-------|------|
| **Identity / access** | Microsoft account, subscription, `az login` |
| **Governance / cost** | Resource group, Cost Management budgets (recommended) |
| **Platform enablement** | Resource providers **Microsoft.App**, **Microsoft.OperationalInsights** |
| **Compute + HTTP** | **Container App** (serverless container with ingress) |
| **Compute boundary** | **Container Apps Environment** |
| **Images** | **Azure Container Registry** (Basic) |
| **Observability** | **Log Analytics workspace** |
| **IaC** | Terraform **azurerm** + **docker** providers under `terraform/azure/` |

Together, these are all the **Azure cloud resources and services** this project’s Week 3 materials and code rely on for the Azure deployment path.
