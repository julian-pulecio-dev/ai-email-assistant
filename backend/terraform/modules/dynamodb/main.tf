resource "aws_dynamodb_table" "users" {
  name         = "${var.project_name}-${var.environment}-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# User-defined email categories ("labels"). Each item mirrors a real Gmail label
# (gmail_label_id) so the classifier/tagger steps can apply it to a message later.
resource "aws_dynamodb_table" "labels" {
  name         = "${var.project_name}-${var.environment}-labels"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"
  range_key    = "label_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "label_id"
    type = "S"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# One item per SQS message_id from new_emails that has ever failed processing.
# Written by record_processing_error (inside the state machine's failure path) and
# finalized by record_dead_letter once the message actually lands in the DLQ, so a
# dead-lettered event always has its underlying error attached and queryable.
resource "aws_dynamodb_table" "processing_errors" {
  name         = "${var.project_name}-${var.environment}-processing-errors"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "message_id"

  attribute {
    name = "message_id"
    type = "S"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}
