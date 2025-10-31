# Control Tower Config Recorder Terraform Module
# This module converts the CloudFormation template to Terraform
# Maintains same functionality with enhanced event triggering

# SQS Queue for communication between Producer and Consumer Lambda
resource "aws_sqs_queue" "config_recorder" {
  name                       = "ct-config-recorder-queue"
  visibility_timeout_seconds = 900   # 15 minutes (matches Lambda timeout)
  delay_seconds              = 5
  kms_master_key_id          = "alias/aws/sqs"

  tags = local.common_tags
}

# Data source to create ZIP file for Producer Lambda
data "archive_file" "producer_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/producer/index.py"
  output_path = "${path.module}/lambda/producer/producer-lambda.zip"
}

# Producer Lambda Function
resource "aws_lambda_function" "producer" {
  filename      = data.archive_file.producer_lambda_zip.output_path
  function_name = "ct-config-recorder-producer"
  role          = aws_iam_role.producer_lambda_execution.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  memory_size   = 512
  timeout       = 900
  architectures = ["x86_64"]

  reserved_concurrent_executions = 1

  # Use source code hash to trigger updates when code changes
  source_code_hash = data.archive_file.producer_lambda_zip.output_base64sha256

  environment {
    variables = {
      EXCLUDED_ACCOUNTS = join(",", var.excluded_accounts)
      LOG_LEVEL         = var.lambda_log_level
      SQS_URL           = aws_sqs_queue.config_recorder.url
      LAMBDA_VERSION    = var.lambda_version
    }
  }

  # Ensure Lambda function is updated when source code changes
  depends_on = [
    data.archive_file.producer_lambda_zip,
    aws_iam_role_policy_attachment.producer_lambda_basic_execution,
    aws_iam_role_policy.producer_lambda_custom
  ]

  tags = local.common_tags
}

# IAM Role for Producer Lambda
resource "aws_iam_role" "producer_lambda_execution" {
  name = "ct-config-recorder-producer-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Attach basic execution role policy to Producer Lambda
resource "aws_iam_role_policy_attachment" "producer_lambda_basic_execution" {
  role       = aws_iam_role.producer_lambda_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Producer Lambda
resource "aws_iam_role_policy" "producer_lambda_custom" {
  name = "ct_cro_producer"
  role = aws_iam_role.producer_lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudformation:ListStackInstances"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:cloudformation:*:*:stackset/AWSControlTowerBP-BASELINE-CONFIG:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:ReceiveMessage",
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.config_recorder.arn
      }
    ]
  })
}

# Data source for AWS partition
data "aws_partition" "current" {}
# Data source to create ZIP file for Consumer Lambda
data "archive_file" "consumer_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/consumer/index.py"
  output_path = "${path.module}/lambda/consumer/consumer-lambda.zip"
}



# Consumer Lambda Function
resource "aws_lambda_function" "consumer" {
  filename      = data.archive_file.consumer_lambda_zip.output_path
  function_name = "ct-config-recorder-consumer"
  role          = aws_iam_role.consumer_lambda_execution.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  memory_size   = 512  # Increased for better performance
  timeout       = 900  # 15 minutes for cross-account operations
  architectures = ["x86_64"]

  reserved_concurrent_executions = 50

  # Use source code hash to trigger updates when code changes
  source_code_hash = data.archive_file.consumer_lambda_zip.output_base64sha256

  environment {
    variables = {
      LOG_LEVEL                                   = var.lambda_log_level
      CONFIG_RECORDER_STRATEGY                    = var.config_recorder_strategy
      CONFIG_RECORDER_DEFAULT_RECORDING_FREQUENCY = var.config_recorder_default_recording_frequency
      REGION_RESOURCE_TYPES_MAPPING               = local.region_continuous_resources_json
      REGION_EXCLUSIONS_MAPPING                   = local.region_exclusions_json
    }
  }

  # Ensure Lambda function is updated when source code changes
  depends_on = [
    data.archive_file.consumer_lambda_zip,
    aws_iam_role_policy_attachment.consumer_lambda_basic_execution,
    aws_iam_role_policy.consumer_lambda_custom
  ]
  tags = local.common_tags
}

