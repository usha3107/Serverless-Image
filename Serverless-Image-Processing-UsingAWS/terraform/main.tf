resource "aws_s3_bucket" "uploads" {
  bucket = "${var.app_name}-uploads-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "processed" {
  bucket = "${var.app_name}-processed-${data.aws_caller_identity.current.account_id}"
}
resource "aws_s3_bucket_lifecycle_configuration" "uploads_lifecycle" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    id     = "delete-after-7-days"
    status = "Enabled"

    expiration {
      days = 7
    }
  }
}

resource "aws_sqs_queue" "image_processing_requests" {
  name                       = "${var.app_name}-image-processing-requests"
  visibility_timeout_seconds = 300
}

resource "aws_sqs_queue" "image_processing_results" {
  name                       = "${var.app_name}-image-processing-results"
  visibility_timeout_seconds = 300
}


resource "aws_iam_role" "lambda_role" {
  name = "${var.app_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}


resource "random_password" "api_key" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "api_key_secret" {
  name = "${var.app_name}-api-key"
}

resource "aws_secretsmanager_secret_version" "api_key_value" {
  secret_id     = aws_secretsmanager_secret.api_key_secret.id
  secret_string = random_password.api_key.result
}


resource "aws_iam_policy" "lambda_policy" {
  name = "${var.app_name}-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },

      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.uploads.arn}/*",
          "${aws_s3_bucket.processed.arn}/*"
        ]
      },

      {
        Effect   = "Allow"
        Action   = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.image_processing_requests.arn,
          aws_sqs_queue.image_processing_results.arn
        ]
      },

      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "${aws_secretsmanager_secret.api_key_secret.arn}*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


# Upload Image Lambda
resource "aws_lambda_function" "upload_image" {
  function_name = "${var.app_name}-upload-image"
  role          = aws_iam_role.lambda_role.arn
  handler       = "app.lambda_handler"
  runtime       = "python3.11"

  filename         = "${path.module}/../functions/upload_image.zip"
  source_code_hash = filebase64sha256("${path.module}/../functions/upload_image.zip")

  environment {
    variables = {
      UPLOADS_BUCKET      = aws_s3_bucket.uploads.bucket
      REQUESTS_QUEUE_URL = aws_sqs_queue.image_processing_requests.url
    }
  }
}

# Process Image Lambda (✅ FIXED WITH PILLOW LAYER)
resource "aws_lambda_function" "process_image" {
  function_name = "${var.app_name}-process-image"
  role          = aws_iam_role.lambda_role.arn
  handler       = "app.lambda_handler"
  runtime       = "python3.11"

  timeout      = 30
  memory_size = 512

  filename         = "${path.module}/../functions/process_image.zip"
  source_code_hash = filebase64sha256("${path.module}/../functions/process_image.zip")

  layers = [
    "arn:aws:lambda:us-east-1:936389956084:layer:pillow-layer:1"
  ]

  environment {
    variables = {
      UPLOADS_BUCKET    = aws_s3_bucket.uploads.bucket
      PROCESSED_BUCKET  = aws_s3_bucket.processed.bucket
      RESULTS_QUEUE_URL = aws_sqs_queue.image_processing_results.url
    }
  }
}

resource "aws_lambda_event_source_mapping" "process_image_sqs" {
  event_source_arn = aws_sqs_queue.image_processing_requests.arn
  function_name    = aws_lambda_function.process_image.arn
  batch_size       = 1
  enabled          = true
}

# Log Notification Lambda
resource "aws_lambda_function" "log_notification" {
  function_name = "${var.app_name}-log-notification"
  role          = aws_iam_role.lambda_role.arn
  handler       = "app.lambda_handler"
  runtime       = "python3.11"

  filename         = "${path.module}/../functions/log_notification.zip"
  source_code_hash = filebase64sha256("${path.module}/../functions/log_notification.zip")
}

resource "aws_lambda_event_source_mapping" "log_notification_sqs" {
  event_source_arn = aws_sqs_queue.image_processing_results.arn
  function_name    = aws_lambda_function.log_notification.arn
  batch_size       = 1
  enabled          = true
}



resource "aws_api_gateway_rest_api" "image_api" {
  name = "${var.app_name}-api"

  binary_media_types = [
    "image/png",
    "image/jpeg",
    "image/jpg"
  ]
}

resource "aws_api_gateway_resource" "v1" {
  rest_api_id = aws_api_gateway_rest_api.image_api.id
  parent_id   = aws_api_gateway_rest_api.image_api.root_resource_id
  path_part   = "v1"
}

resource "aws_api_gateway_resource" "images" {
  rest_api_id = aws_api_gateway_rest_api.image_api.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "images"
}

resource "aws_api_gateway_resource" "upload" {
  rest_api_id = aws_api_gateway_rest_api.image_api.id
  parent_id   = aws_api_gateway_resource.images.id
  path_part   = "upload"
}

resource "aws_api_gateway_method" "upload" {
  rest_api_id      = aws_api_gateway_rest_api.image_api.id
  resource_id      = aws_api_gateway_resource.upload.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "upload" {
  rest_api_id             = aws_api_gateway_rest_api.image_api.id
  resource_id             = aws_api_gateway_resource.upload.id
  http_method             = aws_api_gateway_method.upload.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.upload_image.invoke_arn
}
resource "aws_api_gateway_deployment" "image_api" {
  rest_api_id = aws_api_gateway_rest_api.image_api.id

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.upload
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.image_api.id
  deployment_id = aws_api_gateway_deployment.image_api.id
  stage_name    = "prod"
}


resource "aws_api_gateway_api_key" "image_api_key" {
  name    = "${var.app_name}-api-key"
  enabled = true
}

resource "aws_api_gateway_usage_plan" "image_usage_plan" {
  name = "${var.app_name}-usage-plan"

  throttle_settings {
    rate_limit  = 0.33
    burst_limit = 5
  }

  api_stages {
    api_id = aws_api_gateway_rest_api.image_api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }
}

resource "aws_api_gateway_usage_plan_key" "image_plan_key" {
  key_id        = aws_api_gateway_api_key.image_api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.image_usage_plan.id
}


resource "aws_lambda_permission" "api_gateway_upload" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_image.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.image_api.execution_arn}/*/*"
}
