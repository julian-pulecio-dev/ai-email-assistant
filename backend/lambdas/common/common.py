"""Shared helpers used by all Lambda functions in this app.

Packaged into the shared Lambda Layer so every function can `import common`.
"""
import base64
import json
import logging
import os
import time

import boto3
import jwt
import requests
from boto3.dynamodb.conditions import Key
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

# The Lambda runtime already attaches a handler to the root logger that ships
# stdout to CloudWatch; just set the level so handler.py's `logging.getLogger(__name__)`
# calls are actually emitted.
logging.getLogger().setLevel(logging.INFO)

logger = logging.getLogger(__name__)

_secrets_client = boto3.client("secretsmanager")
_dynamodb = boto3.resource("dynamodb")
_s3 = boto3.client("s3")

_secret_cache: dict[str, dict] = {}

GOOGLE_TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
GOOGLE_ACCESS_TOKEN_EXPIRY_BUFFER_SECONDS = 60
GMAIL_API_BASE = "https://gmail.googleapis.com/gmail/v1/users/me"


class GoogleTokenError(Exception):
    """Raised when exchanging/refreshing Google OAuth tokens fails."""


class GmailHistoryExpired(Exception):
    """Raised when Gmail can no longer diff from the given startHistoryId (HTTP 404).

    Gmail only retains ~7 days of history; callers should re-baseline via get_gmail_history_id().
    """


def get_secret_json(secret_name: str) -> dict:
    """Fetch and cache a JSON-bodied secret from Secrets Manager for the life of the execution environment."""
    if secret_name not in _secret_cache:
        response = _secrets_client.get_secret_value(SecretId=secret_name)
        _secret_cache[secret_name] = json.loads(response["SecretString"])
    return _secret_cache[secret_name]


def verify_google_id_token(token: str, client_id: str) -> dict:
    """Verify a Google ID token's signature, issuer, audience and expiry. Raises ValueError if invalid."""
    return google_id_token.verify_oauth2_token(token, google_requests.Request(), client_id)


def create_session_jwt(*, user_id: str, email: str, secret: str, ttl_minutes: int) -> tuple[str, int]:
    now = int(time.time())
    expires_at = now + ttl_minutes * 60
    payload = {"sub": user_id, "email": email, "iat": now, "exp": expires_at}
    token = jwt.encode(payload, secret, algorithm="HS256")
    return token, expires_at


def decode_session_jwt(token: str, secret: str) -> dict:
    """Raises jwt.PyJWTError (or a subclass) if the token is invalid or expired."""
    return jwt.decode(token, secret, algorithms=["HS256"])


def exchange_google_auth_code(code: str, client_id: str, client_secret: str) -> dict:
    """Exchange an authorization code (from the frontend's auth-code flow, popup/postMessage mode) for tokens."""
    response = requests.post(
        GOOGLE_TOKEN_ENDPOINT,
        data={
            "code": code,
            "client_id": client_id,
            "client_secret": client_secret,
            "redirect_uri": "postmessage",
            "grant_type": "authorization_code",
        },
        timeout=10,
    )
    if not response.ok:
        raise GoogleTokenError(f"code exchange failed: {response.status_code} {response.text}")
    return response.json()


def refresh_google_access_token(refresh_token: str, client_id: str, client_secret: str) -> dict:
    response = requests.post(
        GOOGLE_TOKEN_ENDPOINT,
        data={
            "refresh_token": refresh_token,
            "client_id": client_id,
            "client_secret": client_secret,
            "grant_type": "refresh_token",
        },
        timeout=10,
    )
    if not response.ok:
        raise GoogleTokenError(f"token refresh failed: {response.status_code} {response.text}")
    return response.json()


def get_valid_google_access_token(table_name: str, user_id: str, client_id: str, client_secret: str) -> str:
    """Returns a usable Google access token for the user, refreshing it first if it's expired (or about to be).

    Raises GoogleTokenError if the user has no stored refresh token (they need to sign in again to re-consent).
    """
    user = get_user(table_name, user_id)
    if not user:
        raise GoogleTokenError("user_not_found")

    refresh_token = user.get("google_refresh_token")
    if not refresh_token:
        raise GoogleTokenError("no_refresh_token_on_file")

    expires_at = int(user.get("google_access_token_expires_at") or 0)
    if expires_at - GOOGLE_ACCESS_TOKEN_EXPIRY_BUFFER_SECONDS > int(time.time()):
        return user["google_access_token"]

    logger.info("Google access token expired for user_id=%s, refreshing", user_id)
    tokens = refresh_google_access_token(refresh_token, client_id, client_secret)
    new_access_token = tokens["access_token"]
    new_expires_at = int(time.time()) + int(tokens["expires_in"])

    table = _dynamodb.Table(table_name)
    table.update_item(
        Key={"user_id": user_id},
        UpdateExpression="SET google_access_token = :token, google_access_token_expires_at = :exp",
        ExpressionAttributeValues={":token": new_access_token, ":exp": new_expires_at},
    )
    return new_access_token


def get_user(table_name: str, user_id: str) -> dict | None:
    table = _dynamodb.Table(table_name)
    result = table.get_item(Key={"user_id": user_id})
    return result.get("Item")


def put_user(table_name: str, item: dict) -> None:
    table = _dynamodb.Table(table_name)
    table.put_item(Item=item)


def list_users(table_name: str) -> list[dict]:
    """Returns every user. A full Scan is fine at this project's scale; add a GSI if the table grows large."""
    table = _dynamodb.Table(table_name)
    users = []
    scan_kwargs: dict = {}
    while True:
        response = table.scan(**scan_kwargs)
        users.extend(response.get("Items", []))
        last_key = response.get("LastEvaluatedKey")
        if not last_key:
            break
        scan_kwargs["ExclusiveStartKey"] = last_key
    return users


