import base64
import json
import tempfile
from datetime import timedelta
from pathlib import Path
from unittest import mock

import jwt
from django.conf import settings
from django.core.cache import cache
from django.core.management import call_command
from django.test import TestCase
from django.utils import timezone

from . import security
from .models import (
    AuditEntry,
    Device,
    GroupKey,
    GroupMessage,
    MemberPosition,
    TeamGroup,
    User,
)
from .passwords import hash_password, verify_password

# A hash written by the former Dart server (password "operator-2026").
DART_HASH = (
    "pbkdf2-sha256$120000$7vv5C563nAkL2fsfsUfaTg==$"
    "91dxv6uyYkd2DjxdqzCdbf6bxVZFuqTC+nmGHeOGito="
)


def make_user(name, password, role="operator", groups=("alpha", "bravo"), **extra):
    user = User.objects.create(
        username=name,
        display_name=name.upper(),
        role=role,
        password=hash_password(password, iterations=1000),
        **extra,
    )
    user.groups.set(groups)
    return user


class ApiTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.operator = make_user("operator", "operator-pass")
        self.commander = make_user(
            "commander", "commander-pass", role="commander",
            groups=("alpha", "command"),
        )

    def call(self, method, path, body=None, token=None, **headers):
        if token:
            headers["HTTP_AUTHORIZATION"] = f"Bearer {token}"
        return self.client.generic(
            method,
            path,
            data=json.dumps(body) if body is not None else "",
            content_type="application/json",
            **headers,
        )

    def login(self, user="operator", password="operator-pass", **extra):
        response = self.call(
            "POST", "/auth/login", {"userName": user, "password": password, **extra}
        )
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()["sessionToken"]


class PasswordTests(TestCase):
    def test_hashes_verify_and_reject(self):
        encoded = hash_password("secret-123", iterations=1000)
        self.assertTrue(verify_password("secret-123", encoded))
        self.assertFalse(verify_password("secret-124", encoded))
        self.assertFalse(verify_password("secret-123", "garbage"))
        self.assertNotEqual(hash_password("a"), hash_password("a"))

    def test_hashes_from_the_dart_server_still_verify(self):
        self.assertTrue(verify_password("operator-2026", DART_HASH))
        self.assertFalse(verify_password("operator-2027", DART_HASH))

    def test_django_auth_uses_the_same_format(self):
        user = User.objects.create(username="x", password=DART_HASH)
        self.assertTrue(user.check_password("operator-2026"))
        user.set_password("new-password-1")
        self.assertTrue(user.password.startswith("pbkdf2-sha256$120000$"))


class LoginTests(ApiTestCase):
    def test_login_returns_session_profile_and_groups(self):
        response = self.call(
            "POST", "/auth/login",
            {"userName": " OPERATOR ", "password": "operator-pass"},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response["Content-Type"], "application/json; charset=utf-8"
        )
        self.assertEqual(response["Cache-Control"], "no-store")
        body = response.json()
        self.assertEqual(body["expiresInSeconds"], 43200)
        self.assertEqual(
            body["user"],
            {
                "userName": "operator",
                "displayName": "OPERATOR",
                "role": "operator",
                "groups": ["alpha", "bravo"],
            },
        )
        self.assertEqual([g["id"] for g in body["groups"]], ["alpha", "bravo"])
        self.assertEqual(
            body["groups"][1],
            {"id": "bravo", "name": "BRAVO", "channelIndex": 1,
             "pttEnabled": True, "description": ""},
        )
        claims = jwt.decode(
            body["sessionToken"], settings.SESSION_SECRET, algorithms=["HS256"],
            audience="tactical-app", issuer="fpmc-tactical",
        )
        self.assertEqual(claims["typ"], "session")
        self.assertEqual(claims["sub"], "operator")
        self.assertEqual(claims["ver"], 1)
        self.assertNotIn("dev", claims)

    def test_unknown_user_and_wrong_password_look_the_same(self):
        unknown = self.call("POST", "/auth/login",
                            {"userName": "nobody", "password": "x"})
        wrong = self.call("POST", "/auth/login",
                          {"userName": "operator", "password": "x"})
        self.assertEqual(unknown.status_code, 401)
        self.assertEqual(unknown.content, wrong.content)
        self.assertEqual(wrong.json(), {"error": "invalid_credentials"})

    def test_missing_credentials_and_bad_json(self):
        response = self.client.post(
            "/auth/login", data="not json", content_type="application/json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json(), {"error": "missing_credentials"})

    def test_disabled_account(self):
        self.operator.disabled = True
        self.operator.save()
        response = self.call("POST", "/auth/login",
                             {"userName": "operator", "password": "operator-pass"})
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json(), {"error": "account_disabled"})

    def test_five_failures_lock_the_user_from_that_address(self):
        for _ in range(5):
            self.call("POST", "/auth/login",
                      {"userName": "operator", "password": "wrong"})
        locked = self.call("POST", "/auth/login",
                           {"userName": "operator", "password": "operator-pass"})
        self.assertEqual(locked.status_code, 429)
        self.assertEqual(locked.json()["error"], "locked")
        self.assertGreater(locked.json()["retryAfterSeconds"], 250)
        # Another address is not affected.
        other = self.call(
            "POST", "/auth/login",
            {"userName": "operator", "password": "operator-pass"},
            REMOTE_ADDR="10.0.0.9",
        )
        self.assertEqual(other.status_code, 200)
        # The lock ends after five minutes.
        later = security.time.time() + 6 * 60
        with mock.patch.object(security.time, "time", return_value=later):
            ok = self.call("POST", "/auth/login",
                           {"userName": "operator", "password": "operator-pass"})
        self.assertEqual(ok.status_code, 200)

    def test_address_rate_limit(self):
        for i in range(30):
            self.call("POST", "/auth/login",
                      {"userName": f"user{i}", "password": "x"})
        response = self.call("POST", "/auth/login",
                             {"userName": "operator", "password": "operator-pass"})
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.json()["error"], "rate_limited")
        self.assertIsInstance(response.json()["retryAfterSeconds"], int)

    def test_forwarded_address_only_behind_a_trusted_proxy(self):
        request = mock.Mock(META={"REMOTE_ADDR": "1.1.1.1",
                                  "HTTP_X_FORWARDED_FOR": "2.2.2.2, 3.3.3.3"})
        self.assertEqual(security.client_ip(request), "1.1.1.1")
        with self.settings(TRUST_PROXY=True):
            self.assertEqual(security.client_ip(request), "2.2.2.2")


