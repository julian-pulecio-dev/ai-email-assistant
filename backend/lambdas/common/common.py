"""Shared helpers used by all Lambda functions in this app.

Packaged into the shared Lambda Layer so every function can `import common`.
"""
import json
import os
import time

import boto3
import jwt
import requests
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

_secrets_client = boto3.client("secretsmanager")
_dynamodb = boto3.resource("dynamodb")

_secret_cache: dict[str, dict] = {}

GOOGLE_TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
GOOGLE_ACCESS_TOKEN_EXPIRY_BUFFER_SECONDS = 60


class GoogleTokenError(Exception):
    """Raised when exchanging/refreshing Google OAuth tokens fails."""


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
