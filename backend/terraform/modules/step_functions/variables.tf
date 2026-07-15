variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "fetch_gmail_message_function_arn" {
  type = string
}

variable "classify_email_labels_function_arn" {
  type = string
}

variable "apply_gmail_labels_function_arn" {
  type = string
}

variable "record_processing_error_function_arn" {
  type = string
}

variable "new_emails_queue_arn" {
  description = "ARN of the SQS queue (populated by check_new_emails) that feeds this state machine via an EventBridge Pipe."
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "alert_email" {
  description = "Email address notified when process_new_email executions fail. Leave empty to skip the subscription (the alarm/topic are still created)."
  type        = string
  default     = ""
}
