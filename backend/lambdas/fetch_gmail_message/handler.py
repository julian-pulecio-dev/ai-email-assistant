"""Step Functions state 1 of process_new_email - fetches a Gmail message and extracts
the fields needed for classification (date, sender, subject, body, attachments).

Triggered indirectly: check_new_emails publishes {"user_id", "email_id"} onto SQS, an
EventBridge Pipe reads the queue and starts a state machine execution per message. The
UnwrapMessage/ExtractMessageFields Pass states at the front of the state machine already
turn the raw SQS record batch into {message_id, receive_count, user_id, email_id} - this
function (and every state after it) just passes message_id/receive_count through
untouched so a failure anywhere in the pipeline can still be tied back to the SQS
message that caused it (see record_processing_error / record_dead_letter).

Attachments are staged in S3 rather than returned inline: Step Functions state payloads
cap at 256KB, far too small for most attachments, so classify_email_labels reads them
back from S3 to build the Bedrock Converse call.
"""
import base64
import email.utils
import logging

import requests

import common

logger = logging.getLogger(__name__)

TABLE_NAME = common.env("USERS_TABLE_NAME")
GOOGLE_OAUTH_SECRET_NAME = common.env("GOOGLE_OAUTH_SECRET_NAME")
ATTACHMENTS_BUCKET_NAME = common.env("ATTACHMENTS_BUCKET_NAME")

MAX_BODY_CHARS = 4000
MAX_ATTACHMENTS = 5
MAX_ATTACHMENT_BYTES = 4 * 1024 * 1024

# Formats the classify_email_labels' Bedrock Converse call can accept. Anything else
# (zip, exe, audio/video, svg, tiff...) is skipped rather than sent to the model.
IMAGE_FORMATS = {
    "image/png": "png",
    "image/jpeg": "jpeg",
    "image/gif": "gif",
    "image/webp": "webp",
}
DOCUMENT_FORMATS = {
    "application/pdf": "pdf",
    "text/csv": "csv",
    "application/msword": "doc",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "text/html": "html",
    "text/markdown": "md",
    "text/plain": "txt",
    "application/vnd.ms-excel": "xls",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
}


class GmailMessageNotFound(Exception):
    """Raised when Gmail's history reported messageAdded for an id that 404s on fetch.

    This happens when the message is deleted/moved (e.g. a spam filter auto-trashes it)
    between check_new_emails noting it and this state running - it's expected, not a
    transient failure, so the state machine shouldn't retry it.
    """


def handler(event, _context):
    message_id = event.get("message_id")
    receive_count = event.get("receive_count")
    user_id = event["user_id"]
    email_id = event["email_id"]

    google_credentials = common.get_secret_json(GOOGLE_OAUTH_SECRET_NAME)
    access_token = common.get_valid_google_access_token(
        TABLE_NAME, user_id, google_credentials["client_id"], google_credentials["client_secret"]
    )

    response = requests.get(
        f"{common.GMAIL_API_BASE}/messages/{email_id}",
        headers={"Authorization": f"Bearer {access_token}"},
        params={"format": "full"},
        timeout=10,
    )
    if response.status_code == 404:
        logger.warning("fetch_gmail_message: email_id=%s not found (deleted/moved?), skipping", email_id)
        raise GmailMessageNotFound(f"email_id {email_id} not found for user_id {user_id}")
    response.raise_for_status()
    detail = response.json()

    payload = detail.get("payload", {})
    header_map = {h["name"]: h["value"] for h in payload.get("headers", [])}
    date_header = header_map.get("Date", "")

    attachments = _stage_attachments(payload, access_token, user_id, email_id)

    logger.info(
        "fetch_gmail_message: fetched email_id=%s for user_id=%s with %d attachment(s)",
        email_id,
        user_id,
        len(attachments),
    )

    return {
        "message_id": message_id,
        "receive_count": receive_count,
        "user_id": user_id,
        "email_id": email_id,
        "date": _normalize_date(date_header),
        "sender": header_map.get("From", ""),
        "subject": header_map.get("Subject", ""),
        "body": _extract_body(payload)[:MAX_BODY_CHARS],
        "attachments": attachments,
    }


def _normalize_date(date_header: str) -> str:
    if not date_header:
        return ""
    try:
        return email.utils.parsedate_to_datetime(date_header).isoformat()
    except (TypeError, ValueError):
        return date_header


def _extract_body(payload: dict) -> str:
    """Walks the MIME tree for the first text/plain part, falling back to text/html."""
    return _find_part(payload, "text/plain") or _find_part(payload, "text/html") or ""


def _find_part(payload: dict, mime_type: str) -> str | None:
    if payload.get("mimeType") == mime_type:
        data = payload.get("body", {}).get("data")
        return _decode_base64url(data) if data else None
    for part in payload.get("parts", []) or []:
        found = _find_part(part, mime_type)
        if found:
            return found
    return None


def _stage_attachments(payload: dict, access_token: str, user_id: str, email_id: str) -> list[dict]:
    candidates: list[dict] = []
    _collect_attachment_parts(payload, candidates)

    staged = []
    for index, part in enumerate(candidates[:MAX_ATTACHMENTS]):
        mime_type = part.get("mimeType", "")
        kind, fmt = _bedrock_format_for(mime_type)
        if not fmt:
            logger.info("fetch_gmail_message: skipping unsupported attachment type=%s", mime_type)
            continue

        body = part.get("body", {})
        if body.get("size", 0) > MAX_ATTACHMENT_BYTES:
            logger.info("fetch_gmail_message: skipping oversized attachment (%s bytes)", body.get("size"))
            continue

        try:
            if body.get("data"):
                data = _decode_base64url_bytes(body["data"])
            else:
                data = common.get_gmail_attachment(access_token, email_id, body["attachmentId"])
        except requests.RequestException as exc:
            logger.warning("fetch_gmail_message: failed to download attachment: %s", exc)
            continue

        if len(data) > MAX_ATTACHMENT_BYTES:
            logger.info("fetch_gmail_message: skipping oversized attachment (%d bytes)", len(data))
            continue

        filename = _sanitize_filename(part.get("filename") or f"attachment-{index}")
        s3_key = f"{user_id}/{email_id}/{index}-{filename}"
        common.upload_attachment(ATTACHMENTS_BUCKET_NAME, s3_key, data)
        staged.append({"s3_key": s3_key, "filename": filename, "kind": kind, "format": fmt})

    return staged


def _collect_attachment_parts(part: dict, out: list[dict]) -> None:
    body = part.get("body", {})
    if part.get("filename") and (body.get("attachmentId") or body.get("data")):
        out.append(part)
    for child in part.get("parts", []) or []:
        _collect_attachment_parts(child, out)


def _bedrock_format_for(mime_type: str) -> tuple[str, str] | tuple[None, None]:
    if mime_type in IMAGE_FORMATS:
        return "image", IMAGE_FORMATS[mime_type]
    if mime_type in DOCUMENT_FORMATS:
        return "document", DOCUMENT_FORMATS[mime_type]
    return None, None


def _sanitize_filename(name: str) -> str:
    safe = "".join(c if c.isalnum() or c in ".-_" else "_" for c in name)
    return safe[:100] or "attachment"


def _decode_base64url_bytes(data: str) -> bytes:
    padded = data + "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(padded)


def _decode_base64url(data: str) -> str:
    return _decode_base64url_bytes(data).decode("utf-8", errors="replace")
