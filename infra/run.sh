#!/usr/bin/env bash
# run.sh — Invoke the piano-teacher Lambda with a simulated S3 ObjectModified event.
#
# Usage: ./run.sh [--region REGION]

set -euo pipefail

# --- Configuration ---
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
LAMBDA_NAME="piano-teacher-handler"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="piano-teacher-${ACCOUNT_ID}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region) REGION="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "==> Invoking ${LAMBDA_NAME} in ${REGION}"
echo ""

# Simulated S3 ObjectModified event for board.md
EVENT=$(cat <<EOF
{
  "Records": [
    {
      "eventSource": "aws:s3",
      "eventName": "ObjectModified:Put",
      "s3": {
        "bucket": {
          "name": "${BUCKET_NAME}"
        },
        "object": {
          "key": "board.md"
        }
      }
    }
  ]
}
EOF
)

# Invoke and capture response
OUTPUT_FILE=$(mktemp)
trap "rm -f ${OUTPUT_FILE}" EXIT

aws lambda invoke \
    --function-name "${LAMBDA_NAME}" \
    --region "${REGION}" \
    --cli-binary-format raw-in-base64-out \
    --payload "${EVENT}" \
    "${OUTPUT_FILE}" >/dev/null

echo "Response:"
python3 -m json.tool "${OUTPUT_FILE}" 2>/dev/null || cat "${OUTPUT_FILE}"
