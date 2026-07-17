# Piano Teacher — Status

## Summary

Piano-teacher is a working always-on agent that reads sheet music PDFs and generates structured practice plans. Built for the AWS Builder Center "Build an Always-On Agent" Weekend Challenge.

The core flow is fully operational:
1. Upload a PDF score to S3
2. Add a card to the kanban board and assign it to `piano-teacher`
3. Move the card to "Doing"
4. The agent wakes automatically, reads the score, decomposes it into lessons with ABC notation, writes lesson files, and populates the board with practice cards

## What Works

- **S3 event trigger:** Uploading/modifying `board.md` in S3 fires the Lambda automatically
- **Loop guard:** The agent flips matched cards to `done` before processing, so the re-trigger from its own write exits in ~30ms
- **PDF analysis:** Claude Sonnet 4.5 reads the score via multimodal document input and produces structured lesson decompositions
- **Lesson generation:** Each lesson has YAML frontmatter, ABC notation, practice steps, warnings, and completion criteria — all per the PRD contract
- **Board management:** Lesson cards are added to the board in `inbox` status, assigned to the user
- **Scales with difficulty:** Simple pieces (Twinkle) → 8 lessons; complex pieces (Für Elise) → 13 lessons

## Tested Pieces

| Piece | Lessons | Processing Time |
|-------|---------|-----------------|
| Twinkle Twinkle Little Star | 8 | ~45 seconds |
| Für Elise (Beethoven WoO 59) | 13 | ~45 seconds |

## Architecture (Deployed)

```
S3 bucket: piano-teacher-741448943849
├── scores/         (uploaded PDFs)
├── lessons/        (generated markdown)
└── board.md        (fancy-kanban control plane)

Lambda: piano-teacher-handler
├── Runtime: Python 3.12
├── Timeout: 900s (15 min max)
├── Memory: 512 MB
└── Trigger: S3 ObjectCreated on board.md

Model: us.anthropic.claude-sonnet-4-5-20250929-v1:0
Region: us-east-1
```

## Units Completed

| Unit | Description | Status |
|------|-------------|--------|
| 01 Infra | S3, IAM, Lambda via bash scripts | ✅ Done |
| 02 Kanban | Board file, parser, MCP tools | ✅ Done |
| 03 Trigger | S3 event notification, loop guard | ✅ Done |
| 04 Agent | Strands Agent, Bedrock multimodal, lesson generation | ✅ Done |
| 05 Integration | End-to-end test with real PDF (Für Elise) | ✅ Done |
| 06 Demo | Article, screen recording | Pending |

## Issues Resolved During Build

1. **Linux platform wheels:** `rpds-py` (Rust native extension) needed `--python-platform manylinux2014_x86_64` in `uv pip install`
2. **IAM streaming permission:** Strands uses `ConverseStream` by default — needed `bedrock:InvokeModelWithResponseStream` in the policy
3. **Response extraction:** Strands `result.message` returns a dict `{"role": "assistant", "content": [...]}` — had to extract text blocks explicitly

## Repository Structure

```
piano-teacher/
├── dev_log/            # MMDD development log
├── infra/
│   ├── deploy.sh       # Idempotent deploy (all resources)
│   ├── run.sh          # Test invocation
│   ├── stop.sh         # Teardown with confirmation
│   └── README.md
├── src/
│   ├── handler.py      # Lambda entry point
│   ├── agent.py        # Strands Agent + lesson generation
│   ├── board_parser.py # Fancy-kanban markdown parser
│   └── tools.py        # @tool definitions for S3 operations
├── lessons/            # Generated output (gitignored)
├── board.md            # Template board
├── requirements.txt
└── .gitignore
```

## What Remains

- **Unit 06: Demo** — article draft for Builder Center submission, screen recording
- Optional: SNS notification when lessons are ready
- Optional: handle multiple cards in a single invocation more gracefully
