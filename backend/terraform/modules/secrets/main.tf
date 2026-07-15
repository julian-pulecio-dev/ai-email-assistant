# Pre-existing secret holding the Google OAuth client_id/client_secret.
# Terraform never creates or writes to this secret - it must exist already
# (see root README for the AWS CLI command to create it).
data "aws_secretsmanager_secret" "google_oauth" {
  name = var.google_oauth_secret_name
}

# Secret used to sign/verify our own session JWTs. Fully managed by Terraform
# since it is an application secret, not a Google credential.
resource "random_password" "session_jwt_secret" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "session_jwt" {
  name = "${var.project_name}-${var.environment}-session-jwt-secret"

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "session_jwt" {
  secret_id     = aws_secretsmanager_secret.session_jwt.id
  secret_string = jsonencode({ secret = random_password.session_jwt_secret.result })
}
