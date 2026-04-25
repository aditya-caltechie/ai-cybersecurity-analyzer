# Cybersecurity Analyzer on AWS: ECR + App Runner (same container model as Azure/GCP).
# Reference architecture: single Docker image on port 8000, 1 vCPU / 2 GiB for Semgrep.

data "aws_caller_identity" "current" {}

data "aws_ecr_authorization_token" "token" {}

locals {
  ecr_registry_host = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

# -----------------------------------------------------------------------------
# Amazon ECR — private container registry
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "app" {
  name                 = var.service_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# -----------------------------------------------------------------------------
# IAM — role App Runner uses to pull images from ECR
# -----------------------------------------------------------------------------
resource "aws_iam_role" "apprunner_access" {
  name = "${var.service_name}-apprunner-ecr-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = var.service_name
  }
}

resource "aws_iam_role_policy_attachment" "apprunner_ecr" {
  role       = aws_iam_role.apprunner_access.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# -----------------------------------------------------------------------------
# Docker build/push
#
# The Terraform docker provider can be flaky on macOS and sometimes fails with
# "use of closed network connection" while pushing to ECR. To make this reliable,
# we use the Docker CLI + AWS CLI inside a local-exec step.
# -----------------------------------------------------------------------------
resource "null_resource" "build_and_push" {
  triggers = {
    image      = "${aws_ecr_repository.app.repository_url}:${var.docker_image_tag}"
    dockerfile = filesha256("${path.module}/../../Dockerfile")
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail

# Ensure we're using the same Docker daemon as your current context (macOS Docker Desktop).
DOCKER_HOST="${var.docker_host}"
export DOCKER_HOST

aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${local.ecr_registry_host}

docker build --platform linux/amd64 -t ${aws_ecr_repository.app.repository_url}:${var.docker_image_tag} ${path.module}/../..
docker push ${aws_ecr_repository.app.repository_url}:${var.docker_image_tag}
EOT
    interpreter = ["/bin/bash", "-lc"]
  }

  depends_on = [aws_ecr_repository.app]
}

# -----------------------------------------------------------------------------
# App Runner — managed HTTPS, runs the container
# -----------------------------------------------------------------------------
resource "aws_apprunner_auto_scaling_configuration_version" "app" {
  auto_scaling_configuration_name = "${var.service_name}-scaling"
  max_concurrency                 = 50
  # AWS provider requires min_size >= 1; App Runner still scales in/out with traffic within max_size.
  min_size = 1
  max_size = 1

  tags = {
    Name = var.service_name
  }
}

resource "aws_apprunner_service" "app" {
  service_name = var.service_name

  source_configuration {
    auto_deployments_enabled = false

    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_access.arn
    }

    image_repository {
      image_identifier      = "${aws_ecr_repository.app.repository_url}:${var.docker_image_tag}"
      image_repository_type = "ECR"

      image_configuration {
        port = "8000"
        runtime_environment_variables = {
          OPENAI_API_KEY    = var.openai_api_key
          SEMGREP_APP_TOKEN = var.semgrep_app_token
          ENVIRONMENT       = "production"
          PYTHONUNBUFFERED  = "1"
        }
      }
    }
  }

  instance_configuration {
    cpu    = "1024" # 1 vCPU
    memory = "2048" # 2 GB — required for Semgrep rule load (see CLAUDE.md / workshop)
  }

  health_check_configuration {
    protocol            = "HTTP"
    path                = "/health"
    interval            = 20
    timeout             = 10
    healthy_threshold   = 1
    unhealthy_threshold = 5
  }

  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.app.arn

  tags = {
    Name = var.service_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.apprunner_ecr,
    null_resource.build_and_push
  ]
}
