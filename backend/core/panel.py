"""Server-rendered web panel for commanders: users, devices, groups, keys
and the audit log. Plain HTML forms with CSRF protection, no JavaScript."""

import base64
import csv
import io
import re
import secrets
from datetime import timedelta
from functools import wraps

from django import forms
from django.contrib import messages
from django.contrib.auth import logout, update_session_auth_hash
from django.contrib.auth.forms import AuthenticationForm, PasswordChangeForm
from django.contrib.auth.views import LoginView
from django.core.exceptions import PermissionDenied
from django.db import transaction
from django.db.models import Max, Q
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.utils import timezone
from django.views.decorators.http import require_POST

from . import audit, keys, security
from .api import GROUP_ID, MIN_PASSWORD_LENGTH, USER_NAME
from .mgrs import to_mgrs
from .models import ROLES, AuditEntry, GroupMessage, TeamGroup, User

ROLE_CHOICES = [
    ("operator", "Operátor"),
    ("medic", "Zdravotník"),
    ("commander", "Velitel"),
]
assert {r for r, _ in ROLE_CHOICES} == set(ROLES)


def commander_required(view):
    @wraps(view)
    def wrapper(request, *args, **kwargs):
        if not request.user.is_authenticated:
            return redirect("panel-login")
        if not request.user.is_commander or request.user.disabled:
            raise PermissionDenied
        return view(request, *args, **kwargs)

    return wrapper


# --- Login ---------------------------------------------------------------------


class CommanderLoginForm(AuthenticationForm):
    """Django login limited to commanders, with the same brute-force
    protection as the app login."""

    error_messages = {
        **AuthenticationForm.error_messages,
        "invalid_login": "Nesprávné jméno nebo heslo.",
        "inactive": "Účet je zablokovaný.",
        "not_commander": "Do panelu mají přístup jen velitelé.",
        "rate_limited": "Příliš mnoho pokusů. Zkuste to za %(seconds)s s.",
    }

    def clean(self):
        name = (self.cleaned_data.get("username") or "").strip().lower()
        self.cleaned_data["username"] = name
        ip = security.client_ip(self.request)
        wait = security.rate_limit(ip) or (
            security.locked_for(name, ip) if name else None
        )
        if wait is not None:
            audit.record("panel_login_limited", name or None, ip=ip)
            raise forms.ValidationError(
                self.error_messages["rate_limited"],
                code="rate_limited",
                params={"seconds": wait},
            )
        try:
            super().clean()
        except forms.ValidationError:
            if name:
                security.record_failure(name, ip)
            audit.record("panel_login_failed", name or None, ip=ip)
            raise
        if not self.get_user().is_commander:
            audit.record("panel_login_refused", name, ip=ip)
            raise forms.ValidationError(
                self.error_messages["not_commander"], code="not_commander"
            )
        security.record_success(name, ip)
        audit.record("panel_login", name, ip=ip)
        return self.cleaned_data


class PanelLoginView(LoginView):
    template_name = "panel/login.html"
    authentication_form = CommanderLoginForm
    redirect_authenticated_user = True


@require_POST
def logout_view(request):
    logout(request)
    return redirect("panel-login")


# --- Users ---------------------------------------------------------------------


class GroupChoiceField(forms.ModelMultipleChoiceField):
    widget = forms.CheckboxSelectMultiple

    def label_from_instance(self, group):
        return f"{group.name} (kanál {group.channel_index})"


class UserForm(forms.Form):
    display_name = forms.CharField(
        label="Zobrazované jméno", max_length=40, required=False
    )
    role = forms.ChoiceField(label="Role", choices=ROLE_CHOICES)
    groups = GroupChoiceField(
        label="Skupiny", queryset=TeamGroup.objects.all(), required=False
    )
    disabled = forms.BooleanField(label="Zablokovaný", required=False)


