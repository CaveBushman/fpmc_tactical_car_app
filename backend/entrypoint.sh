#!/bin/sh
# Applies migrations, prepares the shared cache table, then serves the app.
set -e
python manage.py migrate --noinput
python manage.py createcachetable
exec gunicorn tactical.wsgi:application \
  --bind "0.0.0.0:${PORT:-8080}" \
  --workers "${WEB_WORKERS:-3}" \
  --access-logfile - \
  --forwarded-allow-ips "${FORWARDED_ALLOW_IPS:-127.0.0.1}"
