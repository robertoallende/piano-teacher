# Unit 04: Agent

## Objective

Implement the Strands Agent that reads a PDF score via Bedrock Claude (multimodal), decomposes it into structured practice lessons with ABC notation, and writes lesson markdown files to S3.

## Implementation

### Agent orchestration (src/agent.py)

A Strands Agent with:
- **System prompt:** Instructs Claude to act as a piano teacher. Given a score PDF, decompose it into beginner-level lessons. Each lesson covers a phrase/passage, one technical focus, with ABC notation.
- **Tools:** `read_board`, `write_board`, `read_score`, `write_lesson` (from src/tools.py)
- **Model:** `us.anthropic.claude-sonnet-4-5-20250929-v1:0` via Bedrock

### Processing flow (called from handler.py)

For each matched card:
1. Read the PDF from `scores/<docs field>`
2. Send PDF bytes to Bedrock Claude as multimodal input (document type)
3. Prompt: analyze the score, determine lesson count based on difficulty for a beginner, generate structured lesson content with ABC notation
4. Parse the response into individual lesson files
5. Write each lesson to `lessons/<piece-id>/lesson-NN.md`
6. Update the board: add lesson cards to inbox

### Lesson generation prompt strategy

Two-phase approach:
1. **Analysis call:** Send the PDF, ask for a lesson decomposition plan (JSON): number of lessons, bars covered, focus area, difficulty flags per lesson
2. **Generation call:** For each lesson in the plan, generate the full markdown content with ABC notation

Alternative (simpler, may fit in one call for short pieces):
- Single call: send PDF + prompt, get all lessons back in one structured response

**Decision:** Start with single-call for simplicity. If responses get truncated for longer pieces, split into two phases.

### Handler integration

Update `handler.py` to call the agent after the loop guard flip:
```python
for card in matched:
    process_card(card)  # calls agent
```

### Output format

Each lesson file follows the contract from PRD §5.1:
```markdown
---
piece_id: "<slug>"
lesson_number: <int>
title: "<short title>"
bars: "<e.g. 1-8>"
hands: "separate | together"
target_tempo: "<e.g. 60 bpm -> 90 bpm>"
difficulty_flags: ["<flag>"]
---

# Lesson <N>: <short title>

## Focus
...

## Notation
```abc
...
```

## Practice Steps
...

## Watch Out For
...

## Done When
...
```

## Files Created/Modified

- `src/agent.py` — Strands Agent definition and process_card function
- `src/handler.py` — integrate agent call after loop guard
- `src/tools.py` — may need adjustment for multimodal PDF handling

## Dependencies

- Unit 01 (infra)
- Unit 02 (board parser, tools)
- Unit 03 (trigger + loop guard)

## Status: Complete
