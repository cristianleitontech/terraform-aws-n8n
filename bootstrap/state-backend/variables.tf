variable "aws_region" {
  description = "AWS region where the S3 backend bucket will be created."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment label used in resource tags."
  type        = string
  default     = "demo"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state."
  type        = string
}

variable "noncurrent_version_expiration_days" {
  description = "Days to keep noncurrent object versions before S3 lifecycle cleanup."
  type        = number
  default     = 30
}
