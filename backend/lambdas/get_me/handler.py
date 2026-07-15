"""GET /auth/me - returns the authenticated user's profile.

Protected by the `authorizer` Lambda; expects requestContext.authorizer.lambda.user_id
to have been set by it.
"""
import logging

import common

logger = logging.getLogger(__name__)

TABLE_NAME = common.env("USERS_TABLE_NAME")


def handler(event, _context):
    authorizer_context = event["requestContext"]["authorizer"]["lambda"]
    user_id = authorizer_context["user_id"]

    user = common.get_user(TABLE_NAME, user_id)
    if not user:
        logger.warning("get_me: user_id=%s not found", user_id)
        return common.json_response(404, {"error": "user_not_found"})

    return common.json_response(
        200,
        {
            "id": user["user_id"],
            "email": user.get("email"),
            "name": user.get("name"),
            "picture": user.get("picture"),
        },
    )