# IAM Role for Consumer Lambda
resource "aws_iam_role" "consumer_lambda_execution" {
  name = "ct-config-recorder-consumer-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Attach basic execution role policy to Consumer Lambda
resource "aws_iam_role_policy_attachment" "consumer_lambda_basic_execution" {
  role       = aws_iam_role.consumer_lambda_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Consumer Lambda with STS assume role permissions
resource "aws_iam_role_policy" "consumer_lambda_custom" {
  name = "policy-sts-all"
  role = aws_iam_role.consumer_lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:ReceiveMessage",
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.config_recorder.arn
      }
    ]
  })
}

# SQS Event Source Mapping for Consumer Lambda
resource "aws_lambda_event_source_mapping" "consumer_sqs_trigger" {
  event_source_arn = aws_sqs_queue.config_recorder.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 1
  enabled          = true

  # Ensure the Consumer Lambda function is created before the event source mapping
  depends_on = [
    aws_lambda_function.consumer,
    aws_sqs_queue.config_recorder
  ]
}

# EventBridge Rule for Control Tower Events
resource "aws_cloudwatch_event_rule" "controltower_events" {
  name        = "ct-config-recorder-controltower-events"
  description = "Trigger Producer Lambda on Control Tower events"

  event_pattern = jsonencode({
    source      = ["aws.controltower"]
    detail-type = ["AWS Service Event via CloudTrail"]
    detail = {
      eventName = [
        "UpdateLandingZone",
        "CreateManagedAccount",
        "UpdateManagedAccount"
      ]
    }
  })

  tags = local.common_tags

  # Ensure the Lambda function is created before the EventBridge rule
  depends_on = [
    aws_lambda_function.producer
  ]
}

# EventBridge Target for Control Tower Events
resource "aws_cloudwatch_event_target" "controltower_lambda_target" {
  rule      = aws_cloudwatch_event_rule.controltower_events.name
  target_id = "ProducerLambdaTarget"
  arn       = aws_lambda_function.producer.arn
}

# Lambda Permission for Control Tower EventBridge Rule
resource "aws_lambda_permission" "allow_controltower_eventbridge" {
  statement_id  = "AllowExecutionFromControlTowerEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.controltower_events.arn
}


# EventBridge Rule for Producer Lambda Code/Configuration Updates
resource "aws_cloudwatch_event_rule" "producer_lambda_update_events" {
  name        = "ct-config-recorder-producer-update-events"
  description = "Trigger Producer Lambda when its code or configuration is updated"

  event_pattern = jsonencode({
    source      = ["aws.lambda"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = [
        "CreateFunction20150331",
        "UpdateFunctionConfiguration20150331v2"
      ]
      requestParameters = {
        functionName = [aws_lambda_function.producer.function_name]
      }
    }
  })

  tags = local.common_tags

  # Ensure the Lambda function is created before the EventBridge rule
  depends_on = [
    aws_lambda_function.producer
  ]
}

# EventBridge Target for Producer Lambda Update Events
resource "aws_cloudwatch_event_target" "producer_lambda_update_target" {
  rule      = aws_cloudwatch_event_rule.producer_lambda_update_events.name
  target_id = "ProducerLambdaUpdateTarget"
  arn       = aws_lambda_function.producer.arn
}

# Lambda Permission for Producer Lambda Update EventBridge Rule
resource "aws_lambda_permission" "allow_producer_lambda_update_eventbridge" {
  statement_id  = "AllowExecutionFromProducerLambdaUpdateEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.producer_lambda_update_events.arn
}

# CloudWatch Log Group for Producer Lambda
resource "aws_cloudwatch_log_group" "producer_lambda_logs" {
  name              = "/aws/lambda/ct-config-recorder-producer"
  retention_in_days = 90

  tags = local.common_tags
}

# CloudWatch Log Group for Consumer Lambda
resource "aws_cloudwatch_log_group" "consumer_lambda_logs" {
  name              = "/aws/lambda/ct-config-recorder-consumer"
  retention_in_days = 90

  tags = local.common_tags
}

# Manual trigger for Producer Lambda on initial deployment
resource "aws_lambda_invocation" "trigger_producer_on_deploy" {
  function_name = aws_lambda_function.producer.function_name

  input = jsonencode({
    source = "terraform.deployment"
    detail = {
      eventName = "InitialDeployment"
    }
  })

  # Trigger this whenever the producer lambda changes
  triggers = {
    lambda_hash = aws_lambda_function.producer.source_code_hash
  }

  depends_on = [
    aws_lambda_function.producer,
    aws_sqs_queue.config_recorder,
    aws_iam_role_policy.producer_lambda_custom
  ]
}
