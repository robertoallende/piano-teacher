# MMDD Extension: Kanban Status Board - version 1

This extension modifies `00_mmdd.md`. In `00_main.md`, replace the "Units Implemented" and "Planned Units" sections with a single `fancy-kanban` board tracking all units.

## Board Rules

- One card per unit. Add a card per subunit only when the subunit's status diverges from its parent unit.
- Create the card (status `planned`) in Step 2 when the unit plan is approved.
- Move to `doing` when Step 3 starts. Context, implementation, and testing are all `doing`.
- Move to `done` in Step 5, together with the `_done.md` file and the commit.
- `Description`: one sentence, the unit's objective. `File`: the unit plan filename.
- Never display, remove, or regenerate existing `_id` values. Generate an `_id` only for new cards: 6-8 random lowercase alphanumeric characters.

## Board Format

Embed this block in `00_main.md`, adding one row per unit:

````markdown
```fancy-kanban
---
title: Units
fields:
  - name: status, type: Select, options: planned|doing|done, label: Status, default: planned
  - name: title, type: Text, label: Title
  - name: description, type: Textarea, label: Description
  - name: file, type: File, label: File
workflow: planned→doing, doing→done, doing→planned, done→doing
---

| _id    | Status | Title    | Description                          | File        |
|--------|--------|----------|--------------------------------------|-------------|
| a1b2c3 | done   | 01 Setup | Repository structure and templates   | 01_setup.md |
```
````

## Table Rules

- Column order: `_id` first, then fields in definition order.
- `Select` cells must contain one of the field's `options` values.
- The `workflow` line lists the allowed status transitions as `from→to` pairs; do not move a card along a transition not listed.
- `File` cells hold filenames; separate multiple files with `\|`.
- Row order within a status is display order; keep rows in unit sequence order.
- Empty cells are valid.
- Escape literal `|` in values as `\|`; write newlines as `<br>`.
- Edit only the board block when updating status — do not rewrite surrounding content.

This is a compact subset of the `fancy-kanban` schema, sufficient for this board. [Full specification](https://raw.githubusercontent.com/robertoallende/fancy-kanban/refs/heads/main/docs/schema.md).