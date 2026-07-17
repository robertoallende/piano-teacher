"""piano-teacher Lambda handler — skeleton."""

import json


def lambda_handler(event, context):
    """Entry point for S3 ObjectModified events on board.md."""
    print(f"Received event: {json.dumps(event)}")
    return {"statusCode": 200, "body": "piano-teacher handler invoked"}
