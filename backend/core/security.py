"""Login brute-force protection, shared by all workers through the cache:
an IP may try 30 logins per 10 minutes, and 5 wrong passwords for one
user from one IP lock that pair for 5 minutes."""

import time

from django.conf import settings
from django.core.cache import cache

RATE_LIMIT = 30
RATE_WINDOW = 10 * 60
MAX_FAILURES = 5
LOCK_SECONDS = 5 * 60


def client_ip(request):
    if settings.TRUST_PROXY:
        forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "")
        first = forwarded.split(",")[0].strip()
        if first:
            return first
    return request.META.get("REMOTE_ADDR") or "unknown"


def rate_limit(ip, now=None):
    """Counts an attempt; returns seconds to wait when over the limit."""
    now = now or time.time()
    key = f"login-rate:{ip}"
    hits = [t for t in cache.get(key, []) if t > now - RATE_WINDOW]
    if len(hits) >= RATE_LIMIT:
        return int(hits[0] + RATE_WINDOW - now) + 1
    hits.append(now)
    cache.set(key, hits, RATE_WINDOW)
    return None


def _lock_key(user_name, ip):
    return f"login-lock:{user_name}|{ip}"


def locked_for(user_name, ip, now=None):
    """Seconds left of a lockout (+1, as the app expects), else None."""
    now = now or time.time()
    state = cache.get(_lock_key(user_name, ip)) or {}
    until = state.get("until", 0)
    return int(until - now) + 1 if until > now else None


def record_failure(user_name, ip, now=None):
    now = now or time.time()
    key = _lock_key(user_name, ip)
    state = cache.get(key) or {"failures": 0, "until": 0}
    state["failures"] += 1
    if state["failures"] >= MAX_FAILURES:
        state = {"failures": 0, "until": now + LOCK_SECONDS}
    cache.set(key, state, None)


def record_success(user_name, ip):
    cache.delete(_lock_key(user_name, ip))
