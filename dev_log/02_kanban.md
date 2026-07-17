# Unit 02: Kanban

## Objective

Create the kanban board file (`board.md`) that serves as the agent's control plane, and upload it to S3. This is the file whose modifications trigger the agent. Also define the MCP tool interface for reading and writing it from the Strands agent.

## Implementation

### board.md

The board file uses the `fancy-kanban` schema defined in the PRD (§5.2). It lives at the root of the S3 bucket.

```markdown
```fancy-kanban
---
title: Piano Teacher
fields:
  - name: title, type: Text, label: Title
  - name: status, type: Select, options: inbox|doing|done, label: Status, default: inbox
  - name: description, type: Textarea, label: Description
  - name: assignee, type: Select, options: piano-teacher|roberto, label: Assignee
  - name: session_date, type: Date, label: Session Date
  - name: docs, type: File, label: Docs
workflow: inbox→doing, doing→done, doing→inbox, done→doing
---

| _id | Status | Title | Description | Assignee | Session Date | Docs |
| --- | --- | --- | --- | --- | --- | --- |
```
```

Initially empty — user will add song cards manually.

### MCP tools (src/tools.py)

Two tools the Strands agent will call:

1. **`read_board`** — Reads `board.md` from S3, returns the raw markdown content.
2. **`write_board`** — Writes updated markdown content back to `board.md` in S3.

These are thin wrappers around S3 GetObject/PutObject, scoped to the single board file. The agent uses them to:
- Scan for cards matching `status=doing AND assignee=piano-teacher`
- Flip a card's status to `done` (loop guard)
- Append new lesson cards to the board

### Board parsing (src/board_parser.py)

A utility module that:
- Parses the fancy-kanban markdown table into a list of card dicts
- Filters cards by status and assignee
- Serializes cards back to markdown table rows
- Preserves the header/metadata block untouched

### deploy update

- `deploy.sh`: upload `board.md` to S3 as part of deployment (only if not already present — don't overwrite user's board)

## Files Created/Modified

- `board.md` — the kanban board template
- `src/tools.py` — MCP tool definitions (read_board, write_board)
- `src/board_parser.py` — parse/filter/serialize board markdown
- `infra/deploy.sh` — add board.md upload step

## Dependencies

- Unit 01 (infra must be deployed)

## Design Notes: Filesystem Abstraction vs S3 API

We considered abstracting the storage layer so the agent works on a plain directory (mounted via `mountpoint-s3` or `s3fs`) instead of calling S3 APIs directly. Benefits:
- Tools become pure filesystem read/write — no boto3 needed in agent code
- Local dev/test without S3 (just point at a local dir)
- Agent code is decoupled from deployment mechanism

Alternative trigger mechanisms were also evaluated:

| Approach | Latency | Infra complexity | Local dev story |
|----------|---------|-----------------|-----------------|
| S3 event → Lambda | ~1-3s | Medium (event config, Lambda) | Harder to test locally |
| Filesystem watcher | Instant | Low (just a process) | Works locally as-is |
| Manual CLI | Zero infra | None | Perfect locally |
| Polling loop | Configurable | Low | Works locally as-is |

**Decision:** Keep S3 event → Lambda for this PoC. It satisfies the "Always-On Agent" challenge requirement, and Lambda's 15-min timeout is sufficient for a single piece. The filesystem abstraction and long-running process approaches are noted here for a potential v2.

## AI Interactions

- None — straightforward file I/O and string parsing.

## Status: Complete
