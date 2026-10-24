import getpass
import sys

from django.core.management.base import BaseCommand

from core.api import MIN_PASSWORD_LENGTH
from core.passwords import hash_password


class Command(BaseCommand):
    help = "Prints a password hash in the server's format (asks for the password)."

    def handle(self, *args, **options):
        password = getpass.getpass("Heslo: ")
        if len(password) < MIN_PASSWORD_LENGTH:
            self.stderr.write(f"Heslo musí mít aspoň {MIN_PASSWORD_LENGTH} znaků.")
            sys.exit(64)
        self.stdout.write(hash_password(password))
