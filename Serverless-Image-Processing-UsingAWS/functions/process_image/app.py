import json
import os
import boto3
from PIL import Image
from io import BytesIO

s3 = boto3.client("s3")
sqs = boto3.client("sqs")

UPLOADS_BUCKET = os.environ["UPLOADS_BUCKET"]
PROCESSED_BUCKET = os.environ["PROCESSED_BUCKET"]
RESULTS_QUEUE_URL = os.environ["RESULTS_QUEUE_URL"]


def lambda_handler(event, context):
    for record in event["Records"]:
        message = json.loads(record["body"])

        bucket = message["bucket"]
        key = message["key"]
        image_id = message["image_id"]

        obj = s3.get_object(Bucket=bucket, Key=key)
        image_bytes = obj["Body"].read()

        image = Image.open(BytesIO(image_bytes))
        image = image.resize((256, 256))

        buffer = BytesIO()
        image.save(buffer, format="PNG")
        buffer.seek(0)

        processed_key = f"processed/{image_id}.png"

        s3.put_object(
            Bucket=PROCESSED_BUCKET,
            Key=processed_key,
            Body=buffer,
            ContentType="image/png"
        )

        sqs.send_message(
            QueueUrl=RESULTS_QUEUE_URL,
            MessageBody=json.dumps({
                "image_id": image_id,
                "status": "processed",
                "output_key": processed_key
            })
        )

    return {"status": "ok"}
