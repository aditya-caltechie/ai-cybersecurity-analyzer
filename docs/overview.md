# Week 3 Day 1: What You Are Building (Parts 0–2)

This document summarizes the Week 3 Day 1 guides (Parts 0, 1, and 2): local app behavior, Azure account prep, and Terraform deployment to **Azure Container Apps**. It includes a high-level ASCII architecture diagram and a concise **Azure vs AWS** comparison.

---

## What Is Happening (One Paragraph)

You run the **Cybersecurity Analyzer**: a **Next.js** frontend and **FastAPI** backend that call **OpenAI** for reasoning and launch **Semgrep** (via MCP) for static security scans. Locally you either run two processes (dev) or one **Docker** container (production-like). For cloud, **Terraform** provisions **Azure Container Registry (ACR)**, builds/pushes your image, creates a **Container Apps Environment** with **Log Analytics**, and runs a **Container App** that serves HTTP on a public URL. Secrets from `.env` are passed into Terraform as variables and injected into the running container as environment variables.

---

## High-Level Architecture (ASCII)

```
                                    END-TO-END
  ═══════════════════════════════════════════════════════════════════════════════════

  [ Student machine ]                    [ Microsoft Azure — same region as RG ]
  ┌─────────────────────┐              ┌────────────────────────────────────────-────┐
  │ Cursor / terminal   │              │ Subscription                                │
  │                     │              │   └── Resource Group: cyber-analyzer-rg     │
  │ .env (not in git)   │              │         ┌──────────────────────────────────┐│
  │ OPENAI_API_KEY      │──Terraform──▶│ ACR     │ Azure Container Registry         ││
  │ SEMGREP_APP_TOKEN   │   variables  │         │ (stores cyber-analyzer image)    ││
  │                     │              │         └──────────────▲───────────────────┘│
  │ Docker (local build)│──build/push──┼──────────────────--────┘                    │
  └──────────┬──────────┘              │         ┌──────────────────────────────────┐│
             │                         │         │ Log Analytics workspace          ││
             │                         │         │ (logs / metrics ingestion)       ││
             │                         │         └──────────────▲───────────────────┘│
             │                         │                        │                    │
             │                         │         ┌──────────────┴───────────────────┐│
             │                         │         │ Container Apps Environment       ││
             │                         │         │  + scaling / networking glue     ││
             │                         │         └──────────────▲───────────────────┘│
             │                         │                        │                    │
             │                         │         ┌──────────────┴───────────────────┐│
             │                         │         │ Container App: cyber-analyzer    ││
             │                         │         │  Image from ACR                  ││
             │                         │         │ CPU ~1 vCPU, RAM ~2 GiB (Semgrep)││
             │                         │         │  min replicas: 0 (scale to zero) ││
             │                         │         └──────────────▲───────────────────┘│
             │                         └────────────────────────┼────────────────────┘
             │                                                    │
             │                         HTTPS (public FQDN)        │
             └────────────────────────── Browser ─────────────────┘

  Inside the container (single process on port 8000):
  ┌──────────────────────────────────────────────────────────────────────────────┐
  │  FastAPI (API + static Next.js export)                                       │
  │    ├── /health                                                               │
  │    ├── /api/...  (analyze, etc.)                                             │
  │    └── OpenAI Agents SDK ──▶ OpenAI API                                      │
  │              └── spawns / talks to ──▶ Semgrep MCP (static scan)             │
  └──────────────────────────────────────────────────────────────────────────────┘
```

---

## Whole Flow in Steps

### Part 0 — Project, keys, local, Docker

1. **Clone and open** the repo in Cursor; note `frontend/`, `backend/`, `terraform/`.
2. **Semgrep account**: sign up at semgrep.dev, create an API token with **Agent (CI)** and **Web API** scopes.
3. **`.env` at repo root**: set `OPENAI_API_KEY` and `SEMGREP_APP_TOKEN` (never commit; `.gitignore` should exclude `.env`).
4. **Local dev (two terminals)**:
   - `cd backend && uv run server.py` → API on `http://127.0.0.1:8000`.
   - `cd frontend && npm install && npm run dev` → UI on `http://localhost:3000` (use localhost URL as documented).
5. **Smoke test**: upload `airline.py`, run **Analyze Code**; wait for OpenAI + Semgrep pipeline; review findings.
6. **Docker single container**: `docker build -t cyber-analyzer .` then `docker run ... -p 8000:8000 --env-file .env cyber-analyzer`; test at `http://localhost:8000` (API + static UI same origin).