def update_user_gmail_history_id(table_name: str, user_id: str, history_id: str) -> None:
    table = _dynamodb.Table(table_name)
    table.update_item(
        Key={"user_id": user_id},
        UpdateExpression="SET gmail_history_id = :h",
        ExpressionAttributeValues={":h": history_id},
    )


def get_gmail_history_id(access_token: str) -> str:
    """Returns the Gmail mailbox's current historyId, used as the baseline for incremental sync."""
    response = requests.get(
        f"{GMAIL_API_BASE}/profile",
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=10,
    )
    response.raise_for_status()
    return str(response.json()["historyId"])


def list_new_gmail_message_ids(access_token: str, start_history_id: str) -> tuple[list[str], str]:
    """Returns (new_message_ids, latest_history_id) for messages added since start_history_id.

    Raises GmailHistoryExpired if start_history_id is too old for Gmail to diff against.
    """
    message_ids: list[str] = []
    latest_history_id = start_history_id
    page_token = None

    while True:
        params = {"startHistoryId": start_history_id, "historyTypes": "messageAdded"}
        if page_token:
            params["pageToken"] = page_token

        response = requests.get(
            f"{GMAIL_API_BASE}/history",
            headers={"Authorization": f"Bearer {access_token}"},
            params=params,
            timeout=10,
        )
        if response.status_code == 404:
            logger.warning("Gmail historyId %s expired, needs re-baseline", start_history_id)
            raise GmailHistoryExpired(f"startHistoryId {start_history_id} is no longer valid")
        response.raise_for_status()

        body = response.json()
        latest_history_id = body.get("historyId", latest_history_id)
        for record in body.get("history", []):
            for added in record.get("messagesAdded", []):
                message_ids.append(added["message"]["id"])

        page_token = body.get("nextPageToken")
        if not page_token:
            break

    return message_ids, str(latest_history_id)


def get_gmail_attachment(access_token: str, message_id: str, attachment_id: str) -> bytes:
    """Downloads one attachment's raw bytes from a Gmail message."""
    response = requests.get(
        f"{GMAIL_API_BASE}/messages/{message_id}/attachments/{attachment_id}",
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=10,
    )
    response.raise_for_status()
    data = response.json()["data"]
    padded = data + "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(padded)


def upload_attachment(bucket: str, key: str, data: bytes) -> None:
    _s3.put_object(Bucket=bucket, Key=key, Body=data)


def download_attachment(bucket: str, key: str) -> bytes:
    return _s3.get_object(Bucket=bucket, Key=key)["Body"].read()


def list_labels(table_name: str, user_id: str) -> list[dict]:
    """Returns every label the user has defined."""
    table = _dynamodb.Table(table_name)
    labels = []
    query_kwargs: dict = {"KeyConditionExpression": Key("user_id").eq(user_id)}
    while True:
        response = table.query(**query_kwargs)
        labels.extend(response.get("Items", []))
        last_key = response.get("LastEvaluatedKey")
        if not last_key:
            break
        query_kwargs["ExclusiveStartKey"] = last_key
    return labels


def get_label(table_name: str, user_id: str, label_id: str) -> dict | None:
    table = _dynamodb.Table(table_name)
    result = table.get_item(Key={"user_id": user_id, "label_id": label_id})
    return result.get("Item")


def put_label(table_name: str, item: dict) -> None:
    table = _dynamodb.Table(table_name)
    table.put_item(Item=item)


def delete_label(table_name: str, user_id: str, label_id: str) -> None:
    table = _dynamodb.Table(table_name)
    table.delete_item(Key={"user_id": user_id, "label_id": label_id})


def put_processing_error(table_name: str, item: dict) -> None:
    table = _dynamodb.Table(table_name)
    table.put_item(Item=item)


def get_processing_error(table_name: str, message_id: str) -> dict | None:
    table = _dynamodb.Table(table_name)
    result = table.get_item(Key={"message_id": message_id})
    return result.get("Item")


def create_gmail_label(access_token: str, name: str) -> dict:
    """Creates a Gmail label. Gmail labels have no description field - that's local-only context."""
    response = requests.post(
        f"{GMAIL_API_BASE}/labels",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"name": name, "labelListVisibility": "labelShow", "messageListVisibility": "show"},
        timeout=10,
    )
    response.raise_for_status()
    return response.json()


def update_gmail_label(access_token: str, gmail_label_id: str, name: str) -> dict:
    response = requests.patch(
        f"{GMAIL_API_BASE}/labels/{gmail_label_id}",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"name": name},
        timeout=10,
    )
    response.raise_for_status()
    return response.json()


def delete_gmail_label(access_token: str, gmail_label_id: str) -> None:
    response = requests.delete(
        f"{GMAIL_API_BASE}/labels/{gmail_label_id}",
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=10,
    )
    # A label already missing in Gmail (404) is fine - the end state we want either way.
    if response.status_code not in (200, 204, 404):
        response.raise_for_status()


def add_gmail_labels_to_message(access_token: str, message_id: str, gmail_label_ids: list[str]) -> None:
    response = requests.post(
        f"{GMAIL_API_BASE}/messages/{message_id}/modify",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"addLabelIds": gmail_label_ids},
        timeout=10,
    )
    response.raise_for_status()


def json_response(status_code: int, body: dict) -> dict:
    # CORS headers are added by API Gateway's own cors_configuration, not here.
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value
