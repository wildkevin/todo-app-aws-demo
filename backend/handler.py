import json
import os
import uuid
from datetime import datetime, timezone

import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
table = boto3.resource("dynamodb").Table(TABLE_NAME)

MAX_TEXT_LENGTH = 500


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def _error(status_code, message):
    return _response(status_code, {"error": message})


def list_todos():
    items = table.scan().get("Items", [])
    items.sort(key=lambda item: item["createdAt"])
    return _response(200, items)


def create_todo(body_raw):
    try:
        body = json.loads(body_raw or "{}")
    except json.JSONDecodeError:
        return _error(400, "invalid JSON")

    text = body.get("text")
    if not isinstance(text, str):
        return _error(400, "text is required")
    text = text.strip()
    if not text:
        return _error(400, "text must not be empty")
    if len(text) > MAX_TEXT_LENGTH:
        return _error(400, f"text must be {MAX_TEXT_LENGTH} characters or fewer")

    item = {
        "id": str(uuid.uuid4()),
        "text": text,
        "completed": False,
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }
    table.put_item(Item=item)
    return _response(201, item)


def handler(event, context):
    method = event["requestContext"]["http"]["method"]
    path = event["rawPath"]
    segments = [s for s in path.split("/") if s]

    if method == "GET" and segments == ["todos"]:
        return list_todos()

    if method == "POST" and segments == ["todos"]:
        return create_todo(event.get("body"))

    return _error(404, "not found")
