# Build frontend
FROM node:20-alpine AS frontend-build
WORKDIR /app
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ .
RUN npm run build

# Production image
FROM python:3.12-slim
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv for Python package management
RUN pip install uv

# Copy Python dependencies and install
COPY backend/pyproject.toml backend/uv.lock* ./
RUN uv sync --frozen
RUN uv tool install semgrep
# Copy backend source
COPY backend/ ./

# Copy Next.js static export (from 'out' directory)
COPY --from=frontend-build /app/out ./static

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Expose port for Cloud Run / Azure Container Instances
EXPOSE 8000


# Start the FastAPI server
CMD ["uv", "run", "uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]

# NOTE:
# ------------------------------------------------------------
# Here Python + baked-in static frontend, which matches the project’s goal: one 
# port (8000), one service for Azure Container Apps / Cloud Run, no separate frontend 
# container or reverse proxy required.

# Summary: Frontend and backend stay separate in source and in dev; the multi-stage
# Dockerfile is how you compile the JS app and then ship its static output next to the 
# FastAPI app so production is a single deployable unit.
# ------------------------------------------------------------

# Why two stages?
# Stage 1 (node:20-alpine) exists only to build the Next.js app. Compiling TypeScript/React 
# and running next build needs Node and npm. That stage produces a folder of plain static
#  files (your setup uses static export, so that folder is out/).

# Stage 2 (python:3.12-slim) is the runtime image. In production you only need something 
# that can run FastAPI/Uvicorn and serve files. You do not need a running Node process 
# if the UI is already built to HTML/JS/CSS.
# ------------------------------------------------------------