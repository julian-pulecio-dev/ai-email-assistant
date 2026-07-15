variable "project_name" {
  description = "Short name used as a prefix for all resources."
  type        = string
  default     = "google-auth-app"
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "google_oauth_secret_name" {
  description = <<-EOT
    Name of the PRE-EXISTING AWS Secrets Manager secret that stores the Google
    OAuth credentials. This secret is NOT created by Terraform - create it
    yourself (see root README) before running `terraform apply`. Expected
    JSON body: { "client_id": "...", "client_secret": "..." }.
  EOT
  type        = string
}

variable "allowed_origins" {
  description = "List of frontend origins allowed by API Gateway CORS (e.g. http://localhost:5173)."
  type        = list(string)
  default     = ["http://localhost:5173"]
}

variable "session_jwt_ttl_minutes" {
  description = "Lifetime, in minutes, of the session JWT issued after a successful Google login."
  type        = number
  default     = 60
}

variable "lambda_runtime" {
  description = "Python runtime used by all Lambda functions."
  type        = string
  default     = "python3.12"
}
