from .models import AuditEntry


def record(event, user=None, **details):
    """Appends an audit entry; ``user`` is the acting account."""
    AuditEntry.objects.create(
        event=event,
        user=getattr(user, "username", user),
        details=details,
    )
