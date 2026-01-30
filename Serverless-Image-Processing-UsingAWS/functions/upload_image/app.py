import json
import os
import uuid
import base64
import boto3

s3 = boto3.client("s3")
sqs = boto3.client("sqs")

UPLOADS_BUCKET = os.environ["UPLOADS_BUCKET"]
REQUESTS_QUEUE_URL = os.environ["REQUESTS_QUEUE_URL"]


def lambda_handler(event, context):
    try:
        # API Gateway ALWAYS sends binary as base64
        if "body" not in event or not event.get("isBase64Encoded", False):
            return response(400, "Binary body must be base64 encoded")

        # Decode image bytes
        image_bytes = base64.b64decode(event["body"])

        image_id = str(uuid.uuid4())
        object_key = f"{image_id}.png"

        # Upload to S3
        s3.put_object(
            Bucket=UPLOADS_BUCKET,
            Key=object_key,
            Body=image_bytes,
            ContentType="image/png"
        )

        # Send message to SQS
        sqs.send_message(
            QueueUrl=REQUESTS_QUEUE_URL,
            MessageBody=json.dumps({
                "bucket": UPLOADS_BUCKET,
                "key": object_key,
                "image_id": image_id
            })
        )

        return response(202, {
            "message": "Image accepted for processing",
            "image_id": image_id
        })

    except Exception as e:
        return response(500, str(e))


def response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body)
    }