class DeviceTests(ApiTestCase):
    def test_devices_are_bound_up_to_the_limit(self):
        self.login(deviceId="a" * 32, deviceName="Android")
        self.login(deviceId="a" * 32, deviceName="Android")  # same: fine
        self.login(deviceId="b" * 32, deviceName="iPhone")
        refused = self.call(
            "POST", "/auth/login",
            {"userName": "operator", "password": "operator-pass",
             "deviceId": "c" * 32},
        )
        self.assertEqual(refused.status_code, 403)
        self.assertEqual(refused.json(), {"error": "device_not_allowed"})
        self.assertEqual(self.operator.devices.count(), 2)

    def test_unbinding_a_device_ends_its_sessions(self):
        token = self.login(deviceId="a" * 32, deviceName="Android")
        admin = self.login("commander", "commander-pass")
        self.assertEqual(self.call("POST", "/auth/refresh", token=token).status_code,
                         200)
        response = self.call(
            "DELETE", f"/admin/users/operator/devices/{'a' * 32}", token=admin
        )
        self.assertEqual(response.json(), {"ok": True})
        self.assertEqual(self.call("POST", "/auth/refresh", token=token).status_code,
                         401)


class SessionTests(ApiTestCase):
    def test_refresh_keeps_the_device_and_revoke_ends_sessions(self):
        token = self.login(deviceId="d" * 32)
        refreshed = self.call("POST", "/auth/refresh", token=token)
        self.assertEqual(refreshed.status_code, 200)
        new_token = refreshed.json()["sessionToken"]
        self.assertEqual(refreshed.json()["expiresInSeconds"], 43200)
        claims = jwt.decode(new_token, options={"verify_signature": False})
        self.assertEqual(claims["dev"], "d" * 32)

        admin = self.login("commander", "commander-pass")
        self.call("POST", "/admin/users/operator/revoke", token=admin)
        self.assertEqual(self.call("POST", "/auth/refresh", token=new_token).json(),
                         {"error": "unauthenticated"})

    def test_bad_tokens_are_rejected(self):
        self.assertEqual(self.call("POST", "/auth/refresh").status_code, 401)
        self.assertEqual(
            self.call("POST", "/auth/refresh", token="garbage").status_code, 401
        )
        forged = jwt.encode(
            {"typ": "session", "sub": "commander", "ver": 1, "iss": "fpmc-tactical",
             "aud": "tactical-app", "exp": 9999999999},
            "another-secret-0123456789abcdefghij", algorithm="HS256",
        )
        self.assertEqual(
            self.call("POST", "/auth/refresh", token=forged).status_code, 401
        )

    def test_password_change(self):
        token = self.login()
        wrong = self.call("POST", "/auth/password",
                          {"oldPassword": "x", "newPassword": "y" * 12}, token=token)
        self.assertEqual(wrong.status_code, 403)
        weak = self.call("POST", "/auth/password",
                         {"oldPassword": "operator-pass", "newPassword": "short"},
                         token=token)
        self.assertEqual(weak.json(), {"error": "weak_password"})
        ok = self.call("POST", "/auth/password",
                       {"oldPassword": "operator-pass",
                        "newPassword": "new-password-1"}, token=token)
        self.assertEqual(ok.status_code, 200)
        self.assertNotIn("expiresInSeconds", ok.json())
        # Old token revoked, new one works, new password logs in.
        self.assertEqual(self.call("POST", "/auth/refresh", token=token).status_code,
                         401)
        self.assertEqual(
            self.call("POST", "/auth/refresh",
                      token=ok.json()["sessionToken"]).status_code, 200)
        self.login(password="new-password-1")


