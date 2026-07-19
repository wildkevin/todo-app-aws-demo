import json
import os
from datetime import datetime, timezone

import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
table = boto3.resource("dynamodb").Table(TABLE_NAME)


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


def handler(event, context):
    method = event["requestContext"]["http"]["method"]
    path = event["rawPath"]
    segments = [s for s in path.split("/") if s]

    if method == "GET" and segments == ["todos"]:
        return list_todos()

    return _error(404, "not found")