class NewUserForm(UserForm):
    user_name = forms.CharField(
        label="Uživatelské jméno",
        max_length=32,
        help_text="3–32 znaků: malá písmena, číslice, tečka, pomlčka, podtržítko.",
    )
    password = forms.CharField(
        label="Heslo", widget=forms.PasswordInput, min_length=MIN_PASSWORD_LENGTH
    )

    field_order = ["user_name", "display_name", "role", "groups", "password"]

    def clean_user_name(self):
        name = self.cleaned_data["user_name"].strip().lower()
        if not USER_NAME.match(name):
            raise forms.ValidationError("Neplatné uživatelské jméno.")
        if User.objects.filter(username=name).exists():
            raise forms.ValidationError("Uživatel už existuje.")
        return name


class PasswordForm(forms.Form):
    password = forms.CharField(
        label="Nové heslo", widget=forms.PasswordInput, min_length=MIN_PASSWORD_LENGTH
    )


INACTIVE_AFTER = timedelta(days=14)


@commander_required
def users(request):
    query = request.GET.get("q", "").strip()
    show = request.GET.get("show", "")
    users = User.objects.prefetch_related("groups", "devices").annotate(
        last_active=Max("devices__last_seen")
    )
    if query:
        users = users.filter(
            Q(username__icontains=query) | Q(display_name__icontains=query)
        )
    if show == "disabled":
        users = users.filter(disabled=True)
    elif show == "inactive":
        users = users.filter(
            Q(last_active__isnull=True)
            | Q(last_active__lt=timezone.now() - INACTIVE_AFTER)
        )
    return render(
        request,
        "panel/users.html",
        {
            "users": users,
            "query": query,
            "show": show,
            "inactive_days": INACTIVE_AFTER.days,
        },
    )


# --- Bulk import -----------------------------------------------------------------

ROLE_ALIASES = {
    "operator": "operator", "operátor": "operator", "op": "operator",
    "medic": "medic", "zdravotník": "medic", "zdravotnik": "medic",
    "commander": "commander", "velitel": "commander",
}
# No 0/O, 1/l/I: passwords are read off paper.
PASSWORD_ALPHABET = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def generate_password(length=12):
    return "".join(secrets.choice(PASSWORD_ALPHABET) for _ in range(length))


def parse_import(text):
    """Rows of ``user;display name;role;groups`` (comma also works; groups
    separated by spaces or |). Returns (rows, errors), each row a dict and
    each error ``(line number, message)``."""
    lines = [line for line in text.splitlines() if line.strip()]
    if not lines:
        return [], [(0, "Seznam je prázdný.")]
    delimiter = ";" if lines[0].count(";") >= lines[0].count(",") else ","
    known_groups = set(TeamGroup.objects.values_list("id", flat=True))
    existing = set(User.objects.values_list("username", flat=True))
    rows, errors, seen = [], [], set()
    for number, cells in enumerate(csv.reader(lines, delimiter=delimiter), 1):
        cells = [cell.strip() for cell in cells] + ["", "", "", ""]
        name, display, role, groups = cells[:4]
        name = name.lower()
        if number == 1 and name in ("user", "uzivatel", "uživatel", "username"):
            continue  # header
        problems = []
        if not USER_NAME.match(name):
            problems.append("neplatné jméno")
        elif name in existing or name in seen:
            problems.append("jméno už existuje")
        role_id = ROLE_ALIASES.get(role.lower() or "operator")
        if role_id is None:
            problems.append(f"neznámá role {role}")
        group_ids = sorted({g.lower() for g in re.split(r"[\s|]+", groups) if g})
        unknown = [g for g in group_ids if g not in known_groups]
        if unknown:
            problems.append("neznámé skupiny " + ", ".join(unknown))
        if len(display) > 40:
            problems.append("zobrazované jméno je delší než 40 znaků")
        if problems:
            errors.append((number, f"{name or '?'}: " + "; ".join(problems)))
            continue
        seen.add(name)
        rows.append(
            {
                "user_name": name,
                "display_name": display or name.upper(),
                "role": role_id,
                "groups": group_ids,
            }
        )
    return rows, errors


