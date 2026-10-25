"""JSON API used by the app and by admin tools. Paths, status codes and
bodies match the former Dart server exactly, so app builds talking to it
keep working."""

import json
import re

from django.conf import settings
from django.db import DatabaseError, connection, transaction
from django.http import HttpResponse, JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt

from . import audit, keys, security, tokens
from .models import ROLES, Device, TeamGroup, User
from .passwords import DUMMY_HASH, verify_password

MIN_PASSWORD_LENGTH = 10
USER_NAME = re.compile(r"^[a-z0-9._-]{3,32}$")
GROUP_ID = re.compile(r"^[a-z0-9_-]{2,20}$")


# --- Helpers -----------------------------------------------------------------


def _json(status, data):
    return JsonResponse(
        data,
        status=status,
        json_dumps_params={"ensure_ascii": False},
        content_type="application/json; charset=utf-8",
    )


def _error(status, code, **extra):
    return _json(status, {"error": code, **extra})


def _not_found():
    return HttpResponse("Route not found", status=404, content_type="text/plain")


def _body(request):
    """The JSON object sent, or {} for anything else (never a 400)."""
    try:
        data = json.loads(request.body or b"null")
    except (ValueError, UnicodeDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _text(value, default=""):
    return default if value is None else str(value)


def routes(**handlers):
    """Dispatches by HTTP method; anything else is a 404 like before."""

    @csrf_exempt
    def view(request, *args, **kwargs):
        method = request.method
        if method == "HEAD" and "GET" in handlers:
            method = "GET"
        handler = handlers.get(method)
        if handler is None:
            return _not_found()
        response = handler(request, *args, **kwargs)
        if request.method == "HEAD":
            response.content = b""
        return response

    return view


def _authenticate(request):
    """The user behind a valid, unrevoked session token, else None."""
    header = request.META.get("HTTP_AUTHORIZATION", "")
    if not header.startswith("Bearer "):
        return None, None
    claims = tokens.verify_session(header[len("Bearer "):].strip())
    if claims is None:
        return None, None
    user = User.objects.filter(username=claims["sub"]).first()
    if user is None or user.disabled:
        return None, None
    if user.session_version != claims.get("ver", 1):
        return None, None
    device = claims.get("dev")
    if device is not None and not user.devices.filter(device_id=device).exists():
        return None, None
    return user, claims


def _require_user(request):
    user, claims = _authenticate(request)
    if user is None:
        return None, None, _error(401, "unauthenticated")
    return user, claims, None


def _require_commander(request):
    user, _, error = _require_user(request)
    if error:
        return None, error
    if not user.is_commander:
        audit.record("admin_denied", user, path=request.path.lstrip("/"))
        return None, _error(403, "commander_only")
    return user, None


# --- Public ------------------------------------------------------------------


def health(request):
    """Also checks the database, so a proxy or Docker can tell a backend
    that answers but cannot work."""
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
    except DatabaseError:
        return _json(503, {"ok": False, "error": "database_unavailable"})
    return _json(200, {"ok": True})


def login(request):
    body = _body(request)
    user_name = _text(body.get("userName")).strip().lower()
    password = _text(body.get("password"))
    device_id = body.get("deviceId")
    device_id = None if device_id is None else str(device_id).strip()
    device_name = _text(body.get("deviceName")).strip()
    if not user_name or not password:
        return _error(400, "missing_credentials")

    ip = security.client_ip(request)
    wait = security.rate_limit(ip)
    if wait is not None:
        audit.record("login_rate_limited", user_name, ip=ip)
        return _error(429, "rate_limited", retryAfterSeconds=wait)
    locked = security.locked_for(user_name, ip)
    if locked is not None:
        audit.record("login_locked", user_name, ip=ip)
        return _error(429, "locked", retryAfterSeconds=locked)

    user = User.objects.filter(username=user_name).first()
    valid = verify_password(password, user.password if user else DUMMY_HASH)
    if user is None or not valid:
        security.record_failure(user_name, ip)
        audit.record("login_failed", user_name, ip=ip)
        return _error(401, "invalid_credentials")
    if user.disabled:
        audit.record("login_disabled", user_name)
        return _error(403, "account_disabled")

    if device_id:
        now = timezone.now()
        device = user.devices.filter(device_id=device_id).first()
        if device is not None:
            device.last_seen = now
            device.save(update_fields=["last_seen"])
        else:
            limit = settings.MAX_DEVICES_PER_USER
            if limit > 0 and user.devices.count() >= limit:
                audit.record("login_device_refused", user, deviceName=device_name)
                return _error(403, "device_not_allowed")
            Device.objects.create(
                user=user, device_id=device_id, name=device_name,
                bound_at=now, last_seen=now,
            )
            audit.record("device_bound", user, deviceName=device_name)

    security.record_success(user_name, ip)
    audit.record("login", user, ip=ip)
    token, lifetime = tokens.issue_session(user, device_id)
    return _json(
        200,
        {
            "sessionToken": token,
            "expiresInSeconds": lifetime,
            "user": {
                "userName": user.username,
                "displayName": user.display_name,
                "role": user.role,
                "groups": user.group_ids(),
            },
            "groups": [group.to_json() for group in user.groups.all()],
        },
    )


def refresh(request):
    user, claims, error = _require_user(request)
    if error:
        return error
    audit.record("session_refreshed", user)
    token, lifetime = tokens.issue_session(user, claims.get("dev"))
    return _json(200, {"sessionToken": token, "expiresInSeconds": lifetime})


def change_password(request):
    user, claims, error = _require_user(request)
    if error:
        return error
    body = _body(request)
    if not verify_password(_text(body.get("oldPassword")), user.password):
        audit.record("password_change_failed", user)
        return _error(403, "invalid_credentials")
    new_password = _text(body.get("newPassword"))
    if len(new_password) < MIN_PASSWORD_LENGTH:
        return _error(400, "weak_password")
    user.set_password(new_password)
    user.session_version += 1
    user.save()
    audit.record("password_changed", user)
    token, _ = tokens.issue_session(user, claims.get("dev"))
    return _json(200, {"sessionToken": token})


def join_ptt(request, group):
    user, _, error = _require_user(request)
    if error:
        return error
    team_group = user.groups.filter(id=group).first()
    if team_group is None:
        audit.record("ptt_denied", user, group=group)
        return _error(403, "forbidden_group")
    if not team_group.ptt_enabled:
        return _error(403, "ptt_disabled")
    room = f"ptt-{group}"
    key = keys.current(group)
    previous = keys.previous(group)
    audit.record("ptt_join", user, group=group, keyId=key.key_id)
    data = {
        "livekitUrl": settings.LIVEKIT_URL,
        "room": room,
        "identity": user.username,
        "token": tokens.livekit_token(user, room),
        "key": key.to_json(),
    }
    if previous is not None:
        data["previousKey"] = previous.to_json()
    return _json(200, data)


# --- Admin: users -------------------------------------------------------------


def _profile(body, current=None):
    """(display name, role, groups) from a create/patch body, or an error."""
    display = body.get("displayName")
    role = body.get("role")
    groups = body.get("groups")
    if current is not None:
        display = current.display_name if display is None else display
        role = current.role if role is None else role
        groups = current.group_ids() if groups is None else groups
    role = _text(role, "operator")
    if role not in ROLES:
        return None, _error(400, "unknown_role")
    if not isinstance(groups, list):
        return None, _error(400, "groups_required")
    group_ids = {str(g) for g in groups}
    known = set(TeamGroup.objects.filter(id__in=group_ids).values_list("id", flat=True))
    if group_ids - known:
        return None, _error(400, "unknown_group")
    display = _text(display).strip()
    if len(display) > 40:
        return None, _error(400, "display_name_too_long")
    return (display, role, sorted(group_ids)), None


def _find_user(name):
    return User.objects.filter(username=name.strip().lower()).first()


def list_users(request):
    _, error = _require_commander(request)
    if error:
        return error
    groups = list(TeamGroup.objects.all())
    return _json(
        200,
        {
            "users": [
                user.to_admin_json()
                for user in User.objects.prefetch_related("groups", "devices")
            ],
            "groups": sorted(group.id for group in groups),
            "groupDefinitions": [group.to_json() for group in groups],
            "roles": sorted(ROLES),
        },
    )


@transaction.atomic
def create_user(request):
    admin, error = _require_commander(request)
    if error:
        return error
    body = _body(request)
    user_name = _text(body.get("userName")).strip().lower()
    if not USER_NAME.match(user_name):
        return _error(400, "invalid_user_name")
    if User.objects.filter(username=user_name).exists():
        return _error(409, "user_exists")
    password = _text(body.get("password"))
    if len(password) < MIN_PASSWORD_LENGTH:
        return _error(400, "weak_password")
    profile, error = _profile(body)
    if error:
        return error
    display, role, group_ids = profile
    user = User.objects.create_user(
        user_name, password, display_name=display or user_name.upper(), role=role
    )
    user.groups.set(group_ids)
    audit.record("user_created", admin, target=user_name, role=role, groups=group_ids)
    return _json(201, user.to_admin_json())


@transaction.atomic
def update_user(request, name):
    admin, error = _require_commander(request)
    if error:
        return error
    user = _find_user(name)
    if user is None:
        return _error(404, "not_found")
    body = _body(request)
    profile, error = _profile(body, current=user)
    if error:
        return error
    display, role, group_ids = profile
    disabled = (body.get("disabled") is True) if "disabled" in body else user.disabled
    if user.pk == admin.pk and (disabled or role != "commander"):
        return _error(400, "cannot_lock_out_self")
    if role != user.role or disabled != user.disabled or group_ids != user.group_ids():
        user.session_version += 1
    user.display_name, user.role, user.disabled = display, role, disabled
    user.save()
    user.groups.set(group_ids)
    audit.record(
        "user_updated", admin,
        target=user.username, role=role, groups=group_ids, disabled=disabled,
    )
    return _json(200, user.to_admin_json())


def reset_password(request, name):
    admin, error = _require_commander(request)
    if error:
        return error
    user = _find_user(name)
    if user is None:
        return _error(404, "not_found")
    password = _text(_body(request).get("password"))
    if len(password) < MIN_PASSWORD_LENGTH:
        return _error(400, "weak_password")
    user.set_password(password)
    user.session_version += 1
    user.save()
    audit.record("password_reset", admin, target=user.username)
    return _json(200, {"ok": True})


def revoke_sessions(request, name):
    admin, error = _require_commander(request)
    if error:
        return error
    user = _find_user(name)
    if user is None:
        return _error(404, "not_found")
    user.session_version += 1
    user.save(update_fields=["session_version"])
    audit.record("sessions_revoked", admin, target=user.username)
    return _json(200, {"ok": True})


def unbind_device(request, name, device):
    admin, error = _require_commander(request)
    if error:
        return error
    user = _find_user(name)
    deleted = user.devices.filter(device_id=device).delete()[0] if user else 0
    if not deleted:
        return _error(404, "not_found")
    audit.record("device_unbound", admin, target=user.username)
    return _json(200, {"ok": True})


# --- Admin: groups ---------------------------------------------------------------


def _apply_group(group, body):
    """Applies name/channel/PTT/description from [body]; error or None."""
    if "name" in body:
        name = _text(body.get("name")).strip()
        if not name or len(name) > 20:
            return _error(400, "invalid_name")
        group.name = name
    if "channelIndex" in body:
        channel = body.get("channelIndex")
        if type(channel) is not int or not 0 <= channel <= 7:
            return _error(400, "invalid_channel")
        group.channel_index = channel
    if "description" in body:
        description = _text(body.get("description")).strip()
        if len(description) > 80:
            return _error(400, "description_too_long")
        group.description = description
    if "pttEnabled" in body:
        group.ptt_enabled = body.get("pttEnabled") is True
    return None


def list_groups(request):
    _, error = _require_commander(request)
    if error:
        return error
    return _json(
        200,
        {
            "groups": [
                {
                    **group.to_json(),
                    "members": sorted(m.username for m in group.members.all()),
                }
                for group in TeamGroup.objects.prefetch_related("members")
            ]
        },
    )


def create_group(request):
    admin, error = _require_commander(request)
    if error:
        return error
    body = _body(request)
    group_id = _text(body.get("id")).strip().lower()
    if not GROUP_ID.match(group_id):
        return _error(400, "invalid_group_id")
    if TeamGroup.objects.filter(id=group_id).exists():
        return _error(409, "group_exists")
    group = TeamGroup(id=group_id, name=group_id.upper())
    error = _apply_group(group, body)
    if error:
        return error
    group.save()
    audit.record("group_created", admin, **group.to_json())
    return _json(201, group.to_json())


def update_group(request, group_id):
    admin, error = _require_commander(request)
    if error:
        return error
    group = TeamGroup.objects.filter(id=group_id).first()
    if group is None:
        return _error(404, "not_found")
    error = _apply_group(group, _body(request))
    if error:
        return error
    group.save()
    audit.record("group_updated", admin, **group.to_json())
    return _json(200, group.to_json())


def delete_group(request, group_id):
    admin, error = _require_commander(request)
    if error:
        return error
    group = TeamGroup.objects.filter(id=group_id).first()
    if group is None:
        return _error(404, "not_found")
    members = sorted(group.members.values_list("username", flat=True))
    if members:
        return _error(409, "group_in_use", members=members)
    group.delete()
    audit.record("group_deleted", admin, group=group_id)
    return _json(200, {"ok": True})


def rotate_key(request, group_id):
    admin, error = _require_commander(request)
    if error:
        return error
    if not TeamGroup.objects.filter(id=group_id).exists():
        return _error(404, "not_found")
    key = keys.rotate(group_id)
    audit.record("key_rotated", admin, group=group_id, keyId=key.key_id)
    return _json(200, {"group": group_id, "keyId": key.key_id})


def read_audit(request):
    _, error = _require_commander(request)
    if error:
        return error
    from .models import AuditEntry

    try:
        limit = int(request.GET.get("limit", "100"))
    except ValueError:
        limit = 100
    limit = min(max(limit, 1), 500)
    return _json(
        200, {"entries": [entry.to_json() for entry in AuditEntry.objects.all()[:limit]]}
    )
