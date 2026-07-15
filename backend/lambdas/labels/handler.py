"""CRUD for the caller's user-defined email categories ("labels").

GET    /labels            - list the caller's labels
POST   /labels             - create a label ({name, description}); also creates a matching Gmail label
PUT    /labels/{label_id}  - rename/re-describe a label; renames the Gmail label if the name changed
DELETE /labels/{label_id}  - delete a label; also deletes the matching Gmail label

Protected by the `authorizer` Lambda; expects requestContext.authorizer.lambda.user_id.
Each label mirrors a real Gmail label (gmail_label_id) so classify_email_labels /
apply_gmail_labels can tag messages with it later. `description` is local-only context
fed to the classifier prompt - Gmail labels have no such field.
"""
import json
import logging
import time
import uuid

import requests

import common

logger = logging.getLogger(__name__)

LABELS_TABLE_NAME = common.env("LABELS_TABLE_NAME")
USERS_TABLE_NAME = common.env("USERS_TABLE_NAME")
GOOGLE_OAUTH_SECRET_NAME = common.env("GOOGLE_OAUTH_SECRET_NAME")


def handler(event, _context):
    authorizer_context = event["requestContext"]["authorizer"]["lambda"]
    user_id = authorizer_context["user_id"]
    method = event["requestContext"]["http"]["method"]
    label_id = (event.get("pathParameters") or {}).get("label_id")

    if method == "GET":
        return _list_labels(user_id)
    if method == "POST":
        return _create_label(user_id, event)
    if method == "PUT":
        return _update_label(user_id, label_id, event)
    if method == "DELETE":
        return _delete_label(user_id, label_id)
    return common.json_response(405, {"error": "method_not_allowed"})


def _list_labels(user_id: str):
    labels = common.list_labels(LABELS_TABLE_NAME, user_id)
    return common.json_response(200, {"labels": [_public_label(label) for label in labels]})


def _create_label(user_id: str, event: dict):
    body, error = _parse_body(event)
    if error:
        return error

    name = (body.get("name") or "").strip()
    description = (body.get("description") or "").strip()
    if not name or not description:
        return common.json_response(400, {"error": "name_and_description_required"})

    existing_labels = common.list_labels(LABELS_TABLE_NAME, user_id)
    if any(label["name"].lower() == name.lower() for label in existing_labels):
        return common.json_response(409, {"error": "label_name_already_exists"})

    access_token = _get_access_token(user_id)
    try:
        gmail_label = common.create_gmail_label(access_token, name)
    except requests.HTTPError as exc:
        if exc.response is not None and exc.response.status_code == 409:
            return common.json_response(409, {"error": "gmail_label_name_already_exists"})
        logger.error("labels: failed to create Gmail label for user_id=%s: %s", user_id, exc)
        return common.json_response(502, {"error": "gmail_api_error"})

    now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    item = {
        "user_id": user_id,
        "label_id": str(uuid.uuid4()),
        "name": name,
        "description": description,
        "gmail_label_id": gmail_label["id"],
        "created_at": now_iso,
        "updated_at": now_iso,
    }
    common.put_label(LABELS_TABLE_NAME, item)
    logger.info("labels: created label_id=%s name=%s for user_id=%s", item["label_id"], name, user_id)
    return common.json_response(201, _public_label(item))


def _update_label(user_id: str, label_id: str, event: dict):
    if not label_id:
        return common.json_response(400, {"error": "missing_label_id"})

    existing = common.get_label(LABELS_TABLE_NAME, user_id, label_id)
    if not existing:
        return common.json_response(404, {"error": "label_not_found"})

    body, error = _parse_body(event)
    if error:
        return error

    name = (body.get("name") or existing["name"]).strip()
    description = (body.get("description") or existing["description"]).strip()
    if not name or not description:
        return common.json_response(400, {"error": "name_and_description_required"})

    name_changed = name.lower() != existing["name"].lower()
    if name_changed:
        other_labels = common.list_labels(LABELS_TABLE_NAME, user_id)
        if any(label["label_id"] != label_id and label["name"].lower() == name.lower() for label in other_labels):
            return common.json_response(409, {"error": "label_name_already_exists"})

        access_token = _get_access_token(user_id)
        try:
            common.update_gmail_label(access_token, existing["gmail_label_id"], name)
        except requests.HTTPError as exc:
            logger.error("labels: failed to rename Gmail label for user_id=%s: %s", user_id, exc)
            return common.json_response(502, {"error": "gmail_api_error"})

    updated_item = {
        **existing,
        "name": name,
        "description": description,
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    common.put_label(LABELS_TABLE_NAME, updated_item)
    logger.info("labels: updated label_id=%s for user_id=%s", label_id, user_id)
    return common.json_response(200, _public_label(updated_item))


def _delete_label(user_id: str, label_id: str):
    if not label_id:
        return common.json_response(400, {"error": "missing_label_id"})

    existing = common.get_label(LABELS_TABLE_NAME, user_id, label_id)
    if not existing:
        return common.json_response(404, {"error": "label_not_found"})

    access_token = _get_access_token(user_id)
    try:
        common.delete_gmail_label(access_token, existing["gmail_label_id"])
    except requests.HTTPError as exc:
        logger.error("labels: failed to delete Gmail label for user_id=%s: %s", user_id, exc)
        return common.json_response(502, {"error": "gmail_api_error"})

    common.delete_label(LABELS_TABLE_NAME, user_id, label_id)
    logger.info("labels: deleted label_id=%s for user_id=%s", label_id, user_id)
    return common.json_response(200, {"deleted": True})


def _parse_body(event: dict):
    try:
        return json.loads(event.get("body") or "{}"), None
    except json.JSONDecodeError:
        return None, common.json_response(400, {"error": "invalid_json_body"})


def _get_access_token(user_id: str) -> str:
    google_credentials = common.get_secret_json(GOOGLE_OAUTH_SECRET_NAME)
    return common.get_valid_google_access_token(
        USERS_TABLE_NAME, user_id, google_credentials["client_id"], google_credentials["client_secret"]
    )


def _public_label(item: dict) -> dict:
    return {
        "id": item["label_id"],
        "name": item["name"],
        "description": item["description"],
        "created_at": item.get("created_at"),
        "updated_at": item.get("updated_at"),
    }
