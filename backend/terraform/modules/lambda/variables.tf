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