class PttTests(ApiTestCase):
    def test_join_returns_livekit_token_and_keys(self):
        token = self.login()
        response = self.call("POST", "/ptt/alpha/join", token=token)
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["livekitUrl"], settings.LIVEKIT_URL)
        self.assertEqual(body["room"], "ptt-alpha")
        self.assertEqual(body["identity"], "operator")
        self.assertEqual(body["key"]["id"], 1)
        self.assertNotIn("previousKey", body)
        claims = jwt.decode(body["token"], settings.LIVEKIT_API_SECRET,
                            algorithms=["HS256"])
        self.assertEqual(claims["iss"], settings.LIVEKIT_API_KEY)
        self.assertEqual(claims["sub"], "operator")
        self.assertEqual(claims["name"], "OPERATOR")
        self.assertEqual(claims["video"]["room"], "ptt-alpha")
        self.assertEqual(claims["video"]["canPublishSources"], ["microphone"])
        self.assertEqual(claims["exp"] - claims["nbf"], 6 * 3600)

    def test_rotation_keeps_the_previous_key(self):
        token = self.login()
        first = self.call("POST", "/ptt/alpha/join", token=token).json()["key"]
        admin = self.login("commander", "commander-pass")
        rotated = self.call("POST", "/admin/groups/alpha/rotate-key", token=admin)
        self.assertEqual(rotated.json(), {"group": "alpha", "keyId": 2})
        self.call("POST", "/admin/groups/alpha/rotate-key", token=admin)
        body = self.call("POST", "/ptt/alpha/join", token=token).json()
        self.assertEqual(body["key"]["id"], 3)
        self.assertEqual(body["previousKey"]["id"], 2)
        self.assertNotEqual(body["key"]["key"], first["key"])
        self.assertEqual(GroupKey.objects.filter(group_id="alpha").count(), 2)

    def test_foreign_or_disabled_groups(self):
        token = self.login()
        self.assertEqual(self.call("POST", "/ptt/command/join", token=token).json(),
                         {"error": "forbidden_group"})
        TeamGroup.objects.filter(id="alpha").update(ptt_enabled=False)
        self.assertEqual(self.call("POST", "/ptt/alpha/join", token=token).json(),
                         {"error": "ptt_disabled"})
        self.assertEqual(self.call("POST", "/ptt/alpha/join").status_code, 401)


