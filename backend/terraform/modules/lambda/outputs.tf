output "google_login_function_name" {
  value = aws_lambda_function.google_login.function_name
}

output "google_login_invoke_arn" {
  value = aws_lambda_function.google_login.invoke_arn
}

output "get_me_function_name" {
  value = aws_lambda_function.get_me.function_name
}

output "get_me_invoke_arn" {
  value = aws_lambda_function.get_me.invoke_arn
}

output "authorizer_function_name" {
  value = aws_lambda_function.authorizer.function_name
}

output "authorizer_invoke_arn" {
  value = aws_lambda_function.authorizer.invoke_arn
}

output "gmail_messages_function_name" {
  value = aws_lambda_function.gmail_messages.function_name
}

output "gmail_messages_invoke_arn" {
  value = aws_lambda_function.gmail_messages.invoke_arn
}

output "check_new_emails_function_name" {
  value = aws_lambda_function.check_new_emails.function_name
}

output "fetch_gmail_message_function_name" {
  value = aws_lambda_function.fetch_gmail_message.function_name
}

output "fetch_gmail_message_function_arn" {
  value = aws_lambda_function.fetch_gmail_message.arn
}

output "classify_email_labels_function_name" {
  value = aws_lambda_function.classify_email_labels.function_name
}

output "classify_email_labels_function_arn" {
  value = aws_lambda_function.classify_email_labels.arn
}

output "apply_gmail_labels_function_name" {
  value = aws_lambda_function.apply_gmail_labels.function_name
}

output "apply_gmail_labels_function_arn" {
  value = aws_lambda_function.apply_gmail_labels.arn
}

output "labels_function_name" {
  value = aws_lambda_function.labels.function_name
}

output "labels_invoke_arn" {
  value = aws_lambda_function.labels.invoke_arn
}

output "record_processing_error_function_arn" {
  value = aws_lambda_function.record_processing_error.arn
}
