"""Step Functions state - reached via Catch whenever FetchGmailMessage, ClassifyEmailLabels
or ApplyGmailLabels fails after its retries are exhausted. Records the underlying error,
keyed by the originating SQS message_id, before the execution ends in the terminal
ProcessingFailed (Fail) state.

Native SQS redrive-to-DLQ moves the message body unchanged - it can't carry error
details. Writing the error here (and finalizing it in record_dead_letter once the
message actually lands in the DLQ) is what makes it possible to know *why* a given
dead-lettered event failed instead of just that it did.
"""
import logging
import time

import common

logger = logging.getLogger(__name__)

TABLE_NAME = common.env("PROCESSING_ERRORS_TABLE_NAME")


def handler(event, _context):
    error = event.get("error") or {}
    item = {
        "message_id": event.get("message_id") or "unknown",
        "user_id": event.get("user_id"),
        "email_id": event.get("email_id"),
        "receive_count": event.get("receive_count"),
        "error_type": error.get("Error", "Unknown"),
        "error_cause": error.get("Cause", ""),
        "failed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "dead_lettered": False,
    }
    common.put_processing_error(TABLE_NAME, item)

    logger.error(
        "record_processing_error: message_id=%s email_id=%s error_type=%s",
        item["message_id"],
        item["email_id"],
        item["error_type"],
    )
    return event
