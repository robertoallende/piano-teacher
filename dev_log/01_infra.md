# Unit 01: Infra

## Objective

Set up the foundational AWS infrastructure for piano-teacher using bash scripts and the AWS CLI. All resources tagged `project: piano-teacher`. Idempotent deploy, testable invoke, clean teardown.

## Resources Created

| Resource | Name | Purpose |
|----------|------|---------|
| S3 Bucket | `piano-teacher-<account-id>` | Stores `scores/`, `lessons/`, and `board.md` |
| IAM Role | `piano-teacher-lambda-role` | Lambda execution role (S3 read/write, Bedrock invoke, CloudWatch logs) |
| Lambda Function | `piano-teacher-handler` | Hosts the Strands agent, triggered by S3 events on `board.md` |

## Configuration

- **Region:** us-east-1
- **Account:** (derived from `aws sts get-caller-identity`)
- **Runtime:** Python 3.12
- **Model:** `us.anthropic.claude-sonnet-4-5-20250929-v1:0` (cross-region inference profile)
- **Timeout:** 900 seconds (max — needed for PDF analysis + multi-lesson generation)
- **Memory:** 512 MB (to be tuned)
- **Tag:** `project=piano-teacher`

## IAM Policy Scope

- `s3:GetObject` on bucket (`scores/*`, `board.md`)
- `s3:PutObject` on bucket (`lessons/*`, `board.md`)
- `s3:ListBucket` on bucket (for listing lessons)
- `bedrock:InvokeModel` scoped to `arn:aws:bedrock:*::foundation-model/anthropic.*`
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`

## Implementation

### Directory structure

```
piano-teacher/
├── dev_log/
├── infra/
│   ├── deploy.sh       # Idempotent: creates/updates all resources
│   ├── run.sh          # Invokes the Lambda with a test event
│   ├── stop.sh         # Tears down all resources (with confirmation)
│   └── README.md       # Documents scripts and usage
├── src/
│   └── handler.py      # Lambda entry point (skeleton only in this unit)
└── requirements.txt
```

### deploy.sh steps

1. Create IAM role with trust policy for Lambda
2. Attach inline policy (S3 + Bedrock + CloudWatch)
3. Create S3 bucket (handle us-east-1 special case)
4. Apply bucket tags
5. Package Lambda (using `uv pip install --target` + zip)
6. Create or update Lambda function
7. Add S3 trigger permission (for Unit 03 — but the permission can be added now)
8. Print summary (ARN, bucket name, role)

### run.sh

Invokes the Lambda with a simulated S3 ObjectModified event pointing to `board.md`. Prints the response.

### stop.sh

Deletes Lambda, IAM role + policy, empties and deletes S3 bucket. Prompts for confirmation unless `--yes` is passed.

### handler.py (skeleton)

Minimal Lambda handler that logs the event and returns success. No Strands agent logic yet — that's Unit 04.

```python
def lambda_handler(event, context):
    print(f"Received event: {event}")
    return {"statusCode": 200, "body": "piano-teacher handler invoked"}
```

## AI Interactions

- None for this unit — straightforward infrastructure scripting.

## Files Modified

- `infra/deploy.sh`
- `infra/run.sh`
- `infra/stop.sh`
- `infra/README.md`
- `src/handler.py`
- `requirements.txt`

## Status: Complete
