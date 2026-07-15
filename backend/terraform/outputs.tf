output "api_endpoint" {
  description = "Base URL of the deployed HTTP API. Use as VITE_API_BASE_URL in the frontend."
  value       = module.api_gateway.api_endpoint
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "labels_table_name" {
  value = module.dynamodb.labels_table_name
}

output "session_jwt_secret_name" {
  description = "Secrets Manager secret name holding the auto-generated session JWT signing key."
  value       = module.secrets.session_jwt_secret_name
}

output "aws_region" {
  value = data.aws_region.current.name
}

output "new_emails_queue_url" {
  description = "SQS queue that check_new_emails publishes new-email events to."
  value       = module.sqs.queue_url
}

output "new_emails_dlq_url" {
  description = "Dead-letter queue for new_emails_queue_url."
  value       = module.sqs.dlq_url
}

output "process_new_email_state_machine_arn" {
  description = "Step Functions state machine that fetches + classifies each new email."
  value       = module.step_functions.state_machine_arn
}

output "process_new_email_alerts_topic_arn" {
  description = "SNS topic notified when a process_new_email execution fails. Subscribe to it if you didn't set alert_email."
  value       = module.step_functions.alerts_topic_arn
}
