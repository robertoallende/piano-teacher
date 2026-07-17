"""piano-teacher Lambda handler.

Triggered by S3 ObjectCreated events on board.md.
Reads the board, finds cards assigned to piano-teacher in 'doing' status,
applies loop guard (flip to done immediately), then processes each card.
"""

import json
import os

import boto3

from board_parser import parse_board, filter_cards, update_card, serialize_board

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

    # Step 5: Process each card (actual agent work — deferred to Unit 04)
    for card in matched:
        print(f"  TODO: Process card '{card.get('title', card['_id'])}' — docs: {card.get('docs', 'none')}")

    return {
        "statusCode": 200,
        "body": f"Processed {len(matched)} card(s).",
    }


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
