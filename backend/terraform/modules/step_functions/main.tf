locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# State machine: process_new_email
#   FetchGmailMessage (Lambda)    - fetches the email + stages attachments in S3
#   ClassifyEmailLabels (Lambda)  - asks Amazon Nova Lite (Bedrock) which user-defined
#                                    labels apply, given the body and any attachments
#   ApplyGmailLabels (Lambda)     - tags the message in Gmail with the matched labels
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "state_machine" {
  name              = "/aws/vendedlogs/states/${local.name_prefix}-process-new-email"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "state_machine_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "state_machine" {
  name               = "${local.name_prefix}-process-new-email"
  assume_role_policy = data.aws_iam_policy_document.state_machine_assume_role.json
}

data "aws_iam_policy_document" "state_machine" {
  statement {
    sid     = "InvokeLambdas"
    actions = ["lambda:InvokeFunction"]
    resources = [
      var.fetch_gmail_message_function_arn,
      var.classify_email_labels_function_arn,
      var.apply_gmail_labels_function_arn,
      var.record_processing_error_function_arn,
    ]
  }

  # CloudWatch Logs' vended-logs delivery actions don't support resource-level
  # restriction - this broad scope is what AWS docs require for SFN logging.
  statement {
    sid = "CloudWatchLogsDelivery"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "state_machine" {
  name   = "${local.name_prefix}-process-new-email"
  role   = aws_iam_role.state_machine.id
  policy = data.aws_iam_policy_document.state_machine.json
}

resource "aws_sfn_state_machine" "process_new_email" {
  name     = "${local.name_prefix}-process-new-email"
  role_arn = aws_iam_role.state_machine.arn
  # Express (not Standard): billed per request+duration instead of per state
  # transition, and - combined with the pipe's REQUEST_RESPONSE invocation below -
  # lets a failed execution flow back to SQS for redelivery/DLQ instead of vanishing.
  type = "EXPRESS"

  definition = jsonencode({
    Comment = "Fetches a new Gmail message, classifies it (incl. attachments) against the user's labels via Amazon Nova Lite (Bedrock), and tags it in Gmail."
    StartAt = "UnwrapMessage"
    States = {
      # The pipe hands us the raw SQS record batch (batch_size=1): [{messageId, body,
      # attributes, ...}]. These two Pass states turn it into a flat
      # {message_id, receive_count, user_id, email_id} so every later state - including
      # error paths - has message_id available at the top level without needing a Lambda.
      UnwrapMessage = {
        Type = "Pass"
        Parameters = {
          "message_id.$"    = "$[0].messageId"
          "receive_count.$" = "$[0].attributes.ApproximateReceiveCount"
          "message.$"       = "States.StringToJson($[0].body)"
        }
        Next = "ExtractMessageFields"
      }
      ExtractMessageFields = {
        Type = "Pass"
        Parameters = {
          "message_id.$"    = "$.message_id"
          "receive_count.$" = "$.receive_count"
          "user_id.$"       = "$.message.user_id"
          "email_id.$"      = "$.message.email_id"
        }
        Next = "FetchGmailMessage"
      }
      FetchGmailMessage = {
        Type     = "Task"
        Resource = var.fetch_gmail_message_function_arn
        Retry = [
          {
            # The message was deleted/moved before we could fetch it - retrying won't help.
            ErrorEquals = ["GmailMessageNotFound"]
            MaxAttempts = 0
          },
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 2
            MaxAttempts     = 2
            BackoffRate     = 2
          }
        ]
        Catch = [
          {
            ErrorEquals = ["GmailMessageNotFound"]
            Next        = "EmailNotFound"
          },
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "RecordProcessingError"
          }
        ]
        Next = "ClassifyEmailLabels"
      }
      EmailNotFound = {
        Type   = "Pass"
        Result = { status = "skipped", reason = "message_not_found" }
        End    = true
      }
      ClassifyEmailLabels = {
        Type     = "Task"
        Resource = var.classify_email_labels_function_arn
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 2
            MaxAttempts     = 2
            BackoffRate     = 2
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "RecordProcessingError"
          }
        ]
        Next = "ApplyGmailLabels"
      }
      ApplyGmailLabels = {
        Type     = "Task"
        Resource = var.apply_gmail_labels_function_arn
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 2
            MaxAttempts     = 2
            BackoffRate     = 2
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "RecordProcessingError"
          }
        ]
        End = true
      }
      # Persists {message_id, user_id, email_id, error} before failing the execution,
      # so the error isn't lost if this message later exhausts SQS redrives and reaches
      # the DLQ (see record_dead_letter, which finalizes this same message_id's record).
      RecordProcessingError = {
        Type     = "Task"
        Resource = var.record_processing_error_function_arn
        Next     = "ProcessingFailed"
      }
      # Terminal failure. Ending the execution as FAILED (rather than swallowing the
      # error) is what lets the pipe's REQUEST_RESPONSE invocation report this message
      # as undelivered, so SQS redelivers it and it eventually reaches the DLQ if it
      # keeps failing.
      ProcessingFailed = {
        Type  = "Fail"
        Error = "EmailProcessingFailed"
        Cause = "A step in process_new_email failed after retries were exhausted - see this execution's CloudWatch Logs, or the processing_errors table by message_id, for the underlying error."
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.state_machine.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# Alerting - notified whenever an execution ends in ProcessingFailed (or any
# other unhandled failure, e.g. a Lambda timing out before it can even error).
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-process-new-email-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "process_new_email_failures" {
  alarm_name          = "${local.name_prefix}-process-new-email-failures"
  alarm_description   = "One or more process_new_email executions failed in the last 5 minutes."
  namespace           = "AWS/States"
  metric_name         = "ExecutionsFailed"
  dimensions          = { StateMachineArn = aws_sfn_state_machine.process_new_email.arn }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# ---------------------------------------------------------------------------
# EventBridge Pipe: new_emails SQS queue -> process_new_email state machine
# (no bridging Lambda needed - Pipes polls SQS and starts an execution per message)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "pipe_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["pipes.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pipe" {
  name               = "${local.name_prefix}-new-emails-pipe"
  assume_role_policy = data.aws_iam_policy_document.pipe_assume_role.json
}

data "aws_iam_policy_document" "pipe" {
  statement {
    sid       = "ReadFromNewEmailsQueue"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [var.new_emails_queue_arn]
  }
  statement {
    # REQUEST_RESPONSE against an EXPRESS state machine calls the synchronous
    # StartSyncExecution API under the hood, not the async StartExecution -
    # without this the pipe can't start any execution at all (AccessDenied),
    # so every message fails before the state machine's own error handling
    # ever runs and dead-letters with no associated processing_errors record.
    sid       = "StartStateMachineExecution"
    actions   = ["states:StartSyncExecution"]
    resources = [aws_sfn_state_machine.process_new_email.arn]
  }
}

resource "aws_iam_role_policy" "pipe" {
  name   = "${local.name_prefix}-new-emails-pipe"
  role   = aws_iam_role.pipe.id
  policy = data.aws_iam_policy_document.pipe.json
}

resource "aws_pipes_pipe" "new_emails_to_state_machine" {
  name     = "${local.name_prefix}-new-emails-to-state-machine"
  role_arn = aws_iam_role.pipe.arn
  source   = var.new_emails_queue_arn
  target   = aws_sfn_state_machine.process_new_email.arn

  source_parameters {
    sqs_queue_parameters {
      batch_size = 1
    }
  }

  target_parameters {
    step_function_state_machine_parameters {
      # Express-only: the pipe waits for the execution result, so a FAILED
      # execution is reported back as a failed batch item instead of being a
      # fire-and-forget success the moment StartExecution is accepted.
      invocation_type = "REQUEST_RESPONSE"
    }
  }
}
