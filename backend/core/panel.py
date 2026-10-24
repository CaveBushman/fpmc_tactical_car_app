"""Server-rendered web panel for commanders: users, devices, groups, keys
and the audit log. Plain HTML forms with CSRF protection, no JavaScript."""

from functools import wraps

from django import forms
from django.contrib import messages
from django.contrib.auth import logout
from django.contrib.auth.forms import AuthenticationForm
from django.contrib.auth.views import LoginView
from django.core.exceptions import PermissionDenied
from django.db import transaction
from django.shortcuts import get_object_or_404, redirect, render
from django.views.decorators.http import require_POST

from . import audit, keys, security
from .api import GROUP_ID, MIN_PASSWORD_LENGTH, USER_NAME
from .models import ROLES, AuditEntry, TeamGroup, User

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


@commander_required
def users(request):
    return render(
        request,
        "panel/users.html",
        {"users": User.objects.prefetch_related("groups", "devices")},
    )


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


# --- Audit ---------------------------------------------------------------------


@commander_required
def audit_log(request):
    entries = []
    for entry in AuditEntry.objects.all()[:200]:
        details = ", ".join(f"{k}={v}" for k, v in entry.details.items())
        entries.append({"entry": entry, "details": details})
    return render(request, "panel/audit.html", {"entries": entries})
