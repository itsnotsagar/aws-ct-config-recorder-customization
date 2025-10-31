variable "excluded_accounts" {
  description = "List of account IDs to exclude from config recorder customization"
  type        = list(string)
  default     = ["123456789012", "123456789012", "123456789012"]


  validation {
    condition = alltrue([
      for account in var.excluded_accounts : can(regex("^[0-9]{12}$", account))
    ])
    error_message = "All account IDs must be exactly 12 digits."
  }
}



variable "lambda_log_level" {
  description = "Log level for Lambda functions"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.lambda_log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR."
  }
}



variable "config_recorder_strategy" {
  description = "Config Recorder Strategy"
  type        = string
  default     = "EXCLUSION"

  validation {
    condition     = contains(["EXCLUSION"], var.config_recorder_strategy)
    error_message = "Config recorder strategy must be EXCLUSION."
  }
}

variable "config_recorder_default_recording_frequency" {
  description = "Default frequency of recording configuration changes"
  type        = string
  default     = "DAILY"

  validation {
    condition     = contains(["DAILY"], var.config_recorder_default_recording_frequency)
    error_message = "Config recorder default recording frequency must be DAILY."
  }
}

# Defining Region
variable "aws_region" {
  default = "eu-west-1"
}

# Defining Account Id
variable "account_id" {
  type    = string
  default = "123456789012" #CT Management Account
}

variable "lambda_version" {
  description = "Lambda function version - bump this to force config override for all accounts"
  type        = string
  default     = "1"
}

