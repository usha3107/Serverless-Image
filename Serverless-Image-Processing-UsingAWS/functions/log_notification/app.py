import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    for record in event["Records"]:
        message = json.loads(record["body"])

        log_entry = {
            "image_id": message.get("image_id"),
            "original_image": message.get("original"),
            "processed_image": message.get("processed"),
            "status": message.get("status"),
            "message": "Image processing completed successfully"
        }

        logger.info(json.dumps(log_entry))

    return {"status": "logged"}
