module "dynamodb" {
  source = "./modules/dynamodb"

  project_name = var.project_name
  environment  = var.environment
}

module "secrets" {
  source = "./modules/secrets"

  project_name             = var.project_name
  environment              = var.environment
  google_oauth_secret_name = var.google_oauth_secret_name
}

module "sqs" {
  source = "./modules/sqs"

  project_name = var.project_name
  environment  = var.environment
}

module "lambda" {
  source = "./modules/lambda"

  project_name   = var.project_name
  environment    = var.environment
  lambda_runtime = var.lambda_runtime

  lambdas_source_dir = "${path.module}/../lambdas"
  layer_build_dir    = "${path.module}/build/layer"

  dynamodb_table_name          = module.dynamodb.table_name
  dynamodb_table_arn           = module.dynamodb.table_arn
  labels_table_name            = module.dynamodb.labels_table_name
  labels_table_arn             = module.dynamodb.labels_table_arn
  processing_errors_table_name = module.dynamodb.processing_errors_table_name
  processing_errors_table_arn  = module.dynamodb.processing_errors_table_arn

  google_oauth_secret_arn  = module.secrets.google_oauth_secret_arn
  google_oauth_secret_name = module.secrets.google_oauth_secret_name
  session_jwt_secret_arn   = module.secrets.session_jwt_secret_arn
  session_jwt_secret_name  = module.secrets.session_jwt_secret_name
  session_jwt_ttl_minutes  = var.session_jwt_ttl_minutes

  new_emails_queue_url                    = module.sqs.queue_url
  new_emails_queue_arn                    = module.sqs.queue_arn
  new_emails_dlq_arn                      = module.sqs.dlq_arn
  gmail_history_check_schedule_expression = var.gmail_history_check_schedule_expression
  bedrock_model_id                        = var.bedrock_model_id
}

module "step_functions" {
  source = "./modules/step_functions"

  project_name = var.project_name
  environment  = var.environment

  fetch_gmail_message_function_arn     = module.lambda.fetch_gmail_message_function_arn
  classify_email_labels_function_arn   = module.lambda.classify_email_labels_function_arn
  apply_gmail_labels_function_arn      = module.lambda.apply_gmail_labels_function_arn
  record_processing_error_function_arn = module.lambda.record_processing_error_function_arn
  new_emails_queue_arn                 = module.sqs.queue_arn
  alert_email                          = var.alert_email
}

module "api_gateway" {
  source = "./modules/api_gateway"

  project_name    = var.project_name
  environment     = var.environment
  allowed_origins = var.allowed_origins

  google_login_function_name   = module.lambda.google_login_function_name
  google_login_invoke_arn      = module.lambda.google_login_invoke_arn
  get_me_function_name         = module.lambda.get_me_function_name
  get_me_invoke_arn            = module.lambda.get_me_invoke_arn
  authorizer_function_name     = module.lambda.authorizer_function_name
  authorizer_invoke_arn        = module.lambda.authorizer_invoke_arn
  gmail_messages_function_name = module.lambda.gmail_messages_function_name
  gmail_messages_invoke_arn    = module.lambda.gmail_messages_invoke_arn
  labels_function_name         = module.lambda.labels_function_name
  labels_invoke_arn            = module.lambda.labels_invoke_arn
}
