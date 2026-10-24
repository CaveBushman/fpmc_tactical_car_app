"""Imports the former Dart server's DATA_DIR (users.json, groups.json,
group_keys.json, audit.jsonl) so password hashes, device bindings,
session versions and E2EE keys carry over unchanged."""

import json
from datetime import datetime
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from core.models import AuditEntry, Device, GroupKey, TeamGroup, User


def _time(value):
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


class Command(BaseCommand):
    help = "Imports users, groups, keys and audit from the Dart server's data directory."

    def add_arguments(self, parser):
        parser.add_argument("data_dir")
        parser.add_argument(
            "--replace",
            action="store_true",
            help="Delete existing users, groups and keys first.",
        )

    @transaction.atomic
    def handle(self, data_dir, replace, **options):
        directory = Path(data_dir)
        if not (directory / "users.json").exists():
            raise CommandError(f"{directory}/users.json not found")
        if replace:
            User.objects.all().delete()
            TeamGroup.objects.all().delete()
            GroupKey.objects.all().delete()

        groups_file = directory / "groups.json"
        if groups_file.exists():
            for g in json.loads(groups_file.read_text())["groups"]:
                TeamGroup.objects.update_or_create(
                    id=g["id"],
                    defaults={
                        "name": g["name"],
                        "channel_index": g["channelIndex"],
                        "ptt_enabled": g.get("pttEnabled") is not False,
                        "description": g.get("description") or "",
                    },
                )

        users = json.loads((directory / "users.json").read_text())["users"]
        for u in users:
            user, _ = User.objects.update_or_create(
                username=u["userName"].strip().lower(),
                defaults={
                    "display_name": u.get("displayName") or "",
                    "role": u.get("role") or "operator",
                    "password": u["passwordHash"],
                    "disabled": u.get("disabled") is True,
                    "session_version": u.get("sessionVersion") or 1,
                },
            )
            user.groups.set(TeamGroup.objects.filter(id__in=u.get("groups") or []))
            user.devices.all().delete()
            for d in u.get("devices") or []:
                Device.objects.create(
                    user=user,
                    device_id=d["id"],
                    name=d.get("name") or "",
                    bound_at=_time(d.get("boundAt")) or datetime.now().astimezone(),
                    last_seen=_time(d.get("lastSeen")) or datetime.now().astimezone(),
                )

        keys_file = directory / "group_keys.json"
        key_count = 0
        if keys_file.exists():
            for group_id, entries in json.loads(keys_file.read_text()).items():
                for k in entries:
                    GroupKey.objects.update_or_create(
                        group_id=group_id,
                        key_id=k["id"],
                        defaults={
                            "key": k["key"],
                            "created_at": _time(k.get("createdAt"))
                            or datetime.now().astimezone(),
                        },
                    )
                    key_count += 1

        audit_file = directory / "audit.jsonl"
        audit_count = 0
        if audit_file.exists():
            for line in audit_file.read_text().splitlines():
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                at = _time(entry.pop("at", ""))
                event = entry.pop("event", None)
                if at is None or not event:
                    continue
                AuditEntry.objects.create(
                    at=at, event=event, user=entry.pop("user", None), details=entry
                )
                audit_count += 1

        self.stdout.write(
            f"Importováno: {len(users)} uživatelů, "
            f"{TeamGroup.objects.count()} skupin, {key_count} klíčů, "
            f"{audit_count} záznamů auditu."
        )