### Part 1 — Azure account and guardrails

7. **Create Azure account** (free tier / student options per guide); note **subscription** as billing boundary.
8. **Understand hierarchy**: Account → **Subscription** → **Resource Group** (`cyber-analyzer-rg`) → resources (empty until Part 2).
9. **Cost management**: create a small **budget** with email alerts (e.g. 50% / 80% / 100%).
10. **Install Azure CLI**, run `az login`, verify subscription and resource group (`az account list`, `az group list`).

### Part 2 — Terraform deploy to Container Apps

11. **Export secrets to shell** from `.env` (Mac/Linux `export $(cat .env | xargs)` or PowerShell equivalent) so Terraform can receive `-var=...` without storing keys in `.tf` files.
12. **`cd terraform/azure`**, `terraform init`, create/select workspace `azure` (`terraform workspace new/select azure`).
13. **`az login`**, **`az account show`**; register **resource providers** (one-time per subscription): `Microsoft.App`, `Microsoft.OperationalInsights`; wait until state is **Registered**.
14. **`terraform plan`** then **`terraform apply`** with `-var="openai_api_key=..."` and `-var="semgrep_app_token=..."`; confirm with `yes`.
15. **What apply does** (high level): create ACR; **build image locally** via Terraform Docker provider; **push** to ACR; create Log Analytics; create Container Apps Environment; create Container App revision with env vars and resource limits (notably **~2 GiB RAM** for Semgrep).
16. **Get URL**: `terraform output app_url`; open in browser; test upload again.
17. **Observe**: Portal shows registry, logs workspace, environment, app; `az containerapp logs show ...` for live logs.
18. **Cleanup**: **`terraform destroy`** with same `-var` flags when finished; optionally delete empty resource group with `az group delete`.

---

## How This Differs from AWS (Conceptual Map)

| Concept | Azure (this lab) | Typical AWS mental model |
|--------|------------------|---------------------------|
| **Billing / scope** | **Subscription** is the main billing and policy boundary. | **Account** (and often **Organization**) with **Consolidated Billing**; subscriptions are not the same object as Azure subscriptions. |
| **Grouping** | **Resource Group** is a logical folder; region is chosen per resource but RG has a “home” region. | Often **Region** + **CloudFormation stack** or **Terraform state**; **Resource Groups** in AWS are tags-based (different meaning than Azure RG). |
| **Enable a service** | **Resource provider registration** (`Microsoft.App`, etc.) is explicit; must show **Registered** before create. | Most services are **available** if your principal has **IAM** permission; rarely a separate “register provider” step for core compute. |
| **Run serverless HTTP container** | **Azure Container Apps** (KEDA + Envoy-style ingress, scale to zero, managed environment). | Closest patterns: **AWS App Runner** (simplest), **Fargate** behind **ALB**, or **Lambda** + **Function URL** (different model if not container). |
| **Private container registry** | **Azure Container Registry (ACR)** | **Amazon ECR** |
| **Centralized logs** | **Log Analytics** workspace | **CloudWatch Logs** (log groups) |
| **IaC** | Terraform + **AzureRM** (+ Docker provider for build/push in this course) | Terraform + **AWS provider** (same idea; different resource names) |
| **HTTPS URL** | `*.azurecontainerapps.io` FQDN from platform | App Runner / API Gateway / ALB each has its own URL pattern |

**Takeaway:** The **application** architecture (browser → container → OpenAI + Semgrep) is the same you would run on AWS; the **platform** steps differ mainly in **subscription/RG/provider registration** naming and in picking **App Runner vs Fargate** instead of **Container Apps**.

---

## Operational Notes (from the guides)

- **Image rebuilds**: Terraform may not notice app code changes; use `terraform taint` on the Docker resources or bump `docker_image_tag` when documented.
- **Memory**: Semgrep rule load is heavy; **~2 GiB** in the Container App avoids SIGKILL during scan startup.
- **Scale to zero**: min replicas `0` reduces cost when idle; cold start on next request.

---

## Source Material

- `.week3/day1.part0.md` — local setup, Semgrep token, Docker
- `.week3/day1.part1.md` — Azure account, RG, budget, CLI
- `.week3/day1.part2.md` — Terraform deploy, providers, outputs, destroy
