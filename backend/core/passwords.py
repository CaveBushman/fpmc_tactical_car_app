"""Password hashes in the format the former Dart server wrote, so existing
hashes keep working: ``pbkdf2-sha256$<iterations>$<b64 salt>$<b64 hash>``
(PBKDF2-HMAC-SHA256, standard base64 with padding)."""

import base64
import hashlib
import hmac
import secrets

from django.contrib.auth.hashers import BasePasswordHasher, mask_hash

ALGORITHM = "pbkdf2-sha256"
ITERATIONS = 120_000


def _pbkdf2(password, salt, iterations, length=32):
    return hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, iterations, dklen=length
    )


def hash_password(password, iterations=ITERATIONS):
    salt = secrets.token_bytes(16)
    digest = _pbkdf2(password, salt, iterations)
    return "$".join(
        [
            ALGORITHM,
            str(iterations),
            base64.b64encode(salt).decode(),
            base64.b64encode(digest).decode(),
        ]
    )


def verify_password(password, encoded):
    """Constant-time check; any malformed hash is simply a mismatch."""
    try:
        algorithm, iterations, salt, expected = encoded.split("$")
        iterations = int(iterations)
        if algorithm != ALGORITHM or iterations < 1:
            return False
        expected_bytes = base64.b64decode(expected, validate=True)
        actual = _pbkdf2(
            password, base64.b64decode(salt, validate=True), iterations,
            len(expected_bytes),
        )
    except (ValueError, TypeError, AttributeError):
        return False
    return hmac.compare_digest(actual, expected_bytes)


class TacticalPbkdf2Hasher(BasePasswordHasher):
    algorithm = ALGORITHM
    iterations = ITERATIONS

    def salt(self):
        return base64.b64encode(secrets.token_bytes(16)).decode()

    def encode(self, password, salt, iterations=None):
        iterations = iterations or self.iterations
        digest = _pbkdf2(password, base64.b64decode(salt), iterations)
        return f"{ALGORITHM}${iterations}${salt}${base64.b64encode(digest).decode()}"

    def verify(self, password, encoded):
        return verify_password(password, encoded)

    def decode(self, encoded):
        algorithm, iterations, salt, digest = encoded.split("$", 3)
        return {
            "algorithm": algorithm,
            "iterations": int(iterations),
            "salt": salt,
            "hash": digest,
        }

    def safe_summary(self, encoded):
        decoded = self.decode(encoded)
        return {
            "algorithm": decoded["algorithm"],
            "iterations": decoded["iterations"],
            "salt": mask_hash(decoded["salt"]),
            "hash": mask_hash(decoded["hash"]),
        }

    def must_update(self, encoded):
        return False

    def harden_runtime(self, password, encoded):
        pass


# Verified for unknown user names so the response time does not tell
# which names exist.
DUMMY_HASH = hash_password("unused-dummy-password", iterations=ITERATIONS)
