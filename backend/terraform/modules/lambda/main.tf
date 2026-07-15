locals {
  name_prefix = "${var.project_name}-${var.environment}"
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
