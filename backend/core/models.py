from datetime import timezone as dt_timezone

from django.contrib.auth.base_user import AbstractBaseUser, BaseUserManager
from django.db import models
from django.utils import timezone

ROLES = ("commander", "medic", "operator")


def iso(moment):
    """UTC ISO 8601 with milliseconds and Z, as the Dart server wrote."""
    return (
        moment.astimezone(dt_timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


class TeamGroup(models.Model):
    """A communication group: one Meshtastic channel and one PTT room."""

    id = models.CharField(primary_key=True, max_length=20)
    name = models.CharField(max_length=20)
    channel_index = models.PositiveSmallIntegerField(default=0)
    ptt_enabled = models.BooleanField(default=True)
    description = models.CharField(max_length=80, blank=True, default="")

    class Meta:
        ordering = ["channel_index", "id"]

    def __str__(self):
        return self.name

    def to_json(self):
        return {
            "id": self.id,
            "name": self.name,
            "channelIndex": self.channel_index,
            "pttEnabled": self.ptt_enabled,
            "description": self.description,
        }


class UserManager(BaseUserManager):
    def create_user(self, username, password, **fields):
        user = self.model(username=username.strip().lower(), **fields)
        user.set_password(password)
        user.save()
        return user


class User(AbstractBaseUser):
    username = models.CharField(max_length=32, unique=True)
    display_name = models.CharField(max_length=40, blank=True, default="")
    role = models.CharField(
        max_length=16, choices=[(r, r) for r in ROLES], default="operator"
    )
    groups = models.ManyToManyField(TeamGroup, related_name="members", blank=True)
    disabled = models.BooleanField(default=False)
    # Bumped to revoke every session token of the user.
    session_version = models.PositiveIntegerField(default=1)

    objects = UserManager()

    USERNAME_FIELD = "username"

    class Meta:
        ordering = ["username"]

    def __str__(self):
        return self.username

    @property
    def is_active(self):
        return not self.disabled

    @property
    def is_commander(self):
        return self.role == "commander"

    def group_ids(self):
        return sorted(self.groups.values_list("id", flat=True))

    def to_admin_json(self):
        return {
            "userName": self.username,
            "displayName": self.display_name,
            "role": self.role,
            "groups": self.group_ids(),
            "disabled": self.disabled,
            "devices": [device.to_json() for device in self.devices.all()],
        }


class Device(models.Model):
    """A phone bound to a user at login."""

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="devices")
    device_id = models.CharField(max_length=64)
    name = models.CharField(max_length=64, blank=True, default="")
    bound_at = models.DateTimeField(default=timezone.now)
    last_seen = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["bound_at", "id"]
        constraints = [
            models.UniqueConstraint(
                fields=["user", "device_id"], name="unique_device_per_user"
            )
        ]

    def to_json(self):
        return {
            "id": self.device_id,
            "name": self.name,
            "boundAt": iso(self.bound_at),
            "lastSeen": iso(self.last_seen),
        }


class GroupKey(models.Model):
    """E2EE voice key of a group. Not tied to the group row: a group
    re-created with the same id continues its key history."""

    group_id = models.CharField(max_length=20, db_index=True)
    key_id = models.PositiveIntegerField()
    key = models.CharField(max_length=64)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["group_id", "key_id"]
        constraints = [
            models.UniqueConstraint(
                fields=["group_id", "key_id"], name="unique_key_per_group"
            )
        ]

    def to_json(self):
        return {"id": self.key_id, "key": self.key}


class AuditEntry(models.Model):
    at = models.DateTimeField(default=timezone.now, db_index=True)
    event = models.CharField(max_length=40)
    user = models.CharField(max_length=32, null=True, blank=True)
    details = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["-at", "-id"]

    def to_json(self):
        entry = {"at": iso(self.at), "event": self.event}
        if self.user is not None:
            entry["user"] = self.user
        entry.update(self.details)
        return entry
