"""Runs on a 5-minute EventBridge schedule.

For every registered user, diffs their mailbox's current Gmail historyId against
the one stored at last run (see google_login/handler.py). Any newly added
messages are pushed onto SQS - one message per email - for downstream
processing; messages that repeatedly fail to be consumed land in the queue's DLQ.
"""
import json
import logging

import boto3
import requests

import common

logger = logging.getLogger(__name__)

TABLE_NAME = common.env("USERS_TABLE_NAME")
GOOGLE_OAUTH_SECRET_NAME = common.env("GOOGLE_OAUTH_SECRET_NAME")
NEW_EMAILS_QUEUE_URL = common.env("NEW_EMAILS_QUEUE_URL")

_sqs = boto3.client("sqs")


def handler(_event, _context):
    google_credentials = common.get_secret_json(GOOGLE_OAUTH_SECRET_NAME)
    users = common.list_users(TABLE_NAME)
    logger.info("check_new_emails: checking %d users", len(users))

    total_new_messages = 0
    for user in users:
        total_new_messages += _check_user(user, google_credentials)

    logger.info(
        "check_new_emails: done, checked %d users, enqueued %d new messages", len(users), total_new_messages
    )
    return {"checked_users": len(users), "new_messages": total_new_messages}


def _check_user(user: dict, google_credentials: dict) -> int:
    user_id = user["user_id"]
    if not user.get("google_refresh_token"):
        logger.info("check_new_emails: user_id=%s has no refresh token, skipping", user_id)
        return 0

    try:
        access_token = common.get_valid_google_access_token(
            TABLE_NAME, user_id, google_credentials["client_id"], google_credentials["client_secret"]
        )
    except common.GoogleTokenError as exc:
        logger.warning("check_new_emails: could not get access token for user_id=%s: %s", user_id, exc)
        return 0

    start_history_id = user.get("gmail_history_id")
    if not start_history_id:
        logger.info("check_new_emails: user_id=%s has no stored historyId, bootstrapping", user_id)
        _bootstrap_history_id(user_id, access_token)
        return 0

    try:
        message_ids, latest_history_id = common.list_new_gmail_message_ids(access_token, start_history_id)
    except common.GmailHistoryExpired:
        logger.info("check_new_emails: user_id=%s historyId expired, bootstrapping", user_id)
        _bootstrap_history_id(user_id, access_token)
        return 0
    except requests.RequestException as exc:
        logger.error("check_new_emails: Gmail history.list failed for user_id=%s: %s", user_id, exc)
        return 0

    for message_id in message_ids:
        _sqs.send_message(
            QueueUrl=NEW_EMAILS_QUEUE_URL,
            MessageBody=json.dumps({"user_id": user_id, "email_id": message_id}),
        )
    if message_ids:
        logger.info(
            "check_new_emails: user_id=%s found %d new message(s): %s",
            user_id,
            len(message_ids),
            message_ids,
        )

    if latest_history_id != start_history_id:
        common.update_user_gmail_history_id(TABLE_NAME, user_id, latest_history_id)
        logger.info(
            "check_new_emails: user_id=%s historyId %s -> %s", user_id, start_history_id, latest_history_id
        )

    return len(message_ids)


def _bootstrap_history_id(user_id: str, access_token: str) -> None:
    """No prior historyId (or Gmail expired it) - record the current one without enqueueing,
    since there's nothing to diff against yet."""
    try:
        history_id = common.get_gmail_history_id(access_token)
    except requests.RequestException as exc:
        logger.error("check_new_emails: failed to bootstrap historyId for user_id=%s: %s", user_id, exc)
        return
    common.update_user_gmail_history_id(TABLE_NAME, user_id, history_id)