@commander_required
def users_import(request):
    text = request.POST.get("rows", "")
    rows, errors = parse_import(text) if request.method == "POST" else ([], [])
    if request.POST.get("action") == "create" and rows and not errors:
        created = []
        with transaction.atomic():
            for row in rows:
                password = generate_password()
                user = User.objects.create_user(
                    row["user_name"], password,
                    display_name=row["display_name"], role=row["role"],
                )
                user.groups.set(row["groups"])
                created.append({**row, "password": password})
                audit.record(
                    "user_created", request.user, target=user.username,
                    role=user.role, groups=row["groups"], imported=True,
                )
        sheet = io.StringIO()
        writer = csv.writer(sheet, delimiter=";")
        writer.writerow(["uzivatel", "jmeno", "role", "skupiny", "heslo"])
        for row in created:
            writer.writerow(
                [row["user_name"], row["display_name"], row["role"],
                 " ".join(row["groups"]), row["password"]]
            )
        # The passwords exist only in this response: not stored, not logged.
        download = base64.b64encode(
            ("\ufeff" + sheet.getvalue()).encode("utf-8")
        ).decode()
        return render(
            request,
            "panel/users_import_done.html",
            {"created": created, "download": download},
        )
    return render(
        request,
        "panel/users_import.html",
        {"rows": rows, "errors": errors, "text": text,
         "previewed": request.method == "POST"},
    )


# --- Own password ------------------------------------------------------------------


class OwnPasswordForm(PasswordChangeForm):
    error_messages = {
        **PasswordChangeForm.error_messages,
        "password_incorrect": "Současné heslo nesouhlasí.",
        "password_mismatch": "Nová hesla se neshodují.",
    }


@commander_required
def own_password(request):
    form = OwnPasswordForm(request.user, request.POST or None)
    if request.method == "POST" and form.is_valid():
        user = form.save(commit=False)
        # Like a password change in the app: every app session ends.
        user.session_version += 1
        user.save()
        update_session_auth_hash(request, user)
        audit.record("password_changed", user)
        messages.success(
            request, "Heslo změněno. Aplikace se musí přihlásit znovu."
        )
        return redirect("panel-users")
    return render(request, "panel/own_password.html", {"form": form})


@commander_required
@transaction.atomic
def user_create(request):
    form = NewUserForm(request.POST or None)
    del form.fields["disabled"]
    if request.method == "POST" and form.is_valid():
        data = form.cleaned_data
        user = User.objects.create_user(
            data["user_name"],
            data["password"],
            display_name=data["display_name"].strip() or data["user_name"].upper(),
            role=data["role"],
        )
        user.groups.set(data["groups"])
        audit.record(
            "user_created", request.user,
            target=user.username, role=user.role, groups=user.group_ids(),
        )
        messages.success(request, f"Uživatel {user.username} vytvořen.")
        return redirect("panel-user-edit", name=user.username)
    return render(request, "panel/user_new.html", {"form": form})


@commander_required
@transaction.atomic
def user_edit(request, name):
    user = get_object_or_404(User, username=name)
    initial = {
        "display_name": user.display_name,
        "role": user.role,
        "groups": user.groups.all(),
        "disabled": user.disabled,
    }
    form = UserForm(request.POST or None, initial=initial)
    if request.method == "POST" and form.is_valid():
        data = form.cleaned_data
        group_ids = sorted(g.id for g in data["groups"])
        if user.pk == request.user.pk and (
            data["disabled"] or data["role"] != "commander"
        ):
            form.add_error(None, "Sami sebe nemůžete zablokovat ani odebrat roli velitele.")
        else:
            if (
                data["role"] != user.role
                or data["disabled"] != user.disabled
                or group_ids != user.group_ids()
            ):
                user.session_version += 1
            user.display_name = data["display_name"].strip()
            user.role = data["role"]
            user.disabled = data["disabled"]
            user.save()
            user.groups.set(group_ids)
            audit.record(
                "user_updated", request.user, target=user.username,
                role=user.role, groups=group_ids, disabled=user.disabled,
            )
            messages.success(request, "Uloženo.")
            return redirect("panel-user-edit", name=user.username)
    return render(
        request,
        "panel/user_edit.html",
        {"subject": user, "form": form, "password_form": PasswordForm()},
    )


