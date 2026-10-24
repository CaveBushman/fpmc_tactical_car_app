"""E2EE voice keys per group: the current one plus the previous one, so
members still on the old key can be heard during a rotation."""

import base64
import secrets

from django.db import transaction

from .models import GroupKey

RETAINED = 2


def current(group_id):
    key = GroupKey.objects.filter(group_id=group_id).order_by("-key_id").first()
    return key or rotate(group_id)


def previous(group_id):
    keys = list(GroupKey.objects.filter(group_id=group_id).order_by("-key_id")[:2])
    return keys[1] if len(keys) == 2 else None


@transaction.atomic
def rotate(group_id):
    last = (
        GroupKey.objects.select_for_update()
        .filter(group_id=group_id)
        .order_by("-key_id")
        .first()
    )
    key = GroupKey.objects.create(
        group_id=group_id,
        key_id=(last.key_id + 1) if last else 1,
        key=base64.b64encode(secrets.token_bytes(32)).decode(),
    )
    stale = GroupKey.objects.filter(group_id=group_id).order_by("-key_id")[RETAINED:]
    GroupKey.objects.filter(pk__in=[k.pk for k in stale]).delete()
    return key
