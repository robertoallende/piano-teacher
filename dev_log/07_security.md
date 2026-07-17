# Unit 07: Security

## Objective

Harden the infrastructure with guardrails against runaway invocations, overly broad IAM permissions, and data loss.

## Implementation

### 1. Verify no recursive loop

The handler already implements the loop guard correctly:
- Reads board → filters for `status=doing AND assignee=piano-teacher`
- If no match → exits immediately (covers re-trigger case)
- If match → flips card to `done` before processing

The only writes to `board.md` happen:
- After flipping matched cards to `done` (loop guard itself)
- After adding lesson cards to inbox

Both are safe: the re-triggered invocation finds no `doing+piano-teacher` cards and exits in ~30ms.

**Action:** Add a comment block in handler.py documenting the loop guard contract for future maintainers.

### 2. Set reserved concurrency to 5

Caps the maximum number of concurrent Lambda invocations. Even if S3 events pile up (e.g. rapid board edits), only 5 will run simultaneously.

**Action:** Add `aws lambda put-function-concurrency` to deploy.sh.

### 3. Reduce timeout to 120s

The Bedrock call takes ~45s for complex pieces. 120s gives comfortable headroom without leaving a 15-minute runaway window.

**Action:** Change `TIMEOUT=900` to `TIMEOUT=120` in deploy.sh.

### 4. Scope Bedrock ARN

Current policy allows `arn:aws:bedrock:*::foundation-model/anthropic.*` and all inference profiles. Narrow to:
- Region: `us-east-1` only
- Specific inference profile: `us.anthropic.claude-sonnet-4-5-20250929-v1:0`

**Action:** Replace wildcard ARNs with specific resources in the IAM inline policy.

### 5. Scope CloudWatch logs ARN

Current policy allows `arn:aws:logs:*:${ACCOUNT_ID}:*`. Narrow to the specific log group.

**Action:** Replace with `arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:/aws/lambda/${LAMBDA_NAME}:*`

### 6. Enable bucket versioning

Protects against accidental overwrites or corruption of board.md and lesson files.

**Action:** Add `aws s3api put-bucket-versioning` to deploy.sh.

## Files Modified

- `infra/deploy.sh` — all six changes
- `src/handler.py` — loop guard documentation comment

## Dependencies

- Unit 01 (infra deployed)

## Status: Complete