class AdminApiTests(ApiTestCase):
    def setUp(self):
        super().setUp()
        self.admin = self.login("commander", "commander-pass")

    def test_commander_only(self):
        token = self.login()
        response = self.call("GET", "/admin/users", token=token)
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json(), {"error": "commander_only"})
        self.assertTrue(AuditEntry.objects.filter(event="admin_denied").exists())

    def test_list_users_hides_hashes(self):
        response = self.call("GET", "/admin/users", token=self.admin)
        body = response.json()
        self.assertEqual([u["userName"] for u in body["users"]],
                         ["commander", "operator"])
        self.assertEqual(body["roles"], ["commander", "medic", "operator"])
        self.assertEqual(body["groups"], ["alpha", "bravo", "command", "med"])
        self.assertNotIn("pbkdf2", response.content.decode())
        self.assertNotIn("passwordHash", response.content.decode())

    def test_create_user_validation(self):
        cases = [
            ({"userName": "x"}, 400, "invalid_user_name"),
            ({"userName": "operator", "password": "p" * 10, "groups": []}, 409,
             "user_exists"),
            ({"userName": "newbie", "password": "short", "groups": []}, 400,
             "weak_password"),
            ({"userName": "newbie", "password": "p" * 10, "role": "king",
              "groups": []}, 400, "unknown_role"),
            ({"userName": "newbie", "password": "p" * 10}, 400, "groups_required"),
            ({"userName": "newbie", "password": "p" * 10, "groups": ["zulu"]}, 400,
             "unknown_group"),
            ({"userName": "newbie", "password": "p" * 10, "groups": [],
              "displayName": "x" * 41}, 400, "display_name_too_long"),
        ]
        for body, status, code in cases:
            response = self.call("POST", "/admin/users", body, token=self.admin)
            self.assertEqual((response.status_code, response.json()["error"]),
                             (status, code), body)

    def test_create_and_update_user(self):
        created = self.call(
            "POST", "/admin/users",
            {"userName": "Scout", "password": "scout-pass-1", "groups": ["med"]},
            token=self.admin,
        )
        self.assertEqual(created.status_code, 201)
        self.assertEqual(created.json()["displayName"], "SCOUT")
        self.assertEqual(created.json()["role"], "operator")
        self.login("scout", "scout-pass-1")

        version = User.objects.get(username="scout").session_version
        renamed = self.call("PATCH", "/admin/users/scout",
                            {"displayName": "Průzkum"}, token=self.admin)
        self.assertEqual(renamed.json()["displayName"], "Průzkum")
        self.assertEqual(User.objects.get(username="scout").session_version, version)

        moved = self.call("PATCH", "/admin/users/scout",
                          {"groups": ["alpha"], "disabled": True}, token=self.admin)
        self.assertEqual(moved.json()["groups"], ["alpha"])
        self.assertTrue(moved.json()["disabled"])
        self.assertEqual(User.objects.get(username="scout").session_version,
                         version + 1)
        self.assertEqual(
            self.call("PATCH", "/admin/users/nobody", {}, token=self.admin).json(),
            {"error": "not_found"},
        )

    def test_cannot_lock_out_self(self):
        response = self.call("PATCH", "/admin/users/commander", {"role": "medic"},
                             token=self.admin)
        self.assertEqual(response.json(), {"error": "cannot_lock_out_self"})

    def test_reset_password(self):
        weak = self.call("POST", "/admin/users/operator/password",
                         {"password": "x"}, token=self.admin)
        self.assertEqual(weak.json(), {"error": "weak_password"})
        ok = self.call("POST", "/admin/users/operator/password",
                       {"password": "reset-pass-1"}, token=self.admin)
        self.assertEqual(ok.json(), {"ok": True})
        self.login(password="reset-pass-1")

    def test_groups_crud(self):
        listing = self.call("GET", "/admin/groups", token=self.admin).json()
        alpha = next(g for g in listing["groups"] if g["id"] == "alpha")
        self.assertEqual(alpha["members"], ["commander", "operator"])

        cases = [
            ({"id": "x"}, 400, "invalid_group_id"),
            ({"id": "alpha"}, 409, "group_exists"),
            ({"id": "recon", "name": ""}, 400, "invalid_name"),
            ({"id": "recon", "channelIndex": 8}, 400, "invalid_channel"),
            ({"id": "recon", "channelIndex": 4.0}, 400, "invalid_channel"),
            ({"id": "recon", "description": "d" * 81}, 400, "description_too_long"),
        ]
        for body, status, code in cases:
            response = self.call("POST", "/admin/groups", body, token=self.admin)
            self.assertEqual((response.status_code, response.json()["error"]),
                             (status, code), body)

        created = self.call(
            "POST", "/admin/groups",
            {"id": "Recon", "channelIndex": 4, "pttEnabled": False,
             "description": "Průzkum"},
            token=self.admin,
        )
        self.assertEqual(created.status_code, 201)
        self.assertEqual(
            created.json(),
            {"id": "recon", "name": "RECON", "channelIndex": 4,
             "pttEnabled": False, "description": "Průzkum"},
        )
        updated = self.call("PATCH", "/admin/groups/recon", {"name": "PRŮZKUM"},
                            token=self.admin)
        self.assertEqual(updated.json()["name"], "PRŮZKUM")
        self.assertIn("charset=utf-8", updated["Content-Type"])

        in_use = self.call("DELETE", "/admin/groups/alpha", token=self.admin)
        self.assertEqual(in_use.status_code, 409)
        self.assertEqual(in_use.json(),
                         {"error": "group_in_use", "members": ["commander", "operator"]})
        self.assertEqual(self.call("DELETE", "/admin/groups/recon",
                                   token=self.admin).json(), {"ok": True})

    def test_audit_is_newest_first_and_limited(self):
        self.call("POST", "/admin/users/operator/revoke", token=self.admin)
        entries = self.call("GET", "/admin/audit?limit=2", token=self.admin).json()
        self.assertEqual(len(entries["entries"]), 2)
        self.assertEqual(entries["entries"][0]["event"], "sessions_revoked")
        self.assertEqual(entries["entries"][0]["user"], "commander")
        self.assertEqual(entries["entries"][0]["target"], "operator")

    def test_unknown_routes_and_methods(self):
        self.assertEqual(self.client.get("/nothing").status_code, 404)
        self.assertEqual(self.client.get("/auth/login").status_code, 404)
        self.assertEqual(self.client.get("/health").json(), {"ok": True})


