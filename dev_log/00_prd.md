# PRD: piano-teacher

**Project:** piano-teacher **Context:** AWS Builder Center — "Build an Always-On Agent" Weekend Challenge **Window:**July 17, 12:00 AM PT – July 20, 1:00 PM PT **Owner:** Roberto Allende

---

## 1. Vision

Drop a piece of sheet music (PDF) into an S3 bucket. Create a card for it on a kanban board and assign it to `piano-teacher`. Move the card to **Doing**. Without any further action, the agent reads the score, breaks it into a structured practice plan, writes a markdown file per lesson (with embedded, playable notation), and populates the board with one practice card per lesson — ready for the user to work through.

The trigger is a file-modification event on the kanban board itself, not a button click or a chat request. The board is the control plane.

## 2. Problem It Solves

Learning a new piece from scratch is unstructured. Most players either try to play it top-to-bottom immediately (too hard, discouraging) or don't know how to break it into a sane practice sequence (hands separately, phrase by phrase, tempo ramp, tricky bars flagged). piano-teacher automates the "how would a teacher sequence this" step, and turns the output into trackable practice tasks.

## 3. Trigger Model

### 3.1 Board as control plane

The kanban board (a `fancy-kanban` block in a markdown file in S3) is the single source of truth for "what should the agent do." The agent does not act on PDF uploads directly — it acts on **kanban file changes**.

### 3.2 Flow

1. **User uploads** the PDF to `scores/<piece-id>.pdf` (plain S3 upload, no trigger yet).
2. **User creates a card** on the board: `Status = inbox`, `Title = <piece name>`, `Assignee = piano-teacher`, `Docs = <piece-id>.pdf`.
3. **User drags the card to Doing.** This edits the kanban markdown file in S3.
4. **S3 `ObjectModified` event** on the kanban file fires → Lambda → Strands agent wakes.
5. **Agent scans the board** for cards matching: `status = doing AND assignee = piano-teacher`. Any other assignee value is simply ignored by the agent — no special-casing of other people in code, the agent only ever looks for its own name.
6. For each matching card, the agent:
    - Reads the referenced PDF from `scores/`.
    - Calls Claude on Bedrock (multimodal) to analyze the score and generate a lesson decomposition, including abc notation per lesson (see §5).
    - Writes one markdown file per lesson to `lessons/<piece-id>/lesson-NN.md`.
    - **Rewrites the kanban file**: flips the original song card to `status = done`, and appends one new card per lesson to `status = inbox`, `Assignee` left blank (or set to the user), `Docs = lessons/<piece-id>/lesson-NN.md`.
7. **User practices**, dragging each lesson card `Inbox → Doing → Done` as they progress. These moves also touch the kanban file but do **not** match the trigger condition (`Assignee != piano-teacher`), so they don't cause the agent to re-run.

### 3.3 Loop guard (important)

Step 6 writes to the same file that step 4's event watches — a naive implementation would re-trigger itself. Guard: **the very first thing the agent does for a matched card is flip its `status` to `done`** (optimistic lock), before doing any of the slow work (PDF read, Bedrock call, lesson generation). The re-triggered Lambda invocation from that write then scans the board, finds no card with `status = doing AND assignee = piano-teacher` remaining, and exits immediately. This is a simple, good-enough guard for a weekend build — not airtight against a true concurrent race, but sufficient given cards are moved by a single human user, not high-frequency automated writers.

## 4. Architecture

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

### Components

|Component|Role|
|---|---|
|S3 bucket|Holds `scores/` (PDF input), `lessons/` (generated output), and the kanban board file. Source of the trigger event (on the kanban file only).|
|Lambda|Entry point invoked by the S3 `ObjectModified` event on the kanban file.|
|Strands Agent|Orchestrates the multi-step task: parse board, apply loop guard, read PDF, call model, decompose into lessons, write lesson files, rewrite board.|
|MCP server (tool layer)|Exposes kanban read/write, PDF read, and lesson-file write as MCP tools the agent calls.|
|Amazon Bedrock (Claude)|Reads the score, decides lesson decomposition, generates lesson content and abc notation.|

## 5. Output Format (Markdown Contract)

### 5.1 Lesson file — `lessons/<piece-id>/lesson-NN.md`

````markdown
---
piece_id: "<slug>"
lesson_number: <int>
title: "<short title>"
bars: "<e.g. 1-8>"
hands: "separate | together"
target_tempo: "<e.g. 60 bpm -> 90 bpm>"
difficulty_flags: ["<e.g. left-hand-leap>", "<e.g. syncopation>"]
---

# Lesson <N>: <short title>

## Focus
What this lesson isolates and why (1-2 sentences).

## Notation

```abc
X:1
T: <piece title> — Lesson <N>
M: <time signature>
L: <default note length>
K: <key>
<abc notation for this lesson's bars>
````

## Practice Steps

1. Step-by-step instructions, ordered.
2. ...

## Watch Out For

Specific tricky bars/beats and what tends to go wrong there.

## Done When

Concrete, observable completion criterion (e.g. "bars 1-8, hands together, clean at 80 bpm").

````

Notation is embedded directly as a fenced ` ```abc ` block — plain-text, portable ABC
notation. No binary audio asset is generated; any abc-notation-aware renderer can display
and play it back. This replaces the earlier MIDI-generation plan entirely — one fewer
moving part, no separate audio pipeline.

### 5.2 Kanban board fields

