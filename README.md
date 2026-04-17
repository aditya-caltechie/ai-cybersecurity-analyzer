# Cybersecurity Analyzer

Web app that analyzes Python code for security issues using **Semgrep** (static analysis) and an **OpenAI Agents** workflow with the **Semgrep MCP** server. Includes **Terraform** configs for **Azure Container Apps** and **GCP Cloud Run**.

![Course image](assets/cyber.png)

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
- **Multi-cloud**: deploy with `terraform/azure` and `terraform/gcp`

## Stack

| Layer        | Tech                          |
| ------------ | ------------------------------- |
| Frontend     | Next.js (TypeScript), Tailwind |
| Backend      | Python 3.12, FastAPI, uv       |
| Analysis     | Semgrep, MCP, OpenAI Agents    |
| Infra        | Terraform (Azure, GCP)         |

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
├── terraform/   # azure/, gcp/ — infra as code
├── Dockerfile   # Single-container production build
└── assets/      # Images, etc.
```

## Cloud deploy

Use the Terraform stacks under `terraform/azure` and `terraform/gcp` after configuring the respective provider credentials and variables for your subscription/project.
