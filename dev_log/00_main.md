# Project Plan and Dev Log

Piano-teacher: an always-on agent that reads sheet music and generates structured practice plans. Built for the AWS Builder Center "Build an Always-On Agent" Weekend Challenge.

## Structure

Units are numbered sequentially (`01`–`06`). Subunits use two-digit suffixes (`04_01`, `04_02`). All files live in `dev_log/`.

## About the Project

### What This Is

Drop a PDF score into S3, assign a kanban card to `piano-teacher`, move it to Doing. The agent wakes, reads the score via Bedrock Claude (multimodal), decomposes it into lessons with embedded ABC notation, writes lesson markdown files, and populates the board with practice cards.

### Architecture

```
S3 (scores/*.pdf)              S3 (board.md — fancy-kanban file)
   │  plain upload                    │  ObjectModified event
   │  (no trigger)                    ▼
   │                              Lambda (event handler)
   │                                   │  invokes
   │                                   ▼
   │                          Strands Agent (in Lambda)
   │                                   │  MCP tools:
   │                                   │  - read/write kanban file
   └──────── read PDF ─────────────►  │  - read PDF from S3
                                       │  - write lesson markdowns to S3
                                       ▼
                          Amazon Bedrock — Claude (multimodal)
                          score analysis + lesson decomposition
                          + abc notation generation per lesson
                                       │
                                       ▼
                    S3 (lessons/<piece-id>/lesson-NN.md)
                    S3 (board.md updated: song card → done,
                        N new lesson cards → inbox)
```

### Technical Stack

- **Runtime:** Python (Lambda)
- **Agent framework:** Strands Agents SDK
- **Tool protocol:** MCP (Model Context Protocol)
- **Model:** Amazon Bedrock — Claude (multimodal)
- **Storage:** Amazon S3
- **Trigger:** S3 ObjectModified event → Lambda
- **IaC:** AWS SAM / CloudFormation
- **IAM:** Least-privilege role for Lambda

## Project Status

### Overall Completion

Planning phase. No units started.

### Completed Features

None yet.

## Units

```fancy-kanban
---
version: 1
title: Units
fields:
  - name: title, type: Text, label: Title
  - name: status, type: Select, label: Status, options: planned|doing|done, default: planned
  - name: description, type: Textarea, label: Description
  - name: assignee, type: Select, label: Assignee, options: piano-teacher
  - name: file, type: File, label: File
workflow: planned→doing, doing→done, doing→planned, done→doing
---

| _id | Title | Status | Description | Assignee | File |
| --- | --- | --- | --- | --- | --- |
| k7m2x9p1 | 01 Infra | done | S3 bucket structure, IAM role, Lambda skeleton, IaC setup | piano-teacher | 01_infra.md |
| v3n8q4w2 | 02 Kanban | done | Board file with fancy-kanban schema, MCP tool for read/write | piano-teacher | 02_kanban.md |
| j5t1r6y8 | 03 Trigger | planned | S3 ObjectModified event wiring, Lambda invocation, loop guard logic | piano-teacher | 03_trigger.md |
| h9c4f2d7 | 04 Agent | planned | Strands Agent: PDF reading, Bedrock call, lesson decomposition, ABC output | piano-teacher | 04_agent.md |
| b6w8m3x5 | 05 Integration | planned | End-to-end wiring: agent rewrites board, full flow test with real PDF | piano-teacher | 05_integration.md |
| p2k7n9v4 | 06 Demo | planned | Demo piece selection, screen recording, Builder Center article draft | piano-teacher | 06_demo.md |
```
