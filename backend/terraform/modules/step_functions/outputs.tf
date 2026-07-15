output "state_machine_arn" {
  value = aws_sfn_state_machine.process_new_email.arn
}

output "state_machine_name" {
  value = aws_sfn_state_machine.process_new_email.name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.state_machine.name
}

output "pipe_arn" {
  value = aws_pipes_pipe.new_emails_to_state_machine.arn
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
