"""tools.py — Strands agent tools for reading/writing the kanban board and S3 files."""

import os

import boto3
from strands import tool

# Configuration from environment
BUCKET_NAME = os.environ.get("BUCKET_NAME", "piano-teacher")

# Boto3 client (reused across warm Lambda invocations)
s3_client = boto3.client("s3")


@tool
def read_board() -> str:
    """Read the kanban board file (board.md) from S3.

    Returns the raw markdown content of the board file. Use this to inspect
    cards, check their status, and determine what work needs to be done.

    Returns:
        The full markdown content of board.md.
    """
    response = s3_client.get_object(Bucket=BUCKET_NAME, Key="board.md")
    return response["Body"].read().decode("utf-8")


@tool
def write_board(content: str) -> str:
    """Write updated content to the kanban board file (board.md) in S3.

    Use this after modifying card statuses or adding new cards to persist
    changes to the board.

    Args:
        content: The full markdown content to write to board.md.

    Returns:
        Confirmation message.
    """
    s3_client.put_object(
        Bucket=BUCKET_NAME,
        Key="board.md",
        Body=content.encode("utf-8"),
        ContentType="text/markdown",
    )
    return "board.md updated successfully."


@tool
def read_score(file_path: str) -> bytes:
    """Read a PDF score file from the scores/ directory in S3.

    Args:
        file_path: The filename of the score (e.g. 'moonlight.pdf').
                   Will be read from scores/<file_path>.

    Returns:
        The raw bytes of the PDF file.
    """
    key = f"scores/{file_path}" if not file_path.startswith("scores/") else file_path
    response = s3_client.get_object(Bucket=BUCKET_NAME, Key=key)
    return response["Body"].read()


@tool
def write_lesson(piece_id: str, lesson_number: int, content: str) -> str:
    """Write a lesson markdown file to S3.

    Args:
        piece_id: The piece identifier (used as directory name).
        lesson_number: The lesson number (used in filename, zero-padded).
        content: The full markdown content of the lesson file.

    Returns:
        The S3 key of the written file.
    """
    key = f"lessons/{piece_id}/lesson-{lesson_number:02d}.md"
    s3_client.put_object(
        Bucket=BUCKET_NAME,
        Key=key,
        Body=content.encode("utf-8"),
        ContentType="text/markdown",
    )
    return f"Written: {key}"
