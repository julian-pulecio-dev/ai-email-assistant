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
