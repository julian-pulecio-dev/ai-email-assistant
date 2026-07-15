"""GET /gmail/messages - lists the authenticated user's most recent Gmail messages.

Protected by the `authorizer` Lambda; expects requestContext.authorizer.lambda.user_id.
Demonstrates that the stored Google access/refresh tokens actually work for
calling a Google API on the user's behalf.
"""
import logging

import requests

import common

logger = logging.getLogger(__name__)

TABLE_NAME = common.env("USERS_TABLE_NAME")
GOOGLE_OAUTH_SECRET_NAME = common.env("GOOGLE_OAUTH_SECRET_NAME")

GMAIL_API_BASE = "https://gmail.googleapis.com/gmail/v1/users/me"
MAX_RESULTS = 10


def handler(event, _context):
    authorizer_context = event["requestContext"]["authorizer"]["lambda"]
    user_id = authorizer_context["user_id"]

    google_credentials = common.get_secret_json(GOOGLE_OAUTH_SECRET_NAME)

    try:
        access_token = common.get_valid_google_access_token(
            TABLE_NAME, user_id, google_credentials["client_id"], google_credentials["client_secret"]
        )
    except common.GoogleTokenError as exc:
        logger.warning("gmail_messages: access revoked for user_id=%s: %s", user_id, exc)
        return common.json_response(401, {"error": "google_access_revoked"})

    headers = {"Authorization": f"Bearer {access_token}"}

    list_response = requests.get(
        f"{GMAIL_API_BASE}/messages",
        headers=headers,
        params={"maxResults": MAX_RESULTS},
        timeout=10,
    )
    if not list_response.ok:
        logger.error(
            "gmail_messages: list request failed for user_id=%s: %s %s",
            user_id,
            list_response.status_code,
            list_response.text,
        )
        return common.json_response(502, {"error": "gmail_api_error"})

    message_ids = [m["id"] for m in list_response.json().get("messages", [])]

    messages = []
    for message_id in message_ids:
        detail_response = requests.get(
            f"{GMAIL_API_BASE}/messages/{message_id}",
            headers=headers,
            params={"format": "metadata", "metadataHeaders": ["Subject", "From"]},
            timeout=10,
        )
        if not detail_response.ok:
            logger.warning(
                "gmail_messages: detail request failed for message_id=%s: %s",
                message_id,
                detail_response.status_code,
            )
            continue

        detail = detail_response.json()
        header_map = {h["name"]: h["value"] for h in detail.get("payload", {}).get("headers", [])}
        messages.append(
            {
                "id": message_id,
                "subject": header_map.get("Subject", "(no subject)"),
                "from": header_map.get("From", ""),
                "snippet": detail.get("snippet", ""),
            }
        )

    logger.info("gmail_messages: returned %d messages for user_id=%s", len(messages), user_id)
    return common.json_response(200, {"messages": messages})
