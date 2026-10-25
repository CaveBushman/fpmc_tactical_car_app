"""Settings for the tactical backend.

Configuration comes from environment variables (same names as the former
Dart server where they overlap):

- SESSION_SECRET (required, >= 32 chars): signs app session tokens.
- DJANGO_SECRET_KEY: Django's own secret (cookies, CSRF); defaults to a
  value derived from SESSION_SECRET.
- LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET (required).
- POSTGRES_DB / POSTGRES_USER / POSTGRES_PASSWORD / POSTGRES_HOST /
  POSTGRES_PORT: PostgreSQL; without POSTGRES_DB a local SQLite file is
  used (development, tests).
- ALLOWED_HOSTS: comma separated (default "*").
- CSRF_TRUSTED_ORIGINS: comma separated origins of the web panel behind
  a reverse proxy, e.g. https://ptt.example.cz.
- MAX_DEVICES_PER_USER (default 2, 0 = unlimited).
- TRUST_PROXY=1: take the client address from X-Forwarded-For and the
  scheme from X-Forwarded-Proto; enables HTTPS redirect (SSL_REDIRECT=0
  to turn off) and HSTS (HSTS_SECONDS, default 180 days).
- AUDIT_RETENTION_DAYS (default 365): `prune_audit` deletes older entries.
- DEBUG=1: development only.
- DEV_PASSWORDLESS_LOGIN=1 (with DEBUG=1 only): app logins accept any
  password for existing, unblocked users; every such login is audited.
"""

import hashlib
import os
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

TESTING = len(sys.argv) > 1 and sys.argv[1] == "test"


def _env(name, default=None):
    value = os.environ.get(name)
    return value if value not in (None, "") else default


SESSION_SECRET = _env("SESSION_SECRET")
if TESTING:
    SESSION_SECRET = SESSION_SECRET or "test-session-secret-0123456789abcdef"
if not SESSION_SECRET or len(SESSION_SECRET) < 32:
    raise RuntimeError("SESSION_SECRET must be set and at least 32 characters")

LIVEKIT_URL = _env("LIVEKIT_URL", "wss://livekit.test" if TESTING else None)
LIVEKIT_API_KEY = _env("LIVEKIT_API_KEY", "test-key" if TESTING else None)
LIVEKIT_API_SECRET = _env(
    "LIVEKIT_API_SECRET",
    "test-livekit-secret-0123456789abcdef" if TESTING else None,
)
for _name in ("LIVEKIT_URL", "LIVEKIT_API_KEY", "LIVEKIT_API_SECRET"):
    if not globals()[_name]:
        raise RuntimeError(f"Missing environment variable {_name}")

try:
    MAX_DEVICES_PER_USER = int(_env("MAX_DEVICES_PER_USER", "2"))
except ValueError:
    MAX_DEVICES_PER_USER = 2
TRUST_PROXY = _env("TRUST_PROXY") == "1"

SECRET_KEY = _env(
    "DJANGO_SECRET_KEY",
    hashlib.sha256(f"django:{SESSION_SECRET}".encode()).hexdigest(),
)
DEBUG = _env("DEBUG") == "1"
ALLOWED_HOSTS = [h.strip() for h in _env("ALLOWED_HOSTS", "*").split(",") if h.strip()]
CSRF_TRUSTED_ORIGINS = [
    o.strip() for o in _env("CSRF_TRUSTED_ORIGINS", "").split(",") if o.strip()
]

INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "core",
]

MIDDLEWARE = [
    "core.middleware.NoStoreMiddleware",
    "core.middleware.PanelSecurityMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "tactical.urls"
APPEND_SLASH = False

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
                "core.context.panel_section",
            ],
        },
    },
]

WSGI_APPLICATION = "tactical.wsgi.application"

if _env("POSTGRES_DB") and not TESTING:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": _env("POSTGRES_DB"),
            "USER": _env("POSTGRES_USER", "tactical"),
            "PASSWORD": _env("POSTGRES_PASSWORD", ""),
            "HOST": _env("POSTGRES_HOST", "localhost"),
            "PORT": _env("POSTGRES_PORT", "5432"),
            "CONN_MAX_AGE": 60,
        }
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }

# Login rate limits and lockouts must be shared by all worker processes.
CACHES = {
    "default": (
        {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}
        if TESTING
        else {
            "BACKEND": "django.core.cache.backends.db.DatabaseCache",
            "LOCATION": "tactical_cache",
        }
    )
}

AUTH_USER_MODEL = "core.User"
# Same hash format as the former Dart server, so existing hashes verify.
PASSWORD_HASHERS = ["core.passwords.TacticalPbkdf2Hasher"]
AUTH_PASSWORD_VALIDATORS = [
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
        "OPTIONS": {"min_length": 10},
    },
]

LOGIN_URL = "panel-login"
LOGIN_REDIRECT_URL = "panel-users"
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Strict"
SESSION_COOKIE_AGE = 8 * 3600
SESSION_COOKIE_SECURE = not DEBUG and not TESTING
CSRF_COOKIE_SECURE = not DEBUG and not TESTING
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "no-referrer"
X_FRAME_OPTIONS = "DENY"
if TRUST_PROXY:
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
    # Served only over HTTPS behind the proxy: browsers must never fall back
    # to plain HTTP for the panel.
    SECURE_HSTS_SECONDS = int(_env("HSTS_SECONDS", str(180 * 24 * 3600)))
    SECURE_SSL_REDIRECT = _env("SSL_REDIRECT", "1") == "1"
    # The proxy talks to us over plain HTTP on localhost; health checks
    # from Docker must not be redirected.
    SECURE_REDIRECT_EXEMPT = [r"^health$"]

# Development only: existing, unblocked users log in to the app API
# without a password. Ignored unless DEBUG=1, so a production server cannot
# be switched to it by one stray variable.
DEV_PASSWORDLESS_LOGIN = DEBUG and _env("DEV_PASSWORDLESS_LOGIN") == "1"
if DEV_PASSWORDLESS_LOGIN:
    import warnings

    warnings.warn(
        "DEV_PASSWORDLESS_LOGIN is on: app logins need no password. "
        "Development use only.",
        stacklevel=1,
    )

# Audit entries older than this are deleted by `prune_audit`.
AUDIT_RETENTION_DAYS = int(_env("AUDIT_RETENTION_DAYS", "365"))

LANGUAGE_CODE = "cs"
TIME_ZONE = "Europe/Prague"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "root": {"handlers": ["console"], "level": "INFO"},
}