Board file uses the `fancy-kanban` schema. Proposed field list:

```yaml
fields:
  - name: status,       type: Select,   options: inbox|doing|done, label: Status, default: inbox
  - name: title,        type: Text,     label: Title
  - name: description,  type: Textarea, label: Description
  - name: assignee,     type: Select,   options: piano-teacher|roberto, label: Assignee
  - name: session_date, type: Date,     label: Session Date
  - name: docs,         type: File,     label: Docs
workflow: inbox→doing, doing→done, doing→inbox, done→doing
````

Notes on these choices:

- `assignee` as a **Select** (not free Text) — constrains values, which matters because the trigger condition depends on exact string matching. A typo in a free-text field would silently break the trigger. The agent's own logic only ever checks for `piano-teacher`; any other value (`roberto`, blank, etc.) is simply not matched — no special-casing of individual people in code.
- `session_date` / **Session Date** — not a deadline in the project-management sense, but the scheduled date of the practice session this card corresponds to. Renamed from the earlier "Due Date" to reflect that.
- `docs` carries the PDF reference on song cards, and the lesson markdown reference on lesson cards — reusing one field for both, consistent with the schema's generic `File` type.
- `workflow` omits `inbox→done` deliberately — a card must pass through `doing` to give the agent its trigger moment.

## 6. AWS Services Used

- Amazon S3 — PDF input, kanban board file, lesson output storage; event source
- AWS Lambda — event handler, agent host
- Amazon Bedrock — Claude (multimodal) for score analysis, lesson generation, abc notation
- Strands Agents SDK — agent orchestration layer
- MCP (Model Context Protocol) — tool interface between the agent and S3 (kanban read/write, PDF read, lesson write)
- IAM — least-privilege role for Lambda (S3 read on `scores/` and the board file, write on `lessons/` and the board file, Bedrock invoke)

## 7. Non-Goals (v1 / this weekend)

- **No MIDI generation.** Superseded by embedded abc notation (§5.1).
- **No OMR (optical music recognition) pipeline.** Score reading is done by handing the PDF directly to Claude's multimodal input. Accuracy on complex or handwritten scores is a known limitation — pick a clean, simple demo piece.
- **No user-facing app/UI.** The interface is the bucket and the kanban board file.
- **No proactive notification (email/SNS)** — see stretch goals.
- **No plugin-specific formatting requirements in the core contract.** The kanban and abc blocks follow their published schemas exactly as documented — general-purpose, not reinforced around any one renderer. Any nicer rendering (e.g. in Obsidian) is downstream presentation, not a build dependency.

## 8. Stretch Goals (only if core is done early)

- SES/SNS notification when the lesson cards are ready
- A "progress" signal — e.g. when the user marks the last lesson card `done`, the agent re-scans and could generate a short "piece complete" summary card
- Difficulty-adaptive re-planning if a lesson card sits in `doing` past its `session_date`

## 9. Demo / Proof of Autonomy

- Screen recording: move a card to Doing + assign `piano-teacher`, then cut to CloudWatch Logs showing the S3 event firing and the Strands execution trace.
- Screen recording: the kanban board updating with new lesson cards, and the lesson markdown files appearing in `lessons/`, with timestamps.
- (Personal demo polish, not a submission requirement) Opening the board and lesson files in Obsidian with the fancy-kanban and abcjs plugins installed, to show the output is compatible with a real workflow.

## 10. Article Mapping (AWS Builder Center submission requirements)

|Requirement|Covered by|
|---|---|
|Title incl. "Weekend Agent Challenge: piano-teacher"|—|
|Tag `#agents`|—|
|Vision & What the Agent Does|§1–3|
|How You Built It|§4, plus real build notes (decisions, blockers) written during the build|
|AWS Services Used / Architecture|§6, diagram from §4|
|What You Learned|To be written post-build — likely candidates: kanban-file-as-trigger pattern and its loop-guard problem, Strands + MCP integration, multimodal score-reading limitations|
|Link to App/Repo|GitHub repo, public|

## 11. Resolved Decisions

- **Assignee**: agent logic only ever checks for `piano-teacher`; no other names are special-cased in code.
- **Session Date**: represents the scheduled practice session for that card, not a project deadline.
- **Single Lambda**: hosts the whole Strands agent in-process, including the MCP tool calls for S3 read/write — no separately deployed MCP server for v1.
- Lesson count is **model-decided**, driven by difficulty — not fixed. The prompt instructs Claude to assess the piece assuming a **beginner** player and decompose accordingly: simpler/shorter pieces produce fewer lessons, harder or longer pieces produce more, with each lesson still scoped to a learnable chunk (a phrase or short passage, one specific technical focus). No fixed lesson-count target is set in code — this is a genuine model judgment call, which is also a good "how it reasons" beat for the article.
- **Lambda timeout confirmed as sufficient**: max configurable timeout is 900 seconds (15 min), hard ceiling, no override. The whole per-card pipeline (PDF read + multimodal Bedrock call + lesson generation + kanban rewrite) needs to fit inside that window. For a single beginner-level piece this should be comfortable; if a piece is unusually long/complex and risks running long, the fallback is AWS Step Functions to break the work into stages — not needed for v1, noted here so it's not a surprise if a demo piece runs close to the limit.
- Loop guard (§3.3) is optimistic-lock-only, no true distributed lock — accepted as sufficient for a single-user weekend demo. Flag as a known limitation in "What You Learned" rather than over-engineering it now.
