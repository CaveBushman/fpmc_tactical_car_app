#!/usr/bin/env bash
# End-to-end check of the app's backend client against the Django backend:
# starts the server on a free port with a throw-away SQLite database (or the
# PostgreSQL given by POSTGRES_* variables), seeds test accounts and runs
# test/e2e/backend_e2e_test.dart over HTTP.
#
#   tool/e2e_backend.sh            # uses backend/.venv or python3 on PATH
set -euo pipefail
cd "$(dirname "$0")/.."

PYTHON="${PYTHON:-backend/.venv/bin/python}"
if [[ "$PYTHON" == */* ]]; then
  [ -x "$PYTHON" ] || PYTHON=python3
fi
# Absolute, because the server runs from another directory.
if [[ "$PYTHON" == */* ]]; then
  PYTHON="$(cd "$(dirname "$PYTHON")" && pwd)/$(basename "$PYTHON")"
else
  PYTHON="$(command -v "$PYTHON")"
fi

work="$(mktemp -d)"
cleanup() {
  [ -n "${server_pid:-}" ] && kill "$server_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

export SESSION_SECRET="e2e-session-secret-0123456789abcdefgh"
export LIVEKIT_URL="wss://livekit.e2e.test"
export LIVEKIT_API_KEY="e2e-key"
export LIVEKIT_API_SECRET="e2e-livekit-secret-0123456789abcdef"
export MAX_DEVICES_PER_USER=1
export DJANGO_SETTINGS_MODULE=tactical.settings
if [ -z "${POSTGRES_DB:-}" ]; then
  # Without PostgreSQL the settings fall back to backend/db.sqlite3; point
  # them at a throw-away copy instead by running from a scratch copy.
  cp -r backend "$work/backend"
  rm -f "$work/backend/db.sqlite3"
  backend_dir="$work/backend"
else
  backend_dir="backend"
fi

(
  cd "$backend_dir"
  "$PYTHON" manage.py migrate --noinput >/dev/null
  "$PYTHON" manage.py createcachetable >/dev/null
  "$PYTHON" manage.py shell -c '
from core.models import TeamGroup, User
recon, _ = TeamGroup.objects.update_or_create(
    id="recon",
    defaults={"name": "PRŮZKUM", "channel_index": 5, "ptt_enabled": False,
              "description": "Hlídka – sever"},
)
def user(name, groups, **extra):
    u = User.objects.filter(username=name).first()
    if u is None:
        u = User.objects.create_user(name, f"{name}-pass", **extra)
    u.groups.set(groups)
user("e2e-operator", ["alpha", "recon"], display_name="OPERÁTOR E2E")
user("e2e-disabled", ["alpha"], disabled=True)
user("e2e-medic", ["med"], role="medic")
user("e2e-lock", ["alpha"])
from core.models import GroupMessage
GroupMessage.objects.create(group_id="alpha", text="Přesun na RV-1 – ihned",
                            priority=True, author="VELITEL E2E")
GroupMessage.objects.create(group_id="command", text="jen velení", author="X")
'
)

port="$("$PYTHON" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
(cd "$backend_dir" && exec "$PYTHON" -m gunicorn tactical.wsgi:application \
  --bind "127.0.0.1:$port" --workers 2 --log-level warning) &
server_pid=$!

for _ in $(seq 1 50); do
  curl -fsS "http://127.0.0.1:$port/health" >/dev/null 2>&1 && break
  sleep 0.2
done
curl -fsS "http://127.0.0.1:$port/health" >/dev/null

BACKEND_E2E_URL="http://127.0.0.1:$port" flutter test test/e2e/backend_e2e_test.dart

# The report sent by the app is stored for the situation page.
(cd "$backend_dir" && "$PYTHON" manage.py shell -c '
from core.models import MemberPosition
p = MemberPosition.objects.get(user__username="e2e-operator")
assert (round(p.latitude, 6), p.status, p.battery_percent) == (50.087451, "holding", 76), p
print("position report stored")
from core.models import MessageAck
acks = list(MessageAck.objects.values_list("user__username", "message__text"))
assert acks == [("e2e-operator", "Přesun na RV-1 – ihned")], acks
print("acknowledgement stored")
')
