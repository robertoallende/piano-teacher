#!/usr/bin/env bash
# deploy.sh — Package and deploy the piano-teacher Lambda function and supporting resources.
#
# Creates:
#   - IAM role for Lambda execution
#   - S3 bucket for scores, lessons, and board
#   - Lambda function (Python 3.12)
#
# All resources are tagged with project=piano-teacher.
# Idempotent: safe to run multiple times.
#
# Usage: ./deploy.sh [--region REGION]

set -euo pipefail

# --- Configuration ---
PROJECT_TAG="piano-teacher"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
LAMBDA_NAME="piano-teacher-handler"
ROLE_NAME="piano-teacher-lambda-role"
POLICY_NAME="piano-teacher-policy"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="piano-teacher-${ACCOUNT_ID}"
RUNTIME="python3.12"
HANDLER="handler.lambda_handler"
TIMEOUT=900
MEMORY=512
MODEL_ID="us.anthropic.claude-sonnet-4-5-20250929-v1:0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region) REGION="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "==> Deploying piano-teacher to region: ${REGION}"
echo "    Account: ${ACCOUNT_ID}"

# =============================================================================
# Step 1: IAM Role
# =============================================================================
echo ""
echo "--- Step 1: IAM Role (${ROLE_NAME})"

TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}'

INLINE_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}/lessons/*",
        "arn:aws:s3:::${BUCKET_NAME}/board.md"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}"
    },
    {
      "Effect": "Allow",
      "Action": "bedrock:InvokeModel",
      "Resource": [
        "arn:aws:bedrock:*::foundation-model/anthropic.*",
        "arn:aws:bedrock:*:${ACCOUNT_ID}:inference-profile/us.anthropic.*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:${ACCOUNT_ID}:*"
    }
  ]
}
EOF
)

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
    echo "    Role already exists, updating policy..."
else
    echo "    Creating role..."
    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document "${TRUST_POLICY}" \
        --tags Key=project,Value="${PROJECT_TAG}" \
        --output text --query 'Role.Arn'
fi

echo "    Attaching inline policy..."
aws iam put-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name "${POLICY_NAME}" \
    --policy-document "${INLINE_POLICY}"

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo "    Done: ${ROLE_ARN}"

# =============================================================================
# Step 2: S3 Bucket
# =============================================================================
echo ""
echo "--- Step 2: S3 Bucket (${BUCKET_NAME})"

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    echo "    Bucket already exists."
else
    echo "    Creating bucket..."
    if [ "${REGION}" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "${BUCKET_NAME}" \
            --region "${REGION}"
    else
        aws s3api create-bucket \
            --bucket "${BUCKET_NAME}" \
            --region "${REGION}" \
            --create-bucket-configuration LocationConstraint="${REGION}"
    fi
fi

echo "    Applying tags..."
aws s3api put-bucket-tagging --bucket "${BUCKET_NAME}" \
    --tagging "TagSet=[{Key=project,Value=${PROJECT_TAG}}]"

echo "    Done."

# =============================================================================
# Step 3: Package Lambda
# =============================================================================
echo ""
echo "--- Step 3: Packaging Lambda"

BUILD_DIR=$(mktemp -d)
trap "rm -rf ${BUILD_DIR}" EXIT

echo "    Installing dependencies..."
uv pip install \
    --target "${BUILD_DIR}" \
    --quiet \
    -r "${SCRIPT_DIR}/../requirements.txt"

echo "    Copying source files..."
cp "${SCRIPT_DIR}/../src/"*.py "${BUILD_DIR}/"

echo "    Creating zip..."
(cd "${BUILD_DIR}" && zip -r -q "${SCRIPT_DIR}/lambda.zip" .)

ZIP_SIZE=$(du -h "${SCRIPT_DIR}/lambda.zip" | cut -f1)
echo "    Done: lambda.zip (${ZIP_SIZE})"

# =============================================================================
# Step 4: Deploy Lambda
# =============================================================================
echo ""
echo "--- Step 4: Lambda Function (${LAMBDA_NAME})"

# Wait for IAM role propagation (eventual consistency)
echo "    Waiting for IAM role propagation..."
sleep 10

if aws lambda get-function --function-name "${LAMBDA_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    echo "    Function exists, updating code..."
    aws lambda update-function-code \
        --function-name "${LAMBDA_NAME}" \
        --zip-file "fileb://${SCRIPT_DIR}/lambda.zip" \
        --region "${REGION}" \
        --output text --query 'FunctionArn'

    echo "    Waiting for code update to complete..."
    aws lambda wait function-updated \
        --function-name "${LAMBDA_NAME}" \
        --region "${REGION}"

    echo "    Updating configuration..."
    aws lambda update-function-configuration \
        --function-name "${LAMBDA_NAME}" \
        --runtime "${RUNTIME}" \
        --role "${ROLE_ARN}" \
        --handler "${HANDLER}" \
        --timeout "${TIMEOUT}" \
        --memory-size "${MEMORY}" \
        --environment "Variables={BUCKET_NAME=${BUCKET_NAME},BEDROCK_MODEL_ID=${MODEL_ID}}" \
        --region "${REGION}" \
        --output text --query 'FunctionArn'
else
    echo "    Creating function..."
    aws lambda create-function \
        --function-name "${LAMBDA_NAME}" \
        --runtime "${RUNTIME}" \
        --role "${ROLE_ARN}" \
        --handler "${HANDLER}" \
        --zip-file "fileb://${SCRIPT_DIR}/lambda.zip" \
        --timeout "${TIMEOUT}" \
        --memory-size "${MEMORY}" \
        --environment "Variables={BUCKET_NAME=${BUCKET_NAME},BEDROCK_MODEL_ID=${MODEL_ID}}" \
        --tags "project=${PROJECT_TAG}" \
        --region "${REGION}" \
        --output text --query 'FunctionArn'
fi

echo "    Done."

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==> Deployment complete!"
echo ""
echo "    Lambda ARN:  arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${LAMBDA_NAME}"
echo "    S3 Bucket:   ${BUCKET_NAME}"
echo "    IAM Role:    ${ROLE_ARN}"
echo "    Model:       ${MODEL_ID}"
echo "    Timeout:     ${TIMEOUT}s"
echo ""
echo "    Next: run ./run.sh to test the Lambda."