class PanelTests(TestCase):
    def setUp(self):
        cache.clear()
        self.commander = make_user("velitel", "velitel-pass", role="commander",
                                   groups=("alpha",))
        self.operator = make_user("operator", "operator-pass")

    def test_only_commanders_log_in(self):
        response = self.client.post(
            "/panel/login", {"username": "operator", "password": "operator-pass"}
        )
        self.assertContains(response, "Do panelu mají přístup jen velitelé.")
        response = self.client.post(
            "/panel/login", {"username": "VELITEL", "password": "velitel-pass"}
        )
        self.assertRedirects(response, "/panel/")
        page = self.client.get("/panel/")
        self.assertContains(page, "operator")
        self.assertIn("default-src 'none'", page["Content-Security-Policy"])

    def test_pages_need_a_login(self):
        self.assertRedirects(self.client.get("/panel/groups"), "/panel/login",
                             fetch_redirect_response=False)
        self.client.force_login(self.operator)
        self.assertEqual(self.client.get("/panel/").status_code, 403)

    def test_user_and_group_management(self):
        self.client.force_login(self.commander)
        response = self.client.post(
            "/panel/users/new",
            {"user_name": "Medik", "display_name": "", "role": "medic",
             "groups": ["med"], "password": "medik-pass-1"},
        )
        self.assertRedirects(response, "/panel/users/medik")
        medik = User.objects.get(username="medik")
        self.assertEqual(medik.display_name, "MEDIK")
        self.assertEqual(medik.group_ids(), ["med"])

        self.client.post(
            "/panel/users/medik",
            {"display_name": "Zdravotník", "role": "medic", "groups": ["med", "alpha"]},
        )
        medik.refresh_from_db()
        self.assertEqual(medik.group_ids(), ["alpha", "med"])
        self.assertEqual(medik.session_version, 2)

        Device.objects.create(user=medik, device_id="e" * 32, name="Android")
        device = medik.devices.get()
        self.client.post(f"/panel/users/medik/devices/{device.pk}/unbind")
        self.assertFalse(medik.devices.exists())

        self.client.post("/panel/groups/new",
                         {"group_id": "recon", "name": "RECON", "channel_index": 5,
                          "ptt_enabled": "on", "description": ""})
        self.assertTrue(TeamGroup.objects.filter(id="recon", channel_index=5).exists())
        self.client.post("/panel/groups/recon/rotate")
        self.assertEqual(GroupKey.objects.filter(group_id="recon").count(), 1)
        self.client.post("/panel/groups/med/delete")  # has members: kept
        self.assertTrue(TeamGroup.objects.filter(id="med").exists())
        self.assertContains(self.client.get("/panel/audit"), "group_created")

    def test_commander_cannot_lock_out_self(self):
        self.client.force_login(self.commander)
        response = self.client.post(
            "/panel/users/velitel",
            {"display_name": "", "role": "operator", "groups": ["alpha"]},
        )
        self.assertContains(response, "Sami sebe nemůžete")
        self.commander.refresh_from_db()
        self.assertEqual(self.commander.role, "commander")


class ImportTests(TestCase):
    def test_imports_the_dart_data_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            data = Path(directory)
            (data / "users.json").write_text(json.dumps({"users": [{
                "userName": "operator", "displayName": "OPERATOR",
                "role": "operator", "groups": ["alpha", "recon"],
                "passwordHash": DART_HASH, "disabled": False,
                "sessionVersion": 3,
                "devices": [{"id": "f" * 32, "name": "Android",
                             "boundAt": "2026-10-20T10:00:00.000Z",
                             "lastSeen": "2026-10-24T09:00:00.000Z"}],
            }]}))
            (data / "groups.json").write_text(json.dumps({"groups": [
                {"id": "recon", "name": "RECON", "channelIndex": 5,
                 "pttEnabled": False, "description": "x"},
            ]}))
            (data / "group_keys.json").write_text(json.dumps({"recon": [
                {"id": 4, "key": "A" * 44, "createdAt": "2026-10-01T00:00:00.000Z"},
                {"id": 5, "key": "B" * 44, "createdAt": "2026-10-02T00:00:00.000Z"},
            ]}))
            (data / "audit.jsonl").write_text(
                '{"at":"2026-10-24T08:00:00.000Z","event":"login",'
                '"user":"operator","ip":"1.2.3.4"}\n'
            )
            call_command("import_dart_data", directory, stdout=mock.Mock())

        user = User.objects.get(username="operator")
        self.assertTrue(user.check_password("operator-2026"))
        self.assertEqual(user.session_version, 3)
        self.assertEqual(user.group_ids(), ["alpha", "recon"])
        self.assertEqual(user.devices.get().device_id, "f" * 32)
        self.assertFalse(TeamGroup.objects.get(id="recon").ptt_enabled)
        self.assertEqual(
            list(GroupKey.objects.filter(group_id="recon").values_list("key_id", flat=True)),
            [4, 5],
        )
        entry = AuditEntry.objects.get(event="login")
        self.assertEqual(entry.to_json()["ip"], "1.2.3.4")


