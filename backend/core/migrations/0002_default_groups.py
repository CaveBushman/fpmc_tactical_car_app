from django.db import migrations

DEFAULT_GROUPS = [
    ("alpha", "ALPHA", 0),
    ("bravo", "BRAVO", 1),
    ("med", "MED", 2),
    ("command", "COMMAND", 3),
]


def create_default_groups(apps, schema_editor):
    TeamGroup = apps.get_model("core", "TeamGroup")
    if TeamGroup.objects.exists():
        return
    for group_id, name, channel in DEFAULT_GROUPS:
        TeamGroup.objects.create(id=group_id, name=name, channel_index=channel)


class Migration(migrations.Migration):
    dependencies = [("core", "0001_initial")]

    operations = [
        migrations.RunPython(create_default_groups, migrations.RunPython.noop),
    ]
