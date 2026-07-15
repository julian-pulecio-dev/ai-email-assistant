output "queue_url" {
  value = aws_sqs_queue.new_emails.id
}

output "queue_arn" {
  value = aws_sqs_queue.new_emails.arn
}

output "dlq_url" {
  value = aws_sqs_queue.new_emails_dlq.id
}

output "dlq_arn" {
  value = aws_sqs_queue.new_emails_dlq.arn
}