class PanelTeamToolsTests(TestCase):
    def setUp(self):
        cache.clear()
        self.commander = make_user("velitel", "velitel-pass", role="commander",
                                   groups=("alpha",))
        self.client.force_login(self.commander)

    def test_audit_shows_czech_labels_and_readable_details(self):
        AuditEntry.objects.create(event="user_created", user="velitel", details={
            "target": "novak", "role": "medic", "groups": ["alpha", "bravo"],
            "imported": True,
        })
        AuditEntry.objects.create(event="panel_login_failed", details={"ip": "10.0.0.9"})
        html = self.client.get("/panel/audit").content.decode()
        self.assertIn("Vytvořen uživatel", html)
        self.assertIn("uživatel: novak; role: Zdravotník; skupiny: alpha, bravo; hromadně: ano", html)
        self.assertIn('<span class="off">Chybné heslo do panelu</span>', html)
        self.assertNotIn("[&#x27;alpha&#x27;", html)

    def test_user_list_shows_czech_roles_as_phone_cards(self):
        html = self.client.get("/panel/").content.decode()
        self.assertIn('<td data-label="Role">Velitel</td>', html)
        self.assertIn('<table class="stack">', html)

    def test_import_preview_reports_errors_per_line(self):
        make_user("novak", "novak-pass-1")
        text = (
            "uzivatel;jmeno;role;skupiny\n"
            "novak;NOVÁK;operator;alpha\n"           # exists
            "dvorak;DVOŘÁK;zdravotník;alpha med\n"   # fine (Czech role)
            "x;;operator;\n"                         # bad name
            "svoboda;;king;zulu\n"                   # bad role + group
            "dvorak;;operator;\n"                    # duplicate in list
        )
        response = self.client.post("/panel/users/import",
                                    {"rows": text, "action": "preview"})
        errors = response.context["errors"]
        self.assertEqual([line for line, _ in errors], [2, 4, 5, 6])
        self.assertIn("neznámá role king", errors[2][1])
        self.assertIn("neznámé skupiny zulu", errors[2][1])
        self.assertEqual([r["user_name"] for r in response.context["rows"]],
                         ["dvorak"])
        # With errors nothing can be created.
        self.client.post("/panel/users/import", {"rows": text, "action": "create"})
        self.assertFalse(User.objects.filter(username="dvorak").exists())

    def test_import_creates_users_with_one_time_passwords(self):
        text = "novak,NOVÁK,operator,alpha|bravo\ndvorak,,medic,med\n"
        response = self.client.post("/panel/users/import",
                                    {"rows": text, "action": "create"})
        created = response.context["created"]
        self.assertEqual([c["user_name"] for c in created], ["novak", "dvorak"])
        self.assertContains(response, "Stáhnout CSV s hesly")
        dvorak = User.objects.get(username="dvorak")
        self.assertEqual((dvorak.display_name, dvorak.role, dvorak.group_ids()),
                         ("DVORAK", "medic", ["med"]))
        password = created[1]["password"]
        self.assertEqual(len(password), 12)
        self.assertTrue(dvorak.check_password(password))
        # The app can log in with it; the password is in no audit entry.
        login = self.client.post(
            "/auth/login",
            data=json.dumps({"userName": "dvorak", "password": password}),
            content_type="application/json",
        )
        self.assertEqual(login.status_code, 200)
        for entry in AuditEntry.objects.all():
            self.assertNotIn(password, json.dumps(entry.to_json()))
        csv_text = base64.b64decode(response.context["download"]).decode("utf-8")
        self.assertIn(f"dvorak;DVORAK;medic;med;{password}", csv_text)

    def test_search_and_activity_filter(self):
        quiet = make_user("tichy", "tichy-pass-1")
        busy = make_user("aktivni", "aktivni-pass-1")
        busy.display_name = "Rychlá četa"
        busy.save()
        Device.objects.create(user=busy, device_id="1" * 32)
        Device.objects.create(
            user=quiet, device_id="2" * 32,
            last_seen=timezone.now() - timedelta(days=30),
        )
        names = lambda **q: [u.username for u in self.client.get(
            "/panel/", q).context["users"]]
        self.assertEqual(names(q="RYCHL"), ["aktivni"])
        self.assertEqual(names(show="inactive"), ["tichy", "velitel"])
        busy.disabled = True
        busy.save()
        self.assertEqual(names(show="disabled"), ["aktivni"])

    def test_own_password_change_ends_app_sessions(self):
        response = self.client.post(
            "/panel/password",
            {"old_password": "velitel-pass", "new_password1": "nove-heslo-123",
             "new_password2": "nove-heslo-123"},
        )
        self.assertRedirects(response, "/panel/")
        self.commander.refresh_from_db()
        self.assertTrue(self.commander.check_password("nove-heslo-123"))
        self.assertEqual(self.commander.session_version, 2)
        # Still logged in to the panel.
        self.assertEqual(self.client.get("/panel/").status_code, 200)
        wrong = self.client.post(
            "/panel/password",
            {"old_password": "x", "new_password1": "a" * 12, "new_password2": "a" * 12},
        )
        self.assertContains(wrong, "Současné heslo nesouhlasí.")


