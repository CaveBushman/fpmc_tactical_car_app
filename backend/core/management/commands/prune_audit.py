from datetime import timedelta

from django.conf import settings
from django.core.management.base import BaseCommand
from django.utils import timezone

from core.models import AuditEntry


class Command(BaseCommand):
    help = "Deletes audit entries older than AUDIT_RETENTION_DAYS (or --days)."

    def add_arguments(self, parser):
        parser.add_argument("--days", type=int, default=None)

    def handle(self, days, **options):
        days = days if days is not None else settings.AUDIT_RETENTION_DAYS
        if days < 1:
            self.stdout.write("Uchovávání auditu je vypnuté (0 dní), nic nemažu.")
            return
        cutoff = timezone.now() - timedelta(days=days)
        deleted, _ = AuditEntry.objects.filter(at__lt=cutoff).delete()
        self.stdout.write(f"Smazáno {deleted} záznamů auditu starších než {days} dní.")