@commander_required
@require_POST
def user_password(request, name):
    user = get_object_or_404(User, username=name)
    form = PasswordForm(request.POST)
    if form.is_valid():
        user.set_password(form.cleaned_data["password"])
        user.session_version += 1
        user.save()
        audit.record("password_reset", request.user, target=user.username)
        messages.success(request, "Heslo změněno, uživatel je všude odhlášen.")
    else:
        messages.error(
            request, f"Heslo musí mít aspoň {MIN_PASSWORD_LENGTH} znaků."
        )
    return redirect("panel-user-edit", name=user.username)


@commander_required
@require_POST
def user_revoke(request, name):
    user = get_object_or_404(User, username=name)
    user.session_version += 1
    user.save(update_fields=["session_version"])
    audit.record("sessions_revoked", request.user, target=user.username)
    messages.success(request, "Uživatel je odhlášen ze všech zařízení.")
    return redirect("panel-user-edit", name=user.username)


@commander_required
@require_POST
def device_unbind(request, name, pk):
    user = get_object_or_404(User, username=name)
    device = get_object_or_404(user.devices, pk=pk)
    device.delete()
    audit.record("device_unbound", request.user, target=user.username)
    messages.success(request, "Zařízení odpojeno.")
    return redirect("panel-user-edit", name=user.username)


# --- Groups --------------------------------------------------------------------


class GroupForm(forms.ModelForm):
    class Meta:
        model = TeamGroup
        fields = ["name", "channel_index", "ptt_enabled", "description"]
        labels = {
            "name": "Název",
            "channel_index": "Kanál T-Beamu (0–7)",
            "ptt_enabled": "Hlasový kanál (PTT)",
            "description": "Popis",
        }

    def clean_name(self):
        name = self.cleaned_data["name"].strip()
        if not name:
            raise forms.ValidationError("Název je povinný.")
        return name

    def clean_channel_index(self):
        channel = self.cleaned_data["channel_index"]
        if not 0 <= channel <= 7:
            raise forms.ValidationError("Kanál musí být 0–7.")
        return channel


class NewGroupForm(GroupForm):
    group_id = forms.CharField(
        label="Identifikátor",
        max_length=20,
        help_text="2–20 znaků: malá písmena, číslice, pomlčka, podtržítko.",
    )

    class Meta(GroupForm.Meta):
        pass

    field_order = ["group_id", "name", "channel_index", "ptt_enabled", "description"]

    def clean_group_id(self):
        group_id = self.cleaned_data["group_id"].strip().lower()
        if not GROUP_ID.match(group_id):
            raise forms.ValidationError("Neplatný identifikátor.")
        if TeamGroup.objects.filter(id=group_id).exists():
            raise forms.ValidationError("Skupina už existuje.")
        return group_id


@commander_required
def groups(request):
    return render(
        request,
        "panel/groups.html",
        {"groups": TeamGroup.objects.prefetch_related("members")},
    )


@commander_required
def group_create(request):
    form = NewGroupForm(request.POST or None)
    if request.method == "POST" and form.is_valid():
        group = form.save(commit=False)
        group.id = form.cleaned_data["group_id"]
        group.save()
        audit.record("group_created", request.user, **group.to_json())
        messages.success(request, f"Skupina {group.name} vytvořena.")
        return redirect("panel-groups")
    return render(request, "panel/group_form.html", {"form": form, "group": None})


@commander_required
def group_edit(request, group_id):
    group = get_object_or_404(TeamGroup, id=group_id)
    form = GroupForm(request.POST or None, instance=group)
    if request.method == "POST" and form.is_valid():
        form.save()
        audit.record("group_updated", request.user, **group.to_json())
        messages.success(request, "Uloženo.")
        return redirect("panel-groups")
    return render(request, "panel/group_form.html", {"form": form, "group": group})


@commander_required
@require_POST
def group_delete(request, group_id):
    group = get_object_or_404(TeamGroup, id=group_id)
    members = sorted(group.members.values_list("username", flat=True))
    if members:
        messages.error(
            request,
            "Skupinu nelze smazat, mají ji tito uživatelé: " + ", ".join(members),
        )
        return redirect("panel-groups")
    group.delete()
    audit.record("group_deleted", request.user, group=group_id)
    messages.success(request, "Skupina smazána.")
    return redirect("panel-groups")