class OperationsTests(TestCase):
    def test_health_reports_a_dead_database(self):
        self.assertEqual(self.client.get("/health").json(), {"ok": True})
        from django.db import DatabaseError

        with mock.patch("core.api.connection.cursor", side_effect=DatabaseError):
            response = self.client.get("/health")
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()["error"], "database_unavailable")

    def test_prune_audit_keeps_recent_entries(self):
        old = AuditEntry.objects.create(event="login")
        AuditEntry.objects.filter(pk=old.pk).update(
            at=timezone.now() - timedelta(days=400)
        )
        recent = AuditEntry.objects.create(event="login")
        out = mock.Mock()
        call_command("prune_audit", stdout=out)
        self.assertEqual(list(AuditEntry.objects.values_list("pk", flat=True)),
                         [recent.pk])
        call_command("prune_audit", days=0, stdout=out)  # disabled
        self.assertEqual(AuditEntry.objects.count(), 1)

    def test_https_redirect_spares_the_health_check(self):
        with self.settings(SECURE_SSL_REDIRECT=True,
                           SECURE_REDIRECT_EXEMPT=[r"^health$"]):
            self.assertEqual(self.client.get("/health").status_code, 200)
            self.assertEqual(self.client.get("/panel/login").status_code, 301)
            # Behind the proxy the forwarded scheme counts as HTTPS.
            secure = self.client.get(
                "/panel/login", HTTP_X_FORWARDED_PROTO="https", secure=True
            )
            self.assertEqual(secure.status_code, 200)


# Reference values produced by the app's formatMgrs (mgrs_dart).
MGRS_REFERENCE = [
    (50.087451, 14.420671, "33U VR 58556 48514"),
    (49.19506, 16.606837, "33U XQ 17066 50382"),
    (49.8346, 18.282, "34U CA 04553 23784"),
    (51.0, 12.0, "33U TS 89511 54109"),
    (-33.8688, 151.2093, "56H LH 34368 50948"),
    (0.5, 10.0, "32N PF 11276 55273"),
    (64.1466, -21.9426, "27W VM 54138 13689"),
    (40.7128, -74.006, "18T WL 83959 07350"),
    (-0.1, -78.5, "17M QV 78275 88936"),
    (59.9139, 10.7522, "32V NM 97979 43118"),  # Norway exception
    (-54.8, -68.3, "19F EV 45000 27239"),
]


class SituationTests(ApiTestCase):
    def test_mgrs_matches_the_app(self):
        from .mgrs import to_mgrs

        for lat, lon, expected in MGRS_REFERENCE:
            self.assertEqual(to_mgrs(lat, lon), expected, (lat, lon))
        self.assertIsNone(to_mgrs(85, 0))

    def report(self, token, **body):
        return self.call("POST", "/report", body, token=token)

    def test_report_keeps_only_the_latest_position(self):
        token = self.login()
        ok = self.report(token, lat=50.087451, lon=14.420671, alt=240.6,
                         battery=101, status="wounded")
        self.assertEqual(ok.json(), {"ok": True, "messages": []})
        position = self.operator.position
        self.assertEqual((position.battery_percent, position.altitude_m,
                          position.status), (100, 240, "wounded"))
        # A later report replaces it; a late, older one is ignored.
        now = timezone.now()
        self.report(token, lat=50.1, lon=14.5, at=now.isoformat())
        self.report(token, lat=10.0, lon=10.0,
                    at=(now - timedelta(minutes=10)).isoformat())
        position = MemberPosition.objects.get(user=self.operator)
        self.assertEqual((position.latitude, position.status), (50.1, "wounded"))
        self.assertEqual(MemberPosition.objects.count(), 1)

    def test_report_validation(self):
        token = self.login()
        cases = [
            ({"lat": 91, "lon": 0}, "invalid_position"),
            ({"lat": "50", "lon": 14}, "invalid_position"),
            ({"lat": 50, "lon": 14, "status": "asleep"}, "invalid_status"),
            ({"lat": 50, "lon": 14, "at": "yesterday"}, "invalid_time"),
            ({"lat": 50, "lon": 14,
              "at": (timezone.now() + timedelta(hours=1)).isoformat()},
             "invalid_time"),
        ]
        for body, code in cases:
            response = self.report(token, **body)
            self.assertEqual((response.status_code, response.json()["error"]),
                             (400, code), body)
        self.assertEqual(self.call("POST", "/report", {"lat": 1, "lon": 1})
                         .status_code, 401)
        self.assertFalse(AuditEntry.objects.filter(event__contains="report").exists())

    def test_situation_page_puts_urgent_and_fresh_first(self):
        medic = make_user("medic", "medic-pass-1", groups=("med",))
        make_user("silent", "silent-pass-1", groups=("alpha",))
        now = timezone.now()
        MemberPosition.objects.create(
            user=self.operator, latitude=50.087451, longitude=14.420671,
            status="ok", battery_percent=80, reported_at=now - timedelta(hours=1),
        )
        MemberPosition.objects.create(
            user=medic, latitude=49.19506, longitude=16.606837,
            status="wounded", reported_at=now - timedelta(minutes=2),
        )
        self.client.force_login(self.commander)
        page = self.client.get("/panel/situation")
        rows = page.context["rows"]
        self.assertEqual([r["member"].username for r in rows], ["medic", "operator"])
        self.assertEqual(rows[0]["status"], "ZRANĚN")
        self.assertTrue(rows[1]["stale"])
        self.assertEqual(rows[1]["mgrs"], "33U VR 58556 48514")
        self.assertIn("silent", [m.username for m in page.context["silent"]])
        self.assertContains(page, "mapy.cz")
        self.assertContains(page, '<meta http-equiv="refresh" content="60">')
        only_med = self.client.get("/panel/situation", {"group": "med"})
        self.assertEqual([r["member"].username for r in only_med.context["rows"]],
                         ["medic"])


