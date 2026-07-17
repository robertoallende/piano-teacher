"""piano-teacher Lambda handler.

Triggered by S3 ObjectCreated events on board.md.
Reads the board, finds cards assigned to piano-teacher in 'doing' status,
applies loop guard (flip to done immediately), then processes each card.

LOOP GUARD CONTRACT:
    This handler writes back to board.md (the same file that triggers it).
    To prevent infinite recursion:
    1. On entry, we filter for cards with status=doing AND assignee=piano-teacher
    2. If NO match → exit immediately (this covers the re-trigger case)
    3. If match → flip to done BEFORE any slow work (Bedrock call, lesson generation)
    4. The write-back re-triggers this Lambda, but step 2 catches it (~30ms exit)

    This is safe for a single-user PoC. A true concurrent system would need
    a distributed lock or idempotency token.
"""

import json
import os

import boto3

from board_parser import parse_board, filter_cards, update_card, add_card, serialize_board
from agent import process_card

# Configuration
BUCKET_NAME = os.environ.get("BUCKET_NAME", "piano-teacher")

# Boto3 client
s3_client = boto3.client("s3")


def lambda_handler(event, context):
    """Entry point for S3 ObjectCreated events on board.md."""
    print(f"Received event: {json.dumps(event)}")

    # Step 1: Read board.md from S3
    board_content = _read_board()
    if not board_content:
        print("ERROR: Could not read board.md")
        return {"statusCode": 500, "body": "Failed to read board.md"}

    # Step 2: Parse the board
    try:
        board = parse_board(board_content)
    except ValueError as e:
        print(f"ERROR: Could not parse board: {e}")
        return {"statusCode": 400, "body": f"Failed to parse board: {e}"}

    # Step 3: Find cards matching trigger condition
    matched = filter_cards(board["cards"], status="doing", assignee="piano-teacher")

    if not matched:
        print("No cards with status=doing and assignee=piano-teacher. Exiting (loop guard).")
        return {"statusCode": 200, "body": "No matching cards. Loop guard exit."}

    print(f"Found {len(matched)} card(s) to process: {[c.get('title', c['_id']) for c in matched]}")

    # Step 4: Loop guard — flip each matched card to 'done' immediately
    for card in matched:
        print(f"  Flipping card '{card.get('title', card['_id'])}' to done (loop guard)")
        update_card(board["cards"], card["_id"], status="done")

    # Write the updated board back (this re-triggers us, but the next
    # invocation will find no doing+piano-teacher cards and exit)
    updated_content = serialize_board(
        board["raw_config"], board["header_labels"], board["cards"]
    )
    _write_board(updated_content)
    print("Board updated: matched cards flipped to done.")

    # Step 5: Process each card with the agent
    for card in matched:
        title = card.get("title", card["_id"])
        print(f"  Processing card: '{title}'")

        try:
            written_keys = process_card(card)

            if written_keys:
                # Add lesson cards to the board
                _add_lesson_cards_to_board(card, written_keys)
                print(f"  Done: {len(written_keys)} lessons generated for '{title}'")
            else:
                print(f"  WARNING: No lessons generated for '{title}'")

        except Exception as e:
            print(f"  ERROR processing card '{title}': {e}")

    return {
        "statusCode": 200,
        "body": f"Processed {len(matched)} card(s).",
    }


def _add_lesson_cards_to_board(source_card: dict, lesson_keys: list[str]) -> None:
    """Re-read the board and add lesson cards to inbox."""
    board_content = _read_board()
    if not board_content:
        print("ERROR: Could not re-read board.md to add lesson cards")
        return

    board = parse_board(board_content)
    piece_title = source_card.get("title", "Unknown")

    for key in lesson_keys:
        # Extract lesson number from key like "lessons/moonlight-sonata/lesson-01.md"
        filename = key.split("/")[-1]  # lesson-01.md
        lesson_num = filename.replace("lesson-", "").replace(".md", "")

        add_card(board["cards"], {
            "status": "inbox",
            "title": f"{piece_title} — Lesson {lesson_num}",
            "description": f"Practice lesson {lesson_num} for {piece_title}",
            "assignee": "roberto",
            "session_date": "",
            "docs": key,
        })

    updated_content = serialize_board(
        board["raw_config"], board["header_labels"], board["cards"]
    )
    _write_board(updated_content)
    print(f"  Added {len(lesson_keys)} lesson cards to board.")


def _read_board() -> str | None:
    """Read board.md from S3."""
    try:
        response = s3_client.get_object(Bucket=BUCKET_NAME, Key="board.md")
        return response["Body"].read().decode("utf-8")
    except Exception as e:
        print(f"ERROR reading board.md: {e}")
        return None


def _write_board(content: str) -> None:
    """Write board.md to S3."""
    s3_client.put_object(
        Bucket=BUCKET_NAME,
        Key="board.md",
        Body=content.encode("utf-8"),
        ContentType="text/markdown",
    )
