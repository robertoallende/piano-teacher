#!/usr/bin/env bash
# stop.sh — Tear down all piano-teacher AWS resources.
#
# Deletes:
#   - Lambda function
#   - IAM role and inline policy
#   - S3 bucket and all objects
#
# Usage: ./stop.sh [--region REGION] [--yes]

set -euo pipefail

# --- Configuration ---
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
LAMBDA_NAME="piano-teacher-handler"
ROLE_NAME="piano-teacher-lambda-role"
POLICY_NAME="piano-teacher-policy"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="piano-teacher-${ACCOUNT_ID}"
SKIP_CONFIRM=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region) REGION="$2"; shift 2 ;;
        --yes) SKIP_CONFIRM=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "==> This will DELETE all piano-teacher resources in ${REGION}:"
echo "    - Lambda: ${LAMBDA_NAME}"
echo "    - IAM Role: ${ROLE_NAME}"
echo "    - S3 Bucket: ${BUCKET_NAME} (all objects)"
echo ""

if [ "${SKIP_CONFIRM}" = false ]; then
    read -p "Are you sure? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# =============================================================================
# Step 1: Delete Lambda
# =============================================================================
echo ""
echo "--- Step 1: Delete Lambda (${LAMBDA_NAME})"

if aws lambda get-function --function-name "${LAMBDA_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    aws lambda delete-function \
        --function-name "${LAMBDA_NAME}" \
        --region "${REGION}"
    echo "    Deleted."
else
    echo "    Not found, skipping."
fi

# =============================================================================
# Step 2: Delete IAM Role
# =============================================================================
echo ""
echo "--- Step 2: Delete IAM Role (${ROLE_NAME})"

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
    echo "    Removing inline policy..."
    aws iam delete-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-name "${POLICY_NAME}" 2>/dev/null || true

    echo "    Deleting role..."
    aws iam delete-role --role-name "${ROLE_NAME}"
    echo "    Deleted."
else
    echo "    Not found, skipping."
fi

# =============================================================================
# Step 3: Delete S3 Bucket
# =============================================================================
echo ""
echo "--- Step 3: Delete S3 Bucket (${BUCKET_NAME})"

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    echo "    Emptying bucket..."
    aws s3 rm "s3://${BUCKET_NAME}" --recursive --quiet

    echo "    Deleting bucket..."
    aws s3api delete-bucket --bucket "${BUCKET_NAME}" --region "${REGION}"
    echo "    Deleted."
else
    echo "    Not found, skipping."
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==> Teardown complete. All piano-teacher resources removed."
