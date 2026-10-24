import getpass
import sys

from django.core.management.base import BaseCommand, CommandError

from core import audit
from core.api import MIN_PASSWORD_LENGTH, USER_NAME
from core.models import TeamGroup, User


class Command(BaseCommand):
    help = "Creates a commander with access to all groups (first login to the panel)."

    def add_arguments(self, parser):
        parser.add_argument("user_name")
        parser.add_argument("--display-name", default="")

    def handle(self, user_name, display_name, **options):
        user_name = user_name.strip().lower()
        if not USER_NAME.match(user_name):
            raise CommandError("Neplatné uživatelské jméno.")
        if User.objects.filter(username=user_name).exists():
            raise CommandError("Uživatel už existuje.")
        password = getpass.getpass("Heslo: ")
        if len(password) < MIN_PASSWORD_LENGTH:
            self.stderr.write(f"Heslo musí mít aspoň {MIN_PASSWORD_LENGTH} znaků.")
            sys.exit(64)
        if password != getpass.getpass("Heslo znovu: "):
            raise CommandError("Hesla se neshodují.")
        user = User.objects.create_user(
            user_name,
            password,
            display_name=display_name.strip() or user_name.upper(),
            role="commander",
        )
        user.groups.set(TeamGroup.objects.all())
        audit.record("user_created", None, target=user_name, role="commander",
                     groups=user.group_ids())
        self.stdout.write(f"Velitel {user_name} vytvořen.")
