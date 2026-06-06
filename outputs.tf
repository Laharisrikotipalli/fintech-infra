# outputs.tf

output "kms_key_arn" {
  description = "ARN of the customer-managed KMS key"
  value       = aws_kms_key.fintech_key.arn
}

output "kms_key_id" {
  description = "ID of the customer-managed KMS key"
  value       = aws_kms_key.fintech_key.key_id
}

output "s3_bucket_name" {
  description = "Name of the S3 payment events bucket"
  value       = aws_s3_bucket.payment_events.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 payment events bucket"
  value       = aws_s3_bucket.payment_events.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB transactions table"
  value       = aws_dynamodb_table.transactions.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB transactions table"
  value       = aws_dynamodb_table.transactions.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.process_payment_lambda.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.process_payment_lambda.arn
}

output "iam_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda_payment_processor_role.arn
}

output "iam_policy_arn" {
  description = "ARN of the Lambda IAM policy"
  value       = aws_iam_policy.lambda_policy.arn
}
