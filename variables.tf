# variables.tf

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_endpoint_url" {
  description = "LocalStack endpoint URL"
  type        = string
  default     = "http://localhost:4566"
}
