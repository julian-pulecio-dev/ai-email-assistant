"""HTTP API Lambda REQUEST authorizer (simple response format).

Validates the `Authorization: Bearer <session JWT>` header issued by
POST /auth/google and forwards the decoded claims to downstream handlers via
the authorizer context.
"""
import jwt

import common

SESSION_JWT_SECRET_NAME = common.env("SESSION_JWT_SECRET_NAME")


def handler(event, _context):
    headers = event.get("headers") or {}
    auth_header = headers.get("authorization") or headers.get("Authorization") or ""

    if not auth_header.lower().startswith("bearer "):
        return {"isAuthorized": False}

    token = auth_header.split(" ", 1)[1].strip()
    jwt_secret = common.get_secret_json(SESSION_JWT_SECRET_NAME)["secret"]

    try:
        claims = common.decode_session_jwt(token, jwt_secret)
    except jwt.PyJWTError:
        return {"isAuthorized": False}

    return {
        "isAuthorized": True,
        "context": {"user_id": claims["sub"], "email": claims.get("email", "")},
    }
