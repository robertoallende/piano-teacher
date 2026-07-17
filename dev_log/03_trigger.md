# Unit 03: Trigger

## Objective

Wire the S3 ObjectModified event on `board.md` to the Lambda function. Implement the loop guard logic in the handler so the agent only processes cards matching `status=doing AND assignee=piano-teacher`, and exits immediately otherwise.

## Implementation

### S3 Event Notification

Configure the S3 bucket to send `s3:ObjectCreated:*` and `s3:ObjectModified:*` events to the Lambda function, filtered to the key `board.md` only.

Added to `deploy.sh`:
1. Add Lambda permission for S3 to invoke
2. Put bucket notification configuration filtered to `board.md`

### Handler logic (src/handler.py)

Replace the skeleton with real event handling:

1. Receive S3 event → extract bucket and key
2. Read `board.md` from S3 (using `read_board` tool or direct boto3)
3. Parse the board with `board_parser.parse_board()`
4. Filter cards: `status=doing AND assignee=piano-teacher`
5. **If no matching cards → exit immediately** (loop guard: the re-trigger from our own write finds nothing)
6. For each matching card:
   - Immediately flip status to `done` (optimistic lock / loop guard)
   - Write the updated board back to S3
   - (Actual processing deferred to Unit 04)

### Loop guard explanation (from PRD §3.3)

The agent writes to `board.md` which re-triggers itself. Guard: the first thing we do for a matched card is flip its status to `done` before doing any slow work. The re-triggered invocation finds no `doing + piano-teacher` cards and exits.

## Files Modified

- `infra/deploy.sh` — add S3 event notification + Lambda permission
- `src/handler.py` — real event handling with loop guard

## Dependencies

- Unit 01 (Lambda deployed)
- Unit 02 (board.md in S3, board_parser available)

## Status: Complete
