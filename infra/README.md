# Infrastructure Scripts

Bash scripts for deploying, testing, and tearing down the piano-teacher AWS resources using the AWS CLI.

## Prerequisites

- AWS CLI v2 installed and configured (`aws configure`)
- Appropriate IAM permissions to create Lambda functions, IAM roles, and S3 buckets
- Python 3.12 and `uv` installed (for packaging dependencies)

## Tagging

**All resources are tagged with `project: piano-teacher`.** This enables cost tracking, resource identification, and bulk cleanup.

## Scripts

### `deploy.sh`

Packages and deploys all AWS resources needed to run piano-teacher.

**What it creates:**
| Resource | Name | Purpose |
|----------|------|---------|
| S3 Bucket | `piano-teacher-<account-id>` | Stores scores, lessons, and the kanban board file |
| IAM Role | `piano-teacher-lambda-role` | Lambda execution role (S3 read/write, Bedrock invoke) |
| Lambda Function | `piano-teacher-handler` | Hosts the Strands agent |

**Usage:**
```bash
./deploy.sh                  # Deploy to default region (us-east-1)
./deploy.sh --region us-west-2  # Deploy to a specific region
```

**Idempotency:** The script checks for existing resources before creating them. Running it multiple times will update the Lambda code without duplicating infrastructure.

**IAM Policy Scope:**
- `s3:GetObject` on all bucket objects (scores, board, lessons)
- `s3:PutObject` on `lessons/*` and `board.md` only
- `s3:ListBucket` on the bucket
- `bedrock:InvokeModel` scoped to Anthropic models and inference profiles
- CloudWatch Logs for Lambda execution logs

---

### `run.sh`

Invokes the deployed Lambda with a simulated S3 ObjectModified event on `board.md`.

**Usage:**
```bash
./run.sh                    # Invoke with default test event
./run.sh --region us-west-2 # Specify region
```

**Output:** Prints the Lambda response JSON to stdout.

---

### `stop.sh`

Tears down **all** piano-teacher AWS resources. Destructive and irreversible.

**What it deletes:**
- Lambda function (`piano-teacher-handler`)
- IAM role and attached policies (`piano-teacher-lambda-role`)
- S3 bucket and all objects (`piano-teacher-<account-id>`)

**Usage:**
```bash
./stop.sh                    # Interactive confirmation prompt
./stop.sh --yes              # Skip confirmation (CI/automation)
./stop.sh --region us-west-2 --yes  # Specify region + skip prompt
```

**Safety:** By default, the script prompts "Are you sure? (y/N)" before proceeding.

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_DEFAULT_REGION` | `us-east-1` | AWS region for all operations |
| `BEDROCK_MODEL_ID` | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | Model for score analysis |
| Lambda timeout | 900s | Max Lambda timeout (15 min) |
| Lambda memory | 512 MB | Adjustable per workload |

All scripts accept `--region` as a CLI argument, which overrides the environment variable.

## Common Operations

**First-time setup:**
```bash
cd infra/
./deploy.sh
```

**Test the Lambda:**
```bash
./run.sh
```

**Redeploy after code changes:**
```bash
./deploy.sh  # Updates Lambda code in-place
```

**Tear everything down:**
```bash
./stop.sh
```
