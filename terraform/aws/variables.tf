variable "aws_region" {
  description = "AWS region for ECR and App Runner (must support App Runner)"
  type        = string
  default     = "us-east-1"
}

variable "service_name" {
  description = "App Runner service name and ECR repository name (letters, numbers, hyphens)"
  type        = string
  default     = "cyber-analyzer"
}

variable "openai_api_key" {
  description = "OpenAI API key for the application"
  type        = string
  sensitive   = true
  default     = ""
}

variable "semgrep_app_token" {
  description = "Semgrep app token for security scanning"
  type        = string
  sensitive   = true
  default     = ""
}

variable "docker_image_tag" {
  description = "Docker image tag pushed to ECR"
  type        = string
  default     = "latest"
}

variable "docker_host" {
  description = "Optional Docker daemon host (e.g. unix:///Users/<you>/.docker/run/docker.sock). Leave empty to use provider default."
  type        = string
  default     = ""
}
