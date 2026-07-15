variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "lambda_runtime" {
  type = string
}

variable "lambdas_source_dir" {
  description = "Absolute path to backend/lambdas (contains google_login/, get_me/, authorizer/ handler source)."
  type        = string
}

variable "layer_build_dir" {
  description = "Absolute path to the directory produced by build_layer.ps1 (backend/terraform/build/layer), containing a python/ subfolder."
  type        = string
}

variable "dynamodb_table_name" {
  type = string
}

variable "dynamodb_table_arn" {
  type = string
}

variable "labels_table_name" {
  type = string
}

variable "labels_table_arn" {
  type = string
}

variable "processing_errors_table_name" {
  type = string
}

variable "processing_errors_table_arn" {
  type = string
}

variable "google_oauth_secret_arn" {
  type = string
}

variable "google_oauth_secret_name" {
  type = string
}

variable "session_jwt_secret_arn" {
  type = string
}

variable "session_jwt_secret_name" {
  type = string
}

variable "session_jwt_ttl_minutes" {
  type = number
}

variable "new_emails_queue_url" {
  description = "URL of the SQS queue that new-email events are published to."
  type        = string
}

variable "new_emails_queue_arn" {
  description = "ARN of the SQS queue that new-email events are published to."
  type        = string
}

variable "new_emails_dlq_arn" {
  description = "ARN of new_emails' dead-letter queue. record_dead_letter consumes it."
  type        = string
}

variable "gmail_history_check_schedule_expression" {
  description = "EventBridge schedule expression controlling how often check_new_emails runs."
  type        = string
  default     = "rate(5 minutes)"
}

variable "bedrock_model_id" {
  description = "Bedrock foundation model id used by classify_email_labels. Must support multimodal (image/document) input to classify attachments - Nova Micro is text-only."
  type        = string
  default     = "amazon.nova-lite-v1:0"
}
