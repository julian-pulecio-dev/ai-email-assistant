locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.allowed_origins
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}

# ---------------------------------------------------------------------------
# Authorizer
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_authorizer" "session" {
  api_id                            = aws_apigatewayv2_api.this.id
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = var.authorizer_invoke_arn
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  identity_sources                  = ["$request.header.Authorization"]
  name                              = "${local.name_prefix}-session-authorizer"
}

resource "aws_lambda_permission" "authorizer_invoke" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = var.authorizer_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.session.id}"
}

# ---------------------------------------------------------------------------
# POST /auth/google (public)
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_integration" "google_login" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.google_login_invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "google_login" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /auth/google"
  target    = "integrations/${aws_apigatewayv2_integration.google_login.id}"
}

resource "aws_lambda_permission" "google_login_invoke" {
  statement_id  = "AllowAPIGatewayInvokeGoogleLogin"
  action        = "lambda:InvokeFunction"
  function_name = var.google_login_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------
# GET /auth/me (protected)
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_integration" "get_me" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.get_me_invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_me" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /auth/me"
  target             = "integrations/${aws_apigatewayv2_integration.get_me.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.session.id
}

resource "aws_lambda_permission" "get_me_invoke" {
  statement_id  = "AllowAPIGatewayInvokeGetMe"
  action        = "lambda:InvokeFunction"
  function_name = var.get_me_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------
# GET /gmail/messages (protected)
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_integration" "gmail_messages" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.gmail_messages_invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "gmail_messages" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /gmail/messages"
  target             = "integrations/${aws_apigatewayv2_integration.gmail_messages.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.session.id
}

resource "aws_lambda_permission" "gmail_messages_invoke" {
  statement_id  = "AllowAPIGatewayInvokeGmailMessages"
  action        = "lambda:InvokeFunction"
  function_name = var.gmail_messages_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
