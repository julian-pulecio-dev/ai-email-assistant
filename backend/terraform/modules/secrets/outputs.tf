output "google_oauth_secret_arn" {
  value = data.aws_secretsmanager_secret.google_oauth.arn
}

output "google_oauth_secret_name" {
  value = data.aws_secretsmanager_secret.google_oauth.name
}

output "session_jwt_secret_arn" {
  value = aws_secretsmanager_secret.session_jwt.arn
}

output "session_jwt_secret_name" {
  value = aws_secretsmanager_secret.session_jwt.name
}
