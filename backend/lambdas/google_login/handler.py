"""POST /auth/google - exchanges a Google OAuth authorization code and starts a session.

Request body: { "code": "<authorization code from the frontend's auth-code flow>" }
Response body: { "token": "<session JWT>", "expires_at": <epoch seconds>, "user": {...} }

Exchanging the code (instead of just verifying an ID token) also grants us a
Google access_token/refresh_token with whatever API scopes the frontend
requested, so the app can call Google APIs (e.g. Gmail) on the user's behalf
later - see get_valid_google_access_token() in common.py.
"""
import json
import time

import common

TABLE_NAME = common.env("USERS_TABLE_NAME")
GOOGLE_OAUTH_SECRET_NAME = common.env("GOOGLE_OAUTH_SECRET_NAME")
SESSION_JWT_SECRET_NAME = common.env("SESSION_JWT_SECRET_NAME")
SESSION_JWT_TTL_MINUTES = int(common.env("SESSION_JWT_TTL_MINUTES"))


def handler(event, _context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return common.json_response(400, {"error": "invalid_json_body"})

    code = body.get("code")
    if not code:
        return common.json_response(400, {"error": "missing_code"})

    google_credentials = common.get_secret_json(GOOGLE_OAUTH_SECRET_NAME)
    client_id = google_credentials["client_id"]
    client_secret = google_credentials["client_secret"]

    try:
        tokens = common.exchange_google_auth_code(code, client_id, client_secret)
    except common.GoogleTokenError:
        return common.json_response(401, {"error": "google_code_exchange_failed"})

    try:
        claims = common.verify_google_id_token(tokens["id_token"], client_id)
    except ValueError:
        return common.json_response(401, {"error": "invalid_google_token"})

    if not claims.get("email_verified", False):
        return common.json_response(403, {"error": "google_email_not_verified"})

    user_id = claims["sub"]
    now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    existing = common.get_user(TABLE_NAME, user_id)

    # Google only reissues a refresh_token on the user's first consent for this
    # app/scope set; keep the previously stored one if this response omits it.
    refresh_token = tokens.get("refresh_token") or (existing or {}).get("google_refresh_token")

    user_item = {
        "user_id": user_id,
        "email": claims.get("email"),
        "name": claims.get("name"),
        "picture": claims.get("picture"),
        "google_access_token": tokens["access_token"],
        "google_access_token_expires_at": int(time.time()) + int(tokens["expires_in"]),
        "google_refresh_token": refresh_token,
        "google_granted_scopes": tokens.get("scope", ""),
        "created_at": existing["created_at"] if existing else now_iso,
        "updated_at": now_iso,
    }
    common.put_user(TABLE_NAME, user_item)

    jwt_secret = common.get_secret_json(SESSION_JWT_SECRET_NAME)["secret"]
    session_token, expires_at = common.create_session_jwt(
        user_id=user_id,
        email=user_item["email"],
        secret=jwt_secret,
        ttl_minutes=SESSION_JWT_TTL_MINUTES,
    )

    return common.json_response(
        200,
        {
            "token": session_token,
            "expires_at": expires_at,
            "user": {
                "id": user_id,
                "email": user_item["email"],
                "name": user_item["name"],
                "picture": user_item["picture"],
            },
        },
    )
