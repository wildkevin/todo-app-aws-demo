# Hello World stub — proves Lambda can write to and read from DynamoDB.
# Will be replaced with real to-do CRUD logic in a later step.
import json
import os
from datetime import datetime, timezone

import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
table = boto3.resource("dynamodb").Table(TABLE_NAME)


def handler(event, context):
    item = {
        "id": "hello-world",
        "message": "Hello from Lambda!",
        "writtenAt": datetime.now(timezone.utc).isoformat(),
    }

    table.put_item(Item=item)
    result = table.get_item(Key={"id": "hello-world"})

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(
            {
                "message": "Hello World from the To-Do App backend!",
                "readBackFromDynamoDB": result.get("Item"),
            }
        ),
    }
