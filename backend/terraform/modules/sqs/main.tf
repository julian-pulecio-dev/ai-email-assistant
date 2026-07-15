locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_sqs_queue" "new_emails_dlq" {
  name                      = "${local.name_prefix}-new-emails-dlq"
  message_retention_seconds = 1209600 # 14 days, the SQS maximum

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_sqs_queue" "new_emails" {
  name                       = "${local.name_prefix}-new-emails"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.new_emails_dlq.arn
    maxReceiveCount     = 5
  })

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# Lets the DLQ's console/CLI "redrive to source" action find its way back here.
resource "aws_sqs_queue_redrive_allow_policy" "new_emails_dlq" {
  queue_url = aws_sqs_queue.new_emails_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.new_emails.arn]
  })
}