@commander_required
@require_POST
def group_rotate(request, group_id):
    group = get_object_or_404(TeamGroup, id=group_id)
    key = keys.rotate(group.id)
    audit.record("key_rotated", request.user, group=group.id, keyId=key.key_id)
    messages.success(
        request,
        f"Nový klíč {key.key_id} pro {group.name}. Členové ho dostanou při "
        "příštím připojení k hlasovému kanálu.",
    )
    return redirect("panel-groups")


# --- Situation -------------------------------------------------------------------

STATUS_LABELS = {
    "ok": "OK",
    "moving": "V POHYBU",
    "holding": "NA POZICI",
    "wounded": "ZRANĚN",
    "needSupport": "POTŘEBUJI PODPORU",
    "outOfAction": "MIMO AKCI",
}
URGENT_STATUSES = {"wounded", "needSupport"}
# Same as the app's LOST link status.
STALE_AFTER = timedelta(minutes=15)


@commander_required
def situation(request):
    group_id = request.GET.get("group", "")
    members = (
        User.objects.filter(disabled=False)
        .select_related("position")
        .prefetch_related("groups")
    )
    if group_id:
        members = members.filter(groups__id=group_id)
    now = timezone.now()
    rows, silent = [], []
    for member in members:
        position = getattr(member, "position", None)
        if position is None:
            silent.append(member)
            continue
        age = now - position.reported_at
        rows.append(
            {
                "member": member,
                "position": position,
                "mgrs": to_mgrs(position.latitude, position.longitude) or "–",
                "status": STATUS_LABELS.get(position.status, ""),
                "urgent": position.status in URGENT_STATUSES,
                "minutes": max(0, int(age.total_seconds() // 60)),
                "stale": age > STALE_AFTER,
                "map_url": (
                    "https://mapy.cz/zakladni?source=coor"
                    f"&id={position.longitude:.6f},{position.latitude:.6f}"
                    f"&x={position.longitude:.6f}&y={position.latitude:.6f}&z=15"
                ),
            }
        )
    # Urgent first, then fresh before stale, then by name.
    rows.sort(key=lambda r: (not r["urgent"], r["stale"], r["member"].username))
    return render(
        request,
        "panel/situation.html",
        {
            "rows": rows,
            "silent": silent,
            "groups": TeamGroup.objects.all(),
            "group_id": group_id,
            "stale_minutes": int(STALE_AFTER.total_seconds() // 60),
            "recent_messages": GroupMessage.objects.all()[:10],
        },
    )


@commander_required
def group_message_send(request):
    if request.method != "POST":
        return render(
            request,
            "panel/group_message.html",
            {
                "groups": TeamGroup.objects.all(),
                "group_id": request.GET.get("group", ""),
            },
        )
    group = TeamGroup.objects.filter(id=request.POST.get("group", "")).first()
    text = " ".join(request.POST.get("text", "").split())
    if group is None:
        messages.error(request, "Vyberte skupinu.")
    elif not text or len(text) > 500:
        messages.error(request, "Zpráva musí mít 1 až 500 znaků.")
    else:
        priority = request.POST.get("priority") == "on"
        GroupMessage.objects.create(
            group_id=group.id,
            text=text,
            priority=priority,
            author=request.user.display_name or request.user.username,
        )
        audit.record(
            "group_message", request.user, group=group.id, priority=priority
        )
        messages.success(
            request,
            f"Zpráva pro {group.name} odeslána. Aplikace ji dostanou do 2 minut "
            "(v úsporném režimu do 5).",
        )
    return redirect(f"{reverse('panel-situation')}?group={group.id if group else ''}")


# --- Audit ---------------------------------------------------------------------


@commander_required
def audit_log(request):
    entries = []
    for entry in AuditEntry.objects.all()[:200]:
        details = ", ".join(f"{k}={v}" for k, v in entry.details.items())
        entries.append({"entry": entry, "details": details})
    return render(request, "panel/audit.html", {"entries": entries})
