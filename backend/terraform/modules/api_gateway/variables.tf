variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "allowed_origins" {
  type = list(string)
}

variable "google_login_function_name" {
  type = string
}

variable "google_login_invoke_arn" {
  type = string
}

variable "get_me_function_name" {
  type = string
}

variable "get_me_invoke_arn" {
  type = string
}

variable "authorizer_function_name" {
  type = string
}

variable "authorizer_invoke_arn" {
  type = string
}

variable "gmail_messages_function_name" {
  type = string
}

variable "gmail_messages_invoke_arn" {
  type = string
}
