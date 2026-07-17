# Unit 08: Lessons Board

## Objective

Change the agent's output to append a per-piece kanban board to `Lessons.md` instead of adding individual cards to `board.md`. Each piece gets its own `fancy-kanban` block, prepended to the top of the file.

## Implementation

### Changes to handler.py

Remove `_add_lesson_cards_to_board()` — no longer appending cards to `board.md`.

Instead, after `process_card()` returns the written lesson keys, call a new function that:
1. Reads `Lessons.md` from S3 (or starts with empty string if not found)
2. Generates a new `fancy-kanban` block for the piece (song card + lesson cards)
3. Prepends it to the existing content
4. Writes `Lessons.md` back to S3

### New function: `_prepend_lessons_board()`

Generates a block like:
```
```fancy-kanban
---
version: 1
title: <piece title>
fields:
  - name: title, type: Text, label: Title
  - name: status, type: Select, label: Status, options: inbox|doing|done, default: inbox
  - name: description, type: Textarea, label: Description
  - name: assignee, type: Select, label: Assignee, options: piano-teacher|roberto
  - name: session_date, type: Date, label: Session Date
  - name: docs, type: File, label: Docs
workflow: inbox→doing, doing→done, doing→inbox, done→doing, done→inbox
---

| _id | Title | Status | Description | Assignee | Session Date | Docs |
| --- | --- | --- | --- | --- | --- | --- |
| ... | <piece> | done | ... | piano-teacher | <today> | <pdf> |
| ... | <piece> — Lesson 01 | inbox | ... | roberto | <date> | lessons/...md |
```
```

### Session dates

Spread lessons across days starting from tomorrow, 2 lessons per day.

## Files Modified

- `src/handler.py` — replace `_add_lesson_cards_to_board` with `_prepend_lessons_board`

## Status: Complete
