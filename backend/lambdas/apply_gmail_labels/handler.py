"""Step Functions state 3 (final) of process_new_email - applies the labels matched by
classify_email_labels to the email in the user's Gmail mailbox.
"""
import logging

import common

logger = logging.getLogger(__name__)

TABLE_NAME = common.env("USERS_TABLE_NAME")
GOOGLE_OAUTH_SECRET_NAME = common.env("GOOGLE_OAUTH_SECRET_NAME")


def handler(event, _context):
    user_id = event["user_id"]
    email_id = event["email_id"]
    matched_labels = event.get("matched_labels") or []

    if not matched_labels:
        logger.info("apply_gmail_labels: email_id=%s matched no labels, nothing to apply", email_id)
        return {"user_id": user_id, "email_id": email_id, "applied_labels": []}

    google_credentials = common.get_secret_json(GOOGLE_OAUTH_SECRET_NAME)
    access_token = common.get_valid_google_access_token(
        TABLE_NAME, user_id, google_credentials["client_id"], google_credentials["client_secret"]
    )

    gmail_label_ids = [label["gmail_label_id"] for label in matched_labels]
    common.add_gmail_labels_to_message(access_token, email_id, gmail_label_ids)

    applied_names = [label["name"] for label in matched_labels]
    logger.info(
        "apply_gmail_labels: applied labels=%s to email_id=%s for user_id=%s", applied_names, email_id, user_id
    )
    return {"user_id": user_id, "email_id": email_id, "applied_labels": applied_names}
