"""SQS trigger on new_emails-dlq - runs whenever a message has exhausted every redrive
attempt and truly dead-lettered. Finalizes the error record record_processing_error
wrote during the state machine's failure path (same message_id), marking it as
dead-lettered so it's clear this one is done retrying, not just failed once.

If no such record exists - e.g. the pipe couldn't even start an execution for it, so
the state machine's failure path never ran - writes a fallback "Unknown" record instead,
so every event that reaches the DLQ ends up with *some* associated error, per the ask.
"""
import json
import logging
import time

import common

logger = logging.getLogger(__name__)

TABLE_NAME = common.env("PROCESSING_ERRORS_TABLE_NAME")


def handler(event, _context):
    records = event.get("Records", [])
    for record in records:
        _handle_record(record)
    return {"processed": len(records)}


def _handle_record(record: dict) -> None:
    message_id = record.get("messageId")

    try:
        body = json.loads(record.get("body") or "{}")
    except json.JSONDecodeError:
        body = {}

    existing = common.get_processing_error(TABLE_NAME, message_id) if message_id else None
    now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    item = existing or {
        "message_id": message_id or "unknown",
        "user_id": body.get("user_id"),
        "email_id": body.get("email_id"),
        "receive_count": (record.get("attributes") or {}).get("ApproximateReceiveCount"),
        "error_type": "Unknown",
        "error_cause": (
            "No processing-error record found for this message_id - it may have failed "
            "before the state machine ran (e.g. the pipe couldn't start an execution)."
        ),
        "failed_at": now_iso,
    }
    item["dead_lettered"] = True
    item["dead_lettered_at"] = now_iso

    common.put_processing_error(TABLE_NAME, item)

    logger.error(
        "record_dead_letter: message_id=%s email_id=%s error_type=%s",
        item["message_id"],
        item.get("email_id"),
        item.get("error_type"),
    )
