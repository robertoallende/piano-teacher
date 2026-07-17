"""board_parser.py — Parse, filter, and serialize fancy-kanban board markdown."""

import re
import string
import random


def parse_board(content: str) -> dict:
    """Parse a fancy-kanban markdown file into structured data.

    Returns:
        {
            "raw_config": str,       # The config block (between --- markers)
            "fields": [{"name": ..., "type": ..., "label": ..., ...}],
            "cards": [{"_id": ..., "status": ..., "title": ..., ...}],
            "header_labels": [str],  # Column labels in order (excluding _id)
        }
    """
    # Extract content between fancy-kanban fences
    fence_match = re.search(
        r"```fancy-kanban\s*\n(.*?)```", content, re.DOTALL
    )
    if not fence_match:
        raise ValueError("No fancy-kanban block found in content")

    block = fence_match.group(1)

    # Split on --- markers
    parts = re.split(r"^---\s*$", block, flags=re.MULTILINE)
    if len(parts) < 3:
        raise ValueError("Could not find config and table sections (need two --- markers)")

    raw_config = parts[1].strip()
    table_section = parts[2].strip()

    # Parse fields from config
    fields = _parse_fields(raw_config)

    # Build label-to-name mapping
    label_to_name = {f["label"].lower(): f["name"] for f in fields}

    # Parse table
    table_lines = [line for line in table_section.split("\n") if line.strip().startswith("|")]

    if len(table_lines) < 2:
        return {
            "raw_config": raw_config,
            "fields": fields,
            "cards": [],
            "header_labels": [],
        }

    # Header row
    header_cells = _split_row(table_lines[0])
    # First cell is _id, rest are field labels
    header_labels = header_cells[1:]  # Skip _id

    # Map header labels to field names
    header_names = []
    for label in header_labels:
        name = label_to_name.get(label.lower(), label.lower().replace(" ", "_"))
        header_names.append(name)

    # Data rows (skip header and separator)
    cards = []
    for line in table_lines[2:]:
        cells = _split_row(line)
        if not cells:
            continue

        card = {"_id": cells[0]}
        for i, name in enumerate(header_names):
            value = cells[i + 1] if i + 1 < len(cells) else ""
            card[name] = _unescape(value)
        cards.append(card)

    return {
        "raw_config": raw_config,
        "fields": fields,
        "cards": cards,
        "header_labels": header_labels,
    }


def filter_cards(cards: list, **criteria) -> list:
    """Filter cards by field values.

    Example:
        filter_cards(cards, status="doing", assignee="piano-teacher")
    """
    result = []
    for card in cards:
        match = all(card.get(k, "") == v for k, v in criteria.items())
        if match:
            result.append(card)
    return result


def update_card(cards: list, card_id: str, **updates) -> list:
    """Update a card's fields by _id. Returns the modified list."""
    for card in cards:
        if card["_id"] == card_id:
            card.update(updates)
            break
    return cards


def add_card(cards: list, card_data: dict) -> list:
    """Add a new card. Generates _id if not provided."""
    if "_id" not in card_data or not card_data["_id"]:
        card_data["_id"] = _generate_id()
    cards.append(card_data)
    return cards


def serialize_board(raw_config: str, header_labels: list, cards: list) -> str:
    """Serialize structured data back to fancy-kanban markdown.

    Args:
        raw_config: The original config block text
        header_labels: Column labels in order (excluding _id)
        cards: List of card dicts

    Returns:
        Complete fancy-kanban markdown block
    """
    # Build label-to-name mapping from header labels
    header_names = [label.lower().replace(" ", "_") for label in header_labels]

    # Header row
    header_row = "| _id | " + " | ".join(header_labels) + " |"

    # Separator row
    sep_row = "| --- | " + " | ".join(["---"] * len(header_labels)) + " |"

    # Data rows
    data_rows = []
    for card in cards:
        cells = [card.get("_id", _generate_id())]
        for i, label in enumerate(header_labels):
            # Try matching by label (case-insensitive) then by derived name
            name = header_names[i]
            # Also try the exact field name from the card
            value = ""
            for key in card:
                if key == "_id":
                    continue
                if key.lower() == name or key.lower() == label.lower():
                    value = card[key]
                    break
            if not value:
                # Try direct name lookup
                value = card.get(name, "")
            cells.append(_escape(value))
        data_rows.append("| " + " | ".join(cells) + " |")

    # Assemble full block
    lines = [
        "```fancy-kanban",
        "---",
        raw_config,
        "---",
        "",
        header_row,
        sep_row,
    ]
    lines.extend(data_rows)
    lines.append("```")

    return "\n".join(lines) + "\n"


def _parse_fields(config: str) -> list:
    """Parse field definitions from config section."""
    fields = []
    in_fields = False

    for line in config.split("\n"):
        stripped = line.strip()
        if stripped.startswith("fields:"):
            in_fields = True
            continue
        if in_fields:
            if stripped.startswith("- "):
                field = _parse_field_line(stripped[2:])
                fields.append(field)
            elif stripped and not stripped.startswith("-"):
                # End of fields block
                in_fields = False
        # Other config keys (title, workflow, lanes) are preserved in raw_config

    return fields


def _parse_field_line(line: str) -> dict:
    """Parse a single field definition line like 'name: status, type: Select, options: inbox|doing|done'."""
    field = {}
    # Split on comma, but respect values that might contain commas in unusual cases
    pairs = re.split(r",\s*", line)
    for pair in pairs:
        if ":" in pair:
            key, value = pair.split(":", 1)
            field[key.strip()] = value.strip()
    return field


def _split_row(line: str) -> list:
    """Split a markdown table row on unescaped pipes, trim cells."""
    # Remove leading/trailing pipes and split on unescaped |
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]

    # Split on | that is not preceded by backslash
    cells = re.split(r"(?<!\\)\|", line)
    return [cell.strip() for cell in cells]


def _escape(value: str) -> str:
    """Escape a cell value for markdown table storage."""
    if not value:
        return ""
    value = value.replace("|", "\\|")
    value = value.replace("\r\n", "<br>")
    value = value.replace("\n", "<br>")
    value = value.replace("\r", "<br>")
    return value


def _unescape(value: str) -> str:
    """Unescape a cell value read from a markdown table."""
    if not value:
        return ""
    value = value.replace("\\|", "|")
    value = value.replace("<br>", "\n")
    return value


def _generate_id(length: int = 8) -> str:
    """Generate a random alphanumeric ID."""
    chars = string.ascii_lowercase + string.digits
    return "".join(random.choices(chars, k=length))
