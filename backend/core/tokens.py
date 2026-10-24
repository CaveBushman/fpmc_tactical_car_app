"""App session tokens and LiveKit access tokens (HS256 JWTs)."""

import time

import jwt
from django.conf import settings

SESSION_LIFETIME = 12 * 3600
LIVEKIT_LIFETIME = 6 * 3600
ISSUER = "fpmc-tactical"
AUDIENCE = "tactical-app"


def issue_session(user, device_id=None):
    """Returns (token, lifetime in seconds)."""
    now = int(time.time())
    claims = {
        "typ": "session",
        "ver": user.session_version,
        "sub": user.username,
        "iss": ISSUER,
        "aud": AUDIENCE,
        "iat": now,
        "exp": now + SESSION_LIFETIME,
    }
    if device_id is not None:
        claims["dev"] = device_id
    token = jwt.encode(claims, settings.SESSION_SECRET, algorithm="HS256")
    return token, SESSION_LIFETIME


def verify_session(token):
    """Claims of a valid session token, else None."""
    try:
        claims = jwt.decode(
            token,
            settings.SESSION_SECRET,
            algorithms=["HS256"],
            audience=AUDIENCE,
            issuer=ISSUER,
            options={"require": ["sub", "exp"]},
        )
    except jwt.PyJWTError:
        return None
    if claims.get("typ") != "session" or not isinstance(claims.get("sub"), str):
        return None
    return claims


def livekit_token(user, room):
    now = int(time.time())
    claims = {
        "iss": settings.LIVEKIT_API_KEY,
        "sub": user.username,
        "iat": now,
        "nbf": now,
        "exp": now + LIVEKIT_LIFETIME,
        "name": user.display_name,
        "video": {
            "room": room,
            "roomJoin": True,
            "canPublish": True,
            "canSubscribe": True,
            "canPublishData": True,
            "canPublishSources": ["microphone"],
        },
    }
    return jwt.encode(claims, settings.LIVEKIT_API_SECRET, algorithm="HS256")
