locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  bedrock_model_arn = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.bedrock_model_id}"
}

# ---------------------------------------------------------------------------
# Attachment staging bucket - fetch_gmail_message writes attachment bytes here
# (Step Functions state payloads cap at 256KB, too small for most attachments)
# so classify_email_labels can read them back for the Bedrock Converse call.
# Objects are transient: a 1-day lifecycle rule cleans them up automatically.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "attachments" {
  bucket        = "${local.name_prefix}-attachments-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "attachments" {
  bucket                  = aws_s3_bucket.attachments.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "attachments" {
  bucket = aws_s3_bucket.attachments.id

  rule {
    id     = "expire-after-1-day"
    status = "Enabled"
    filter {}

    expiration {
      days = 1
    }
  }
}

# ---------------------------------------------------------------------------
# Shared layer (google-auth, PyJWT, common.py) - built by ../../../build_layer.ps1
# ---------------------------------------------------------------------------

data "archive_file" "layer" {
  type        = "zip"
  source_dir  = var.layer_build_dir
  output_path = "${path.module}/build/layer.zip"
}

resource "aws_lambda_layer_version" "shared" {
  layer_name          = "${local.name_prefix}-shared"
  filename            = data.archive_file.layer.output_path
  source_code_hash    = data.archive_file.layer.output_base64sha256
  compatible_runtimes = [var.lambda_runtime]
}

