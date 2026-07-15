"""Step Functions state 2 of process_new_email - asks Amazon Nova Lite (via Bedrock's
Converse API) which of the user's defined labels (if any) apply to the email fetched
by fetch_gmail_message, including any image/document attachments it staged in S3.
apply_gmail_labels (state 3) tags the message with the result.
"""
import json
import logging

import boto3
import botocore.exceptions

import common

logger = logging.getLogger(__name__)

BEDROCK_MODEL_ID = common.env("BEDROCK_MODEL_ID")
LABELS_TABLE_NAME = common.env("LABELS_TABLE_NAME")
ATTACHMENTS_BUCKET_NAME = common.env("ATTACHMENTS_BUCKET_NAME")

SYSTEM_PROMPT_TEMPLATE = (
    "You are an email triage assistant. Given an email's date, sender, subject, body, and any "
    "attached images or documents, decide which of the following user-defined categories apply to "
    "it (zero, one, or several):\n"
    "{label_list}\n"
    "Respond with ONLY a JSON object, no other text, in exactly this shape: "
    '{{"matched_label_ids": ["<id>", ...], "reasoning": "<one sentence>"}}. '
    "Use the exact id values given above, and return an empty list if none apply."
)

_bedrock = boto3.client("bedrock-runtime")


def handler(event, _context):
    message_id = event.get("message_id")
    receive_count = event.get("receive_count")
    user_id = event["user_id"]
    email_id = event["email_id"]
    labels = common.list_labels(LABELS_TABLE_NAME, user_id)

    if not labels:
        logger.info("classify_email_labels: user_id=%s has no labels defined, skipping", user_id)
        return {
            "message_id": message_id,
            "receive_count": receive_count,
            "user_id": user_id,
            "email_id": email_id,
            "matched_labels": [],
        }

    labels_by_id = {label["label_id"]: label for label in labels}
    label_list = "\n".join(f'- id={l["label_id"]} name="{l["name"]}": {l["description"]}' for l in labels)

    user_message = (
        f"Date: {event.get('date', '')}\n"
        f"From: {event.get('sender', '')}\n"
        f"Subject: {event.get('subject', '')}\n"
        f"Body:\n{event.get('body', '')}"
    )
    content = [{"text": user_message}] + _attachment_content_blocks(event.get("attachments") or [])

    response = _bedrock.converse(
        modelId=BEDROCK_MODEL_ID,
        system=[{"text": SYSTEM_PROMPT_TEMPLATE.format(label_list=label_list)}],
        messages=[{"role": "user", "content": content}],
        inferenceConfig={"maxTokens": 300, "temperature": 0},
    )

    raw_text = response["output"]["message"]["content"][0]["text"]
    matched_ids = _parse_matched_label_ids(raw_text, labels_by_id.keys())

    matched_labels = [
        {
            "label_id": label_id,
            "name": labels_by_id[label_id]["name"],
            "gmail_label_id": labels_by_id[label_id]["gmail_label_id"],
        }
        for label_id in matched_ids
    ]

    logger.info(
        "classify_email_labels: email_id=%s (%d attachment(s)) matched labels=%s",
        email_id,
        len(content) - 1,
        [label["name"] for label in matched_labels],
    )

    return {
        "message_id": message_id,
        "receive_count": receive_count,
        "user_id": user_id,
        "email_id": email_id,
        "matched_labels": matched_labels,
    }


def _attachment_content_blocks(attachments: list[dict]) -> list[dict]:
    blocks = []
    for index, attachment in enumerate(attachments):
        try:
            data = common.download_attachment(ATTACHMENTS_BUCKET_NAME, attachment["s3_key"])
        except botocore.exceptions.ClientError as exc:
            logger.warning("classify_email_labels: could not read attachment from S3: %s", exc)
            continue

        source = {"bytes": data}
        if attachment["kind"] == "image":
            blocks.append({"image": {"format": attachment["format"], "source": source}})
        else:
            blocks.append(
                {"document": {"format": attachment["format"], "name": f"attachment-{index}", "source": source}}
            )
    return blocks


def _parse_matched_label_ids(raw_text: str, valid_ids) -> list[str]:
    try:
        start = raw_text.index("{")
        end = raw_text.rindex("}") + 1
        parsed = json.loads(raw_text[start:end])
        valid_ids = set(valid_ids)
        return [label_id for label_id in parsed.get("matched_label_ids", []) if label_id in valid_ids]
    except (ValueError, json.JSONDecodeError):
        logger.error("classify_email_labels: could not parse model output: %s", raw_text)
        return []
