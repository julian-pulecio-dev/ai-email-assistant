output "table_name" {
  value = aws_dynamodb_table.users.name
}

output "table_arn" {
  value = aws_dynamodb_table.users.arn
}

output "labels_table_name" {
  value = aws_dynamodb_table.labels.name
}

output "labels_table_arn" {
  value = aws_dynamodb_table.labels.arn
}

output "processing_errors_table_name" {
  value = aws_dynamodb_table.processing_errors.name
}

output "processing_errors_table_arn" {
  value = aws_dynamodb_table.processing_errors.arn
}
