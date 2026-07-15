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

module "lambda" {
  source = "./modules/lambda"

  project_name   = var.project_name
  environment    = var.environment
  lambda_runtime = var.lambda_runtime

  lambdas_source_dir = "${path.module}/../lambdas"
  layer_build_dir    = "${path.module}/build/layer"

  dynamodb_table_name = module.dynamodb.table_name
  dynamodb_table_arn  = module.dynamodb.table_arn

  google_oauth_secret_arn  = module.secrets.google_oauth_secret_arn
  google_oauth_secret_name = module.secrets.google_oauth_secret_name
  session_jwt_secret_arn   = module.secrets.session_jwt_secret_arn
  session_jwt_secret_name  = module.secrets.session_jwt_secret_name
  session_jwt_ttl_minutes  = var.session_jwt_ttl_minutes
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
}
