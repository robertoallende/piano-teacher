"""agent.py — Strands Agent for piano-teacher lesson generation."""

import json
import os
import re

import boto3
from strands import Agent
from strands.models import BedrockModel

from board_parser import parse_board, add_card, serialize_board
from tools import write_lesson

# Configuration
BUCKET_NAME = os.environ.get("BUCKET_NAME", "piano-teacher")
MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "us.anthropic.claude-sonnet-4-5-20250929-v1:0")

s3_client = boto3.client("s3")

SYSTEM_PROMPT = """You are an expert piano teacher. Your job is to analyze a piece of sheet music and create a structured practice plan for a beginner student.

When given a PDF score, you will:
1. Identify the piece (title, key, time signature, tempo)
2. Assess overall difficulty for a beginner
3. Decompose the piece into lessons — each lesson covers a short passage (typically 4-8 bars), focuses on one technical challenge, and is scoped to what a beginner can learn in one practice session
4. For each lesson, generate ABC notation for the relevant bars

Guidelines:
- Fewer lessons for simple/short pieces, more for complex/long ones
- Early lessons should be hands-separate; later lessons hands-together
- Start with slow tempos and build up
- Flag specific difficulties (e.g. left-hand-leap, syncopation, octave stretch)
- ABC notation should be accurate and playable
- Each lesson must be self-contained and have a clear "done when" criterion

Respond ONLY with valid JSON in this exact format:
{
  "piece_title": "...",
  "piece_id": "...",
  "key": "...",
  "time_signature": "...",
  "lessons": [
    {
      "lesson_number": 1,
      "title": "...",
      "bars": "1-4",
      "hands": "separate",
      "target_tempo": "60 bpm",
      "difficulty_flags": ["..."],
      "focus": "...",
      "abc_notation": "X:1\\nT: ...\\nM: ...\\nL: ...\\nK: ...\\n...",
      "practice_steps": ["Step 1...", "Step 2..."],
      "watch_out_for": "...",
      "done_when": "..."
    }
  ]
}

Do not include any text outside the JSON. Do not use markdown fencing around the JSON."""


def process_card(card: dict) -> list[str]:
    """Process a single card: read PDF, analyze score, generate lessons.

    Args:
        card: A board card dict with at least 'docs' and 'title' fields.

    Returns:
        List of S3 keys for written lesson files.
    """
    docs = card.get("docs", "")
    title = card.get("title", "unknown")

    if not docs:
        print(f"ERROR: Card '{title}' has no docs field")
        return []

    print(f"Processing card: '{title}', docs: {docs}")

    # Step 1: Read the PDF from S3
    pdf_bytes = _read_pdf(docs)
    if not pdf_bytes:
        print(f"ERROR: Could not read PDF: {docs}")
        return []

    print(f"  PDF read: {len(pdf_bytes)} bytes")

    # Step 2: Send to Bedrock via Strands Agent for analysis
    lessons_data = _analyze_score(pdf_bytes, docs)
    if not lessons_data:
        print(f"ERROR: Could not analyze score for '{title}'")
        return []

    piece_id = lessons_data.get("piece_id", _slugify(title))
    lessons = lessons_data.get("lessons", [])
    print(f"  Analysis complete: {len(lessons)} lessons for piece_id='{piece_id}'")

    # Step 3: Write lesson files to S3
    written_keys = []
    for lesson in lessons:
        lesson_num = lesson["lesson_number"]
        content = _format_lesson_markdown(piece_id, lesson)
        key = f"lessons/{piece_id}/lesson-{lesson_num:02d}.md"

        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=key,
            Body=content.encode("utf-8"),
            ContentType="text/markdown",
        )
        written_keys.append(key)
        print(f"  Written: {key}")

    return written_keys


def _read_pdf(docs_ref: str) -> bytes | None:
    """Read a PDF file from S3 scores/ directory."""
    key = f"scores/{docs_ref}" if not docs_ref.startswith("scores/") else docs_ref
    try:
        response = s3_client.get_object(Bucket=BUCKET_NAME, Key=key)
        return response["Body"].read()
    except Exception as e:
        print(f"ERROR reading PDF '{key}': {e}")
        return None


def _analyze_score(pdf_bytes: bytes, filename: str) -> dict | None:
    """Send PDF to Bedrock Claude via Strands Agent for analysis."""
    model = BedrockModel(
        model_id=MODEL_ID,
        region_name="us-east-1",
        max_tokens=16000,
    )

    agent = Agent(
        model=model,
        system_prompt=SYSTEM_PROMPT,
        tools=[],
        callback_handler=None,
    )

    # Build multimodal message with PDF document
    user_content = [
        {
            "document": {
                "format": "pdf",
                "name": filename.replace(".pdf", ""),
                "source": {"bytes": pdf_bytes},
            }
        },
        {
            "text": (
                "Analyze this piano score and create a structured practice plan "
                "for a beginner student. Respond with the JSON lesson decomposition."
            )
        },
    ]

    try:
        # Pass multimodal content directly as the message
        result = agent(user_content)

        # Parse JSON from response — result.message may be a dict or string
        response_text = ""
        msg = result.message
        if isinstance(msg, dict):
            # Strands returns {"role": "assistant", "content": [{"text": "..."}]}
            content = msg.get("content", [])
            for block in content:
                if isinstance(block, dict) and "text" in block:
                    response_text += block["text"]
        else:
            response_text = str(msg)

        return _parse_json_response(response_text)

    except Exception as e:
        print(f"ERROR from Bedrock: {e}")
        return None


def _parse_json_response(text: str) -> dict | None:
    """Extract JSON from the model response, handling potential markdown fencing."""
    # Try direct parse first
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # Try extracting from markdown code fence
    match = re.search(r"```(?:json)?\s*\n?(.*?)\n?```", text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(1))
        except json.JSONDecodeError:
            pass

    # Try finding JSON object in the text
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            pass

    print(f"ERROR: Could not parse JSON from response: {text[:500]}")
    return None


def _format_lesson_markdown(piece_id: str, lesson: dict) -> str:
    """Format a lesson dict into the markdown contract from PRD §5.1."""
    flags = lesson.get("difficulty_flags", [])
    flags_yaml = json.dumps(flags)

    abc = lesson.get("abc_notation", "")
    # Ensure abc newlines are actual newlines
    abc = abc.replace("\\n", "\n")

    steps = lesson.get("practice_steps", [])
    steps_md = "\n".join(f"{i+1}. {step}" for i, step in enumerate(steps))

    return f"""---
piece_id: "{piece_id}"
lesson_number: {lesson['lesson_number']}
title: "{lesson['title']}"
bars: "{lesson.get('bars', '')}"
hands: "{lesson.get('hands', 'separate')}"
target_tempo: "{lesson.get('target_tempo', '')}"
difficulty_flags: {flags_yaml}
---

# Lesson {lesson['lesson_number']}: {lesson['title']}

## Focus
{lesson.get('focus', '')}

## Notation

```abc
{abc}
```

## Practice Steps
{steps_md}

## Watch Out For
{lesson.get('watch_out_for', '')}

## Done When
{lesson.get('done_when', '')}
"""


def _slugify(title: str) -> str:
    """Convert a title to a filesystem-safe slug."""
    slug = title.lower().strip()
    slug = re.sub(r"[^a-z0-9]+", "-", slug)
    slug = slug.strip("-")
    return slug
