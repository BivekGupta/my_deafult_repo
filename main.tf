terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# --------------------------------------------------------------------------
# 1. DynamoDB Persistence Layer
# --------------------------------------------------------------------------
resource "aws_dynamodb_table" "url_mapping" {
  name         = "URLMapping"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "shortId"

  attribute {
    name = "shortId"
    type = "S"
  }

  tags = {
    Environment = "Production"
    Project     = "Serverless-URL-Shortener"
  }
}

# --------------------------------------------------------------------------
# 2. Backend Compute Layer (AWS Lambda)
# --------------------------------------------------------------------------
# Pack the lambda function folder into a zip file dynamically
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/app"
  output_path = "${path.module}/temp/lambda_function.zip"
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "url-shortener-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "://amazonaws.com" }
      }
    ]
  })
})

# Basic Lambda execution permissions for CloudWatch logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Explicit Read/Write access to the DynamoDB Table
resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "url-shortener-lambda-dynamodb-policy"
  description = "Allows Lambda to perform CRUD operations on the URLMapping DynamoDB Table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.url_mapping.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_lambda_function" "url_shortener" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "URLShortenerFunction"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.url_mapping.name
    }
  }
}

# --------------------------------------------------------------------------
# 3. Amazon API Gateway Endpoint Layer
# --------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "shortener_api" {
  name        = "UrlShortenerApi"
  description = "API Gateway for Serverless URL Shortener microservice"
}

# API Lambda Permission invocation block
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.url_shortener.function_name
  principal     = "://amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.shortener_api.execution_arn}/*/*"
}

# POST /shorten Resource Path Setup
resource "aws_api_gateway_resource" "shorten_res" {
  rest_api_id = aws_api_gateway_rest_api.shortener_api.id
  parent_id   = aws_api_gateway_rest_api.shortener_api.root_resource_id
  path_part   = "shorten"
}

resource "aws_api_gateway_method" "shorten_post" {
  rest_api_id   = aws_api_gateway_rest_api.shortener_api.id
  resource_id   = aws_api_gateway_resource.shorten_res.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "shorten_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.shortener_api.id
  resource_id             = aws_api_gateway_resource.shorten_res.id
  http_method             = aws_api_gateway_method.shorten_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.url_shortener.invoke_arn
}

# GET /{shortId} Dynamic Proxy Path Setup
resource "aws_api_gateway_resource" "redirect_res" {
  rest_api_id = aws_api_gateway_rest_api.shortener_api.id
  parent_id   = aws_api_gateway_rest_api.shortener_api.root_resource_id
  path_part   = "{shortId}"
}

resource "aws_api_gateway_method" "redirect_get" {
  rest_api_id   = aws_api_gateway_rest_api.shortener_api.id
  resource_id   = aws_api_gateway_resource.redirect_res.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "redirect_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.shortener_api.id
  resource_id             = aws_api_gateway_resource.redirect_res.id
  http_method             = aws_api_gateway_method.redirect_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.url_shortener.invoke_arn
}

# API Deployment & Execution Target Environment Stage
resource "aws_api_gateway_deployment" "prod_deploy" {
  depends_on = [
    aws_api_gateway_integration.shorten_post_integration,
    aws_api_gateway_integration.redirect_get_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.shortener_api.id
}

resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.prod_deploy.id
  rest_api_id   = aws_api_gateway_rest_api.shortener_api.id
  stage_name    = "prod"
}

# --------------------------------------------------------------------------
# 4. Amazon CloudFront Edge Distribution Layer
# --------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "cdn" {
  enabled = true

  origin {
    domain_name = "${aws_api_gateway_rest_api.shortener_api.id}.execute-api.${var.aws_region}.amazonaws.com"
    origin_id   = "APIGatewayOrigin"
    origin_path = "/${aws_api_gateway_stage.prod_stage.stage_name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "APIGatewayOrigin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      cookies { forward = "all" }
    }
    
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# --------------------------------------------------------------------------
# Outputs
# --------------------------------------------------------------------------
output "api_gateway_url" {
  value       = aws_api_gateway_stage.prod_stage.invoke_url
  description = "Base API Gateway staging resource link"
}

output "cloudfront_domain" {
  value       = "https://${aws_cloudfront_distribution.cdn.domain_name}"
  description = "Production global CloudFront edge address endpoint"
}