# ---------------------------------------------------------------------------
# IAM - common assume role policy + per-function policies
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "google_login" {
  name               = "${local.name_prefix}-google-login"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role" "get_me" {
  name               = "${local.name_prefix}-get-me"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role" "authorizer" {
  name               = "${local.name_prefix}-authorizer"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role" "gmail_messages" {
  name               = "${local.name_prefix}-gmail-messages"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role" "check_new_emails" {
  name               = "${local.name_prefix}-check-new-emails"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role" "fetch_gmail_message" {
  name               = "${local.name_prefix}-fetch-gmail-message"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role" "classify_email_labels" {
  name               = "${local.name_prefix}-classify-email-labels"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role" "apply_gmail_labels" {
  name               = "${local.name_prefix}-apply-gmail-labels"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role" "labels" {
  name               = "${local.name_prefix}-labels"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role" "record_processing_error" {
  name               = "${local.name_prefix}-record-processing-error"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role" "record_dead_letter" {
  name               = "${local.name_prefix}-record-dead-letter"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "google_login_logs" {
  role       = aws_iam_role.google_login.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "get_me_logs" {
  role       = aws_iam_role.get_me.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "authorizer_logs" {
  role       = aws_iam_role.authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "gmail_messages_logs" {
  role       = aws_iam_role.gmail_messages.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "check_new_emails_logs" {
  role       = aws_iam_role.check_new_emails.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "fetch_gmail_message_logs" {
  role       = aws_iam_role.fetch_gmail_message.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "classify_email_labels_logs" {
  role       = aws_iam_role.classify_email_labels.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "apply_gmail_labels_logs" {
  role       = aws_iam_role.apply_gmail_labels.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "labels_logs" {
  role       = aws_iam_role.labels.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "record_processing_error_logs" {
  role       = aws_iam_role.record_processing_error.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "record_dead_letter_logs" {
  role       = aws_iam_role.record_dead_letter.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "google_login" {
  statement {
    sid       = "DynamoDbReadWriteUsers"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem"]
    resources = [var.dynamodb_table_arn]
  }
  statement {
    sid       = "ReadOAuthAndJwtSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.google_oauth_secret_arn, var.session_jwt_secret_arn]
  }
}

resource "aws_iam_role_policy" "google_login" {
  name   = "${local.name_prefix}-google-login"
  role   = aws_iam_role.google_login.id
  policy = data.aws_iam_policy_document.google_login.json
}

data "aws_iam_policy_document" "get_me" {
  statement {
    sid       = "DynamoDbReadUsers"
    actions   = ["dynamodb:GetItem"]
    resources = [var.dynamodb_table_arn]
  }
}

resource "aws_iam_role_policy" "get_me" {
  name   = "${local.name_prefix}-get-me"
  role   = aws_iam_role.get_me.id
  policy = data.aws_iam_policy_document.get_me.json
}

data "aws_iam_policy_document" "authorizer" {
  statement {
    sid       = "ReadJwtSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.session_jwt_secret_arn]
  }
}

resource "aws_iam_role_policy" "authorizer" {
  name   = "${local.name_prefix}-authorizer"
  role   = aws_iam_role.authorizer.id
  policy = data.aws_iam_policy_document.authorizer.json
}

data "aws_iam_policy_document" "gmail_messages" {
  statement {
    sid       = "DynamoDbReadUpdateUsers"
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [var.dynamodb_table_arn]
  }
  statement {
    sid       = "ReadOAuthSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.google_oauth_secret_arn]
  }
}

resource "aws_iam_role_policy" "gmail_messages" {
  name   = "${local.name_prefix}-gmail-messages"
  role   = aws_iam_role.gmail_messages.id
  policy = data.aws_iam_policy_document.gmail_messages.json
}

data "aws_iam_policy_document" "check_new_emails" {
  statement {
    sid       = "DynamoDbScanReadUpdateUsers"
    actions   = ["dynamodb:Scan", "dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [var.dynamodb_table_arn]
  }
  statement {
    sid       = "ReadOAuthSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.google_oauth_secret_arn]
  }
  statement {
    sid       = "SendToNewEmailsQueue"
    actions   = ["sqs:SendMessage"]
    resources = [var.new_emails_queue_arn]
  }
}

resource "aws_iam_role_policy" "check_new_emails" {
  name   = "${local.name_prefix}-check-new-emails"
  role   = aws_iam_role.check_new_emails.id
  policy = data.aws_iam_policy_document.check_new_emails.json
}

data "aws_iam_policy_document" "fetch_gmail_message" {
  statement {
    sid       = "DynamoDbReadUpdateUsers"
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [var.dynamodb_table_arn]
  }
  statement {
    sid       = "ReadOAuthSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.google_oauth_secret_arn]
  }
  statement {
    sid       = "WriteAttachments"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.attachments.arn}/*"]
  }
}

resource "aws_iam_role_policy" "fetch_gmail_message" {
  name   = "${local.name_prefix}-fetch-gmail-message"
  role   = aws_iam_role.fetch_gmail_message.id
  policy = data.aws_iam_policy_document.fetch_gmail_message.json
}

data "aws_iam_policy_document" "classify_email_labels" {
  statement {
    sid       = "InvokeBedrockModel"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.bedrock_model_arn]
  }
  statement {
    sid       = "DynamoDbQueryLabels"
    actions   = ["dynamodb:Query"]
    resources = [var.labels_table_arn]
  }
  statement {
    sid       = "ReadAttachments"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.attachments.arn}/*"]
  }
}

resource "aws_iam_role_policy" "classify_email_labels" {
  name   = "${local.name_prefix}-classify-email-labels"
  role   = aws_iam_role.classify_email_labels.id
  policy = data.aws_iam_policy_document.classify_email_labels.json
}

data "aws_iam_policy_document" "apply_gmail_labels" {
  statement {
    sid       = "DynamoDbReadUpdateUsers"
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [var.dynamodb_table_arn]
  }
  statement {
    sid       = "ReadOAuthSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.google_oauth_secret_arn]
  }
}

resource "aws_iam_role_policy" "apply_gmail_labels" {
  name   = "${local.name_prefix}-apply-gmail-labels"
  role   = aws_iam_role.apply_gmail_labels.id
  policy = data.aws_iam_policy_document.apply_gmail_labels.json
}

data "aws_iam_policy_document" "labels" {
  statement {
    sid       = "DynamoDbReadWriteLabels"
    actions   = ["dynamodb:Query", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [var.labels_table_arn]
  }
  statement {
    sid       = "DynamoDbReadUpdateUsers"
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [var.dynamodb_table_arn]
  }
  statement {
    sid       = "ReadOAuthSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.google_oauth_secret_arn]
  }
}

resource "aws_iam_role_policy" "labels" {
  name   = "${local.name_prefix}-labels"
  role   = aws_iam_role.labels.id
  policy = data.aws_iam_policy_document.labels.json
}

data "aws_iam_policy_document" "record_processing_error" {
  statement {
    sid       = "WriteProcessingErrors"
    actions   = ["dynamodb:PutItem"]
    resources = [var.processing_errors_table_arn]
  }
}

resource "aws_iam_role_policy" "record_processing_error" {
  name   = "${local.name_prefix}-record-processing-error"
  role   = aws_iam_role.record_processing_error.id
  policy = data.aws_iam_policy_document.record_processing_error.json
}

data "aws_iam_policy_document" "record_dead_letter" {
  statement {
    sid       = "ReadWriteProcessingErrors"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem"]
    resources = [var.processing_errors_table_arn]
  }
  statement {
    sid       = "ConsumeDeadLetterQueue"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [var.new_emails_dlq_arn]
  }
}

resource "aws_iam_role_policy" "record_dead_letter" {
  name   = "${local.name_prefix}-record-dead-letter"
  role   = aws_iam_role.record_dead_letter.id
  policy = data.aws_iam_policy_document.record_dead_letter.json
}

# ---------------------------------------------------------------------------
# Function source packaging
# ---------------------------------------------------------------------------

data "archive_file" "google_login" {
  type        = "zip"
  source_dir  = "${var.lambdas_source_dir}/google_login"
  output_path = "${path.module}/build/google_login.zip"
}

data "archive_file" "get_me" {
  type        = "zip"
  source_dir  = "${var.lambdas_source_dir}/get_me"
  output_path = "${path.module}/build/get_me.zip"
}

data "archive_file" "authorizer" {
  type        = "zip"
  source_dir  = "${var.lambdas_source_dir}/authorizer"
  output_path = "${path.module}/build/authorizer.zip"
}

data "archive_file" "gmail_messages" {
  type        = "zip"
  source_dir  = "${var.lambdas_source_dir}/gmail_messages"
  output_path = "${path.module}/build/gmail_messages.zip"
}

data "archive_file" "check_new_emails" {
  type        = "zip"
  source_dir  = "${var.lambdas_source_dir}/check_new_emails"
  output_path = "${path.module}/build/check_new_emails.zip"
}

data "archive_file" "fetch_gmail_message" {
  type        = "zip"
  source_dir  = "${var.lambdas_source_dir}/fetch_gmail_message"
  output_path = "${path.module}/build/fetch_gmail_message.zip"
}

data "archive_file" "classify_email_labels" {
  type        = "zip"
  source_dir  = "${var.lambdas_source_dir}/classify_email_labels"
  output_path = "${path.module}/build/classify_email_labels.zip"
}

data "archive_file" "apply_gmail_labels" {
  type        = "zip"
  source_dir  = "${var.lambdas_source_dir}/apply_gmail_labels"
  output_path = "${path.module}/build/apply_gmail_labels.zip"
}

data "archive_file" "labels" {
  type        = "zip"
  source_dir  = "${var.lambdas_source_dir}/labels"
  output_path = "${path.module}/build/labels.zip"
}

data "archive_file" "record_processing_error" {
  type        = "zip"
  source_dir  = "${var.lambdas_source_dir}/record_processing_error"
  output_path = "${path.module}/build/record_processing_error.zip"
}

data "archive_file" "record_dead_letter" {
  type        = "zip"
  source_dir  = "${var.lambdas_source_dir}/record_dead_letter"
  output_path = "${path.module}/build/record_dead_letter.zip"
}

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "google_login" {
  function_name    = "${local.name_prefix}-google-login"
  role             = aws_iam_role.google_login.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.google_login.output_path
  source_code_hash = data.archive_file.google_login.output_base64sha256
  layers           = [aws_lambda_layer_version.shared.arn]
  timeout          = 10

  environment {
    variables = {
      USERS_TABLE_NAME         = var.dynamodb_table_name
      GOOGLE_OAUTH_SECRET_NAME = var.google_oauth_secret_name
      SESSION_JWT_SECRET_NAME  = var.session_jwt_secret_name
      SESSION_JWT_TTL_MINUTES  = tostring(var.session_jwt_ttl_minutes)
    }
  }
}

resource "aws_lambda_function" "get_me" {
  function_name    = "${local.name_prefix}-get-me"
  role             = aws_iam_role.get_me.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.get_me.output_path
  source_code_hash = data.archive_file.get_me.output_base64sha256
  layers           = [aws_lambda_layer_version.shared.arn]
  timeout          = 10

  environment {
    variables = {
      USERS_TABLE_NAME = var.dynamodb_table_name
    }
  }
}

resource "aws_lambda_function" "authorizer" {
  function_name    = "${local.name_prefix}-authorizer"
  role             = aws_iam_role.authorizer.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.authorizer.output_path
  source_code_hash = data.archive_file.authorizer.output_base64sha256
  layers           = [aws_lambda_layer_version.shared.arn]
  timeout          = 10

  environment {
    variables = {
      SESSION_JWT_SECRET_NAME = var.session_jwt_secret_name
    }
  }
}

resource "aws_lambda_function" "gmail_messages" {
  function_name    = "${local.name_prefix}-gmail-messages"
  role             = aws_iam_role.gmail_messages.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.gmail_messages.output_path
  source_code_hash = data.archive_file.gmail_messages.output_base64sha256
  layers           = [aws_lambda_layer_version.shared.arn]
  timeout          = 15

  environment {
    variables = {
      USERS_TABLE_NAME         = var.dynamodb_table_name
      GOOGLE_OAUTH_SECRET_NAME = var.google_oauth_secret_name
    }
  }
}

resource "aws_lambda_function" "check_new_emails" {
  function_name    = "${local.name_prefix}-check-new-emails"
  role             = aws_iam_role.check_new_emails.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.check_new_emails.output_path
  source_code_hash = data.archive_file.check_new_emails.output_base64sha256
  layers           = [aws_lambda_layer_version.shared.arn]
  timeout          = 60

  environment {
    variables = {
      USERS_TABLE_NAME         = var.dynamodb_table_name
      GOOGLE_OAUTH_SECRET_NAME = var.google_oauth_secret_name
      NEW_EMAILS_QUEUE_URL     = var.new_emails_queue_url
    }
  }
}

resource "aws_lambda_function" "fetch_gmail_message" {
  function_name    = "${local.name_prefix}-fetch-gmail-message"
  role             = aws_iam_role.fetch_gmail_message.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.fetch_gmail_message.output_path
  source_code_hash = data.archive_file.fetch_gmail_message.output_base64sha256
  layers           = [aws_lambda_layer_version.shared.arn]
  timeout          = 30
  memory_size      = 256 # downloads + base64-decodes attachment bytes

  environment {
    variables = {
      USERS_TABLE_NAME         = var.dynamodb_table_name
      GOOGLE_OAUTH_SECRET_NAME = var.google_oauth_secret_name
      ATTACHMENTS_BUCKET_NAME  = aws_s3_bucket.attachments.bucket
    }
  }
}

resource "aws_lambda_function" "classify_email_labels" {
  function_name    = "${local.name_prefix}-classify-email-labels"
  role             = aws_iam_role.classify_email_labels.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.classify_email_labels.output_path
  source_code_hash = data.archive_file.classify_email_labels.output_base64sha256
  layers           = [aws_lambda_layer_version.shared.arn]
  timeout          = 45
  memory_size      = 256 # holds decoded attachment bytes for the multimodal Converse call

  environment {
    variables = {
      BEDROCK_MODEL_ID        = var.bedrock_model_id
      LABELS_TABLE_NAME       = var.labels_table_name
      ATTACHMENTS_BUCKET_NAME = aws_s3_bucket.attachments.bucket
    }
  }
}

resource "aws_lambda_function" "apply_gmail_labels" {
  function_name    = "${local.name_prefix}-apply-gmail-labels"
  role             = aws_iam_role.apply_gmail_labels.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.apply_gmail_labels.output_path
  source_code_hash = data.archive_file.apply_gmail_labels.output_base64sha256
  layers           = [aws_lambda_layer_version.shared.arn]
  timeout          = 15

  environment {
    variables = {
      USERS_TABLE_NAME         = var.dynamodb_table_name
      GOOGLE_OAUTH_SECRET_NAME = var.google_oauth_secret_name
    }
  }
}

resource "aws_lambda_function" "labels" {
  function_name    = "${local.name_prefix}-labels"
  role             = aws_iam_role.labels.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.labels.output_path
  source_code_hash = data.archive_file.labels.output_base64sha256
  layers           = [aws_lambda_layer_version.shared.arn]
  timeout          = 15

  environment {
    variables = {
      LABELS_TABLE_NAME        = var.labels_table_name
      USERS_TABLE_NAME         = var.dynamodb_table_name
      GOOGLE_OAUTH_SECRET_NAME = var.google_oauth_secret_name
    }
  }
}

resource "aws_lambda_function" "record_processing_error" {
  function_name    = "${local.name_prefix}-record-processing-error"
  role             = aws_iam_role.record_processing_error.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.record_processing_error.output_path
  source_code_hash = data.archive_file.record_processing_error.output_base64sha256
  layers           = [aws_lambda_layer_version.shared.arn]
  timeout          = 10

  environment {
    variables = {
      PROCESSING_ERRORS_TABLE_NAME = var.processing_errors_table_name
    }
  }
}

resource "aws_lambda_function" "record_dead_letter" {
  function_name    = "${local.name_prefix}-record-dead-letter"
  role             = aws_iam_role.record_dead_letter.arn
  runtime          = var.lambda_runtime
  handler          = "handler.handler"
  filename         = data.archive_file.record_dead_letter.output_path
  source_code_hash = data.archive_file.record_dead_letter.output_base64sha256
  layers           = [aws_lambda_layer_version.shared.arn]
  timeout          = 15

  environment {
    variables = {
      PROCESSING_ERRORS_TABLE_NAME = var.processing_errors_table_name
    }
  }
}

resource "aws_lambda_event_source_mapping" "record_dead_letter" {
  event_source_arn = var.new_emails_dlq_arn
  function_name    = aws_lambda_function.record_dead_letter.arn
  batch_size       = 10
}

# ---------------------------------------------------------------------------
# EventBridge schedule - polls every N minutes for new Gmail messages
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "check_new_emails_schedule" {
  name                = "${local.name_prefix}-check-new-emails-schedule"
  schedule_expression = var.gmail_history_check_schedule_expression
}

resource "aws_cloudwatch_event_target" "check_new_emails" {
  rule = aws_cloudwatch_event_rule.check_new_emails_schedule.name
  arn  = aws_lambda_function.check_new_emails.arn
}

resource "aws_lambda_permission" "allow_eventbridge_check_new_emails" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.check_new_emails.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.check_new_emails_schedule.arn
}
