#!/bin/bash
set -e
if [ -f .env ]; then
  export $(cat .env | sed 's/#.*//g' | xargs)
fi

WORKSPACE=${1:-dev} 
BUCKET_NAME="fintech-payment-events-$WORKSPACE"
TABLE_NAME="transactions-$WORKSPACE"

KEY_ARN=$(aws --endpoint-url="$AWS_ENDPOINT_URL" kms list-aliases | jq -r '.Aliases[] | select(.AliasName=="alias/aws/s3") | .TargetKeyId' | xargs -I {} aws --endpoint-url="$AWS_ENDPOINT_URL" kms describe-key --key-id {} | jq -r '.KeyMetadata.Arn')
POLICY_ARN=$(aws --endpoint-url="$AWS_ENDPOINT_URL" iam list-policies --scope Local | jq -r --arg WS "$WORKSPACE" '.Policies[] | select(.PolicyName=="lambda-payment-processor-policy-"+$WS) | .Arn')

echo "--- Running Compliance Checks for workspace: $WORKSPACE ---"
echo "  Bucket : $BUCKET_NAME"
echo "  Table  : $TABLE_NAME"
echo "  KMS ARN: $KEY_ARN"
echo "  Policy : $POLICY_ARN"
echo ""

echo "[CHECK 1] Verifying S3 Public Access Block on bucket: $BUCKET_NAME..."
PUBLIC_ACCESS_BLOCK=$(aws --endpoint-url="$AWS_ENDPOINT_URL" s3api get-public-access-block --bucket "$BUCKET_NAME")

if [[ $(echo "$PUBLIC_ACCESS_BLOCK" | jq '.PublicAccessBlockConfiguration.BlockPublicAcls') == "true" && \
      $(echo "$PUBLIC_ACCESS_BLOCK" | jq '.PublicAccessBlockConfiguration.BlockPublicPolicy') == "true" && \
      $(echo "$PUBLIC_ACCESS_BLOCK" | jq '.PublicAccessBlockConfiguration.IgnorePublicAcls') == "true" && \
      $(echo "$PUBLIC_ACCESS_BLOCK" | jq '.PublicAccessBlockConfiguration.RestrictPublicBuckets') == "true" ]]; then
    echo "  ✓ SUCCESS: S3 bucket has public access block fully enabled."
else
    echo "  ✗ FAILURE: S3 public access block is not correctly configured."
    exit 1
fi

echo "[CHECK 2] Verifying S3 Encryption on bucket: $BUCKET_NAME..."
BUCKET_ENCRYPTION=$(aws --endpoint-url="$AWS_ENDPOINT_URL" s3api get-bucket-encryption --bucket "$BUCKET_NAME")
SSE_ALGORITHM=$(echo "$BUCKET_ENCRYPTION" | jq -r '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm')

if [[ "$SSE_ALGORITHM" == "aws:kms" ]]; then
    echo "  ✓ SUCCESS: S3 bucket is encrypted with aws:kms."
else
    echo "  ✗ FAILURE: S3 bucket encryption is not aws:kms. Found: $SSE_ALGORITHM"
    exit 1
fi

echo "[CHECK 3] Verifying DynamoDB Encryption on table: $TABLE_NAME..."
TABLE_DESCRIPTION=$(aws --endpoint-url="$AWS_ENDPOINT_URL" dynamodb describe-table --table-name "$TABLE_NAME")
SSE_STATUS=$(echo "$TABLE_DESCRIPTION" | jq -r '.Table.SSEDescription.Status')

if [[ "$SSE_STATUS" == "ENABLED" ]]; then
    echo "  ✓ SUCCESS: DynamoDB table encryption is enabled."
else
    echo "  ✗ FAILURE: DynamoDB encryption is not enabled. Status: $SSE_STATUS"
    exit 1
fi

echo "[CHECK 4] Verifying IAM policy for wildcard actions..."
POLICY_VERSION=$(aws --endpoint-url="$AWS_ENDPOINT_URL" iam get-policy --policy-arn "$POLICY_ARN" | jq -r '.Policy.DefaultVersionId')
POLICY_DOC=$(aws --endpoint-url="$AWS_ENDPOINT_URL" iam get-policy-version --policy-arn "$POLICY_ARN" --version-id "$POLICY_VERSION")

ALLOWED_WILDCARD="logs:*"
WILDCARD_ACTIONS=$(echo "$POLICY_DOC" | jq -r '.PolicyVersion.Document.Statement[].Action | if type=="array" then .[] else . end | select(contains("*"))')
FILTERED_WILDCARDS=$(echo "$WILDCARD_ACTIONS" | grep -v "$ALLOWED_WILDCARD" || true)

if [[ -z "$FILTERED_WILDCARDS" ]]; then
    echo "  ✓ SUCCESS: No forbidden wildcard actions found in IAM policy."
else
    echo "  ✗ FAILURE: Forbidden wildcard actions found: $FILTERED_WILDCARDS"
    exit 1
fi

echo ""
echo "--- All Compliance Checks Passed! ---"