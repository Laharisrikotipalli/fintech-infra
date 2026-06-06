# Fintech Infrastructure — Secure AWS Payments API with Terraform & LocalStack

A production-grade Infrastructure as Code project simulating a secure fintech payments backend. Everything runs locally via LocalStack — no real AWS account needed.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Step-by-Step Setup](#step-by-step-setup)
- [Terraform Workspaces](#terraform-workspaces)
- [Compliance Script](#compliance-script)
- [End-to-End Test](#end-to-end-test)
- [Environment Variables](#environment-variables)

---

## Architecture Overview

An event-driven, serverless workflow for processing payment events:

```
Client (AWS CLI)
      |
      |  uploads payment JSON file
      v
+-----------------------------------------------------+
|                  Encryption Boundary                |
|                                                     |
|   S3 Bucket: fintech-payment-events-{workspace}     |
|        |  (KMS encrypted, versioned, private)       |
|        |                                            |
|        |  s3:ObjectCreated:* event                  |
|        v                                            |
|   Lambda: process-payment-{workspace}               |
|        |  (reads event metadata, writes to DynamoDB)|
|        v                                            |
|   DynamoDB: transactions-{workspace}                |
|        (KMS encrypted, PAY_PER_REQUEST)             |
|                                                     |
|   KMS Key: fintech-cmk  (encrypts S3 + DynamoDB)   |
+-----------------------------------------------------+
         ^
         |  Assumes role
   IAM Role: lambda-payment-processor-role-{workspace}
         |  (least-privilege: s3:GetObject, dynamodb:PutItem, kms:Decrypt)
```

**Security principles enforced:**

- Encryption at Rest — S3 and DynamoDB both encrypted with a customer-managed KMS key
- Least Privilege IAM — No wildcard actions except logs:* for CloudWatch
- No Public Data — S3 bucket has all public access block settings enabled

---

## Project Structure

```
fintech-infra/
├── src/
│   └── process_payment.py    # Lambda function source code
├── dist/                     # Auto-generated Lambda ZIP (gitignored)
├── docker-compose.yml        # LocalStack environment
├── main.tf                   # All Terraform resources
├── variables.tf              # Input variables
├── outputs.tf                # Output values
├── compliance_check.sh       # Security compliance verification script
├── .env.example              # Environment variable template
├── .gitignore
└── README.md
```

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Docker Desktop | Latest | https://www.docker.com/products/docker-desktop |
| Terraform | >= 1.0 | https://developer.hashicorp.com/terraform/install |
| AWS CLI | >= 2.0 | https://aws.amazon.com/cli/ |
| jq | Latest | `brew install jq` / `apt install jq` |

Verify installations:

```bash
docker --version
terraform --version
aws --version
jq --version
```

---

## Quick Start

```bash
# 1. Clone and enter project
cd fintech-infra

# 2. Set up environment
cp .env.example .env
source .env

# 3. Start LocalStack
docker-compose up -d

# 4. Init and apply Terraform (dev workspace)
terraform init
terraform workspace new dev
terraform workspace new staging
terraform workspace select dev
terraform apply -auto-approve

# 5. Run compliance checks
./compliance_check.sh dev

# 6. Test the end-to-end flow
echo '{"paymentId": "123", "amount": 100}' > payment.json
aws s3 cp payment.json s3://fintech-payment-events-dev/
sleep 10
aws dynamodb scan --table-name transactions-dev
```

---

## Step-by-Step Setup

### 1. Start LocalStack

LocalStack emulates AWS services locally inside a Docker container.

```bash
docker-compose up -d
```

Verify it is running:

```bash
docker ps | grep localstack_fintech
curl http://localhost:4566/_localstack/health
```

You should see a JSON response listing s3, dynamodb, iam, kms, and lambda as available or running.

### 2. Configure Environment

```bash
cp .env.example .env
source .env
```

This sets `AWS_ENDPOINT_URL=http://localhost:4566` so all AWS CLI commands target LocalStack instead of real AWS.

### 3. Initialize Terraform

```bash
terraform init
```

This downloads the hashicorp/aws provider. The provider is pre-configured in `main.tf` to point all service endpoints at `http://localhost:4566`.

### 4. Create Workspaces

```bash
terraform workspace new dev
terraform workspace new staging
terraform workspace list
# Output: default, dev, staging
```

### 5. Deploy Infrastructure

```bash
terraform workspace select dev
terraform apply -auto-approve
```

Terraform will provision:

- 1 KMS Customer Managed Key with rotation enabled
- 1 S3 bucket with versioning, KMS encryption, and public access block
- 1 DynamoDB table with KMS encryption
- 1 IAM Role and least-privilege Policy for Lambda
- 1 Lambda function
- S3 bucket notification triggering Lambda on object creation

---

## Terraform Workspaces

Resource names are parameterized by `terraform.workspace`, giving each environment fully isolated resources.

| Resource | dev | staging |
|----------|-----|---------|
| S3 Bucket | `fintech-payment-events-dev` | `fintech-payment-events-staging` |
| DynamoDB Table | `transactions-dev` | `transactions-staging` |
| Lambda Function | `process-payment-dev` | `process-payment-staging` |
| IAM Role | `lambda-payment-processor-role-dev` | `lambda-payment-processor-role-staging` |

Switch workspaces:

```bash
terraform workspace select staging
terraform apply -auto-approve
```

---

## Compliance Script

`compliance_check.sh` inspects deployed resources and verifies all security requirements are met.

```bash
chmod +x compliance_check.sh
./compliance_check.sh dev
```

| Check | What it verifies |
|-------|-----------------|
| CHECK 1 | S3 public access block — all 4 settings are true |
| CHECK 2 | S3 encryption — algorithm is aws:kms |
| CHECK 3 | DynamoDB encryption — SSE status is ENABLED |
| CHECK 4 | IAM policy — no forbidden wildcard actions |

Successful output:

```
--- Running Compliance Checks for workspace: dev ---

[CHECK 1] Verifying S3 Public Access Block on bucket: fintech-payment-events-dev...
  SUCCESS: S3 bucket has public access block fully enabled.
[CHECK 2] Verifying S3 Encryption on bucket: fintech-payment-events-dev...
  SUCCESS: S3 bucket is encrypted with aws:kms.
[CHECK 3] Verifying DynamoDB Encryption on table: transactions-dev...
  SUCCESS: DynamoDB table encryption is enabled.
[CHECK 4] Verifying IAM policy for wildcard actions...
  SUCCESS: No forbidden wildcard actions found in IAM policy.

--- All Compliance Checks Passed! ---
```

Exit code 0 = all checks passed. Exit code 1 = a check failed.

---

## End-to-End Test

```bash
# 1. Create a test payment file
TEST_FILE="test-event-$(uuidgen).json"
echo '{"paymentId": "abc-123", "amount": 250.00, "currency": "USD"}' > "$TEST_FILE"

# 2. Upload to S3 — this triggers the Lambda
aws s3 cp "$TEST_FILE" "s3://fintech-payment-events-dev/$TEST_FILE"

# 3. Wait for Lambda to process
sleep 10

# 4. Verify the record was written to DynamoDB
aws dynamodb scan --table-name transactions-dev

# 5. Check Lambda logs (optional)
docker-compose logs localstack | grep "Processed"
```

You should see a DynamoDB item with ObjectKey matching the uploaded filename and Status set to PROCESSED.

---

## Environment Variables

| Variable | Description | Value |
|----------|-------------|-------|
| `AWS_ACCESS_KEY_ID` | Fake key for LocalStack auth | `test` |
| `AWS_SECRET_ACCESS_KEY` | Fake secret for LocalStack auth | `test` |
| `AWS_DEFAULT_REGION` | AWS region | `us-east-1` |
| `AWS_ENDPOINT_URL` | LocalStack endpoint | `http://localhost:4566` |

Never use real AWS credentials in `.env`. The values test/test are intentional for LocalStack.