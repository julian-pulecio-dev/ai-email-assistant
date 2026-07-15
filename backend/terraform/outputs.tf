output "api_endpoint" {
  description = "Base URL of the deployed HTTP API. Use as VITE_API_BASE_URL in the frontend."
  value       = module.api_gateway.api_endpoint
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "session_jwt_secret_name" {
  description = "Secrets Manager secret name holding the auto-generated session JWT signing key."
  value       = module.secrets.session_jwt_secret_name
}

output "aws_region" {
  value = data.aws_region.current.name
}