class PasswordlessLoginTests(ApiTestCase):
    def login_without_password(self, name="operator"):
        return self.call("POST", "/auth/login", {"userName": name, "password": ""})

    def test_off_by_default(self):
        self.assertEqual(self.login_without_password().status_code, 400)

    def test_development_switch(self):
        with self.settings(DEV_PASSWORDLESS_LOGIN=True):
            ok = self.login_without_password()
            self.assertEqual(ok.status_code, 200)
            self.assertEqual(ok.json()["user"]["userName"], "operator")
            # Unknown names and blocked accounts still cannot log in.
            self.assertEqual(self.login_without_password("nobody").status_code, 401)
            self.operator.disabled = True
            self.operator.save()
            self.assertEqual(self.login_without_password().json(),
                             {"error": "account_disabled"})
        self.assertTrue(
            AuditEntry.objects.filter(event="login_passwordless").exists()
        )

    def test_needs_debug(self):
        import importlib
        import os

        from tactical import settings as module

        with mock.patch.dict(os.environ, {"DEV_PASSWORDLESS_LOGIN": "1",
                                          "DEBUG": ""}):
            reloaded = importlib.reload(module)
            self.assertFalse(reloaded.DEV_PASSWORDLESS_LOGIN)
        importlib.reload(module)


class GroupMessageTests(ApiTestCase):
    def test_messages_ride_on_position_reports(self):
        token = self.login()  # operator: alpha, bravo
        old = GroupMessage.objects.create(group_id="alpha", text="staré",
                                          author="HQ")
        GroupMessage.objects.filter(pk=old.pk).update(
            created_at=timezone.now() - timedelta(hours=2)
        )
        first = GroupMessage.objects.create(group_id="alpha", text="Přesun na RV-1",
                                            priority=True, author="VELITEL")
        GroupMessage.objects.create(group_id="command", text="jen velení",
                                    author="VELITEL")
        report = self.call("POST", "/report", {"lat": 50, "lon": 14}, token=token)
        got = report.json()["messages"]
        # First pickup: recent only, own groups only.
        self.assertEqual([m["text"] for m in got], ["Přesun na RV-1"])
        self.assertEqual(got[0]["groupId"], "alpha")
        self.assertTrue(got[0]["priority"])
        self.assertEqual(got[0]["author"], "VELITEL")

        second = GroupMessage.objects.create(group_id="bravo", text="Druhá",
                                             author="VELITEL")
        again = self.call("POST", "/report",
                          {"lat": 50, "lon": 14, "sinceMessageId": first.id},
                          token=token).json()["messages"]
        self.assertEqual([m["id"] for m in again], [second.id])
        none = self.call("POST", "/report",
                         {"lat": 50, "lon": 14, "sinceMessageId": second.id},
                         token=token).json()["messages"]
        self.assertEqual(none, [])

    def test_panel_sends_to_a_group(self):
        self.client.force_login(self.commander)
        form = self.client.get("/panel/situation/message", {"group": "bravo"})
        self.assertContains(form, 'value="bravo" selected')
        response = self.client.post(
            "/panel/situation/message",
            {"group": "bravo", "text": "  Návrat   na základnu ", "priority": "on"},
        )
        self.assertRedirects(response, "/panel/situation?group=bravo",
                             fetch_redirect_response=False)
        message = GroupMessage.objects.get()
        self.assertEqual((message.text, message.priority, message.author),
                         ("Návrat na základnu", True, "COMMANDER"))
        self.assertTrue(AuditEntry.objects.filter(event="group_message").exists())
        self.client.post("/panel/situation/message", {"group": "bravo", "text": " "})
        self.client.post("/panel/situation/message", {"group": "zulu", "text": "x"})
        self.assertEqual(GroupMessage.objects.count(), 1)
        page = self.client.get("/panel/situation")
        self.assertContains(page, "Návrat na základnu")
