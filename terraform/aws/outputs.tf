output "service_url" {
  value       = "https://${aws_apprunner_service.app.service_url}"
  description = "HTTPS URL of the App Runner service (trailing slash may be required for some static routes)"
}

output "apprunner_service_arn" {
  value       = aws_apprunner_service.app.arn
  description = "ARN of the App Runner service"
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.app.repository_url
  description = "ECR repository URL (without tag)"
}

output "ecr_repository_name" {
  value       = aws_ecr_repository.app.name
  description = "ECR repository name"
}

output "aws_region" {
  value       = var.aws_region
  description = "AWS region used by this Terraform stack"
}
