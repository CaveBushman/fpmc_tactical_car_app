from django.shortcuts import redirect
from django.urls import include, path

from core import api

urlpatterns = [
    # JSON API for the app and admin tools (same paths as before).
    path("health", api.routes(GET=api.health)),
    path("auth/login", api.routes(POST=api.login)),
    path("auth/refresh", api.routes(POST=api.refresh)),
    path("auth/password", api.routes(POST=api.change_password)),
    path("ptt/<str:group>/join", api.routes(POST=api.join_ptt)),
    path(
        "admin/users",
        api.routes(GET=api.list_users, POST=api.create_user),
    ),
    path("admin/users/<str:name>", api.routes(PATCH=api.update_user)),
    path("admin/users/<str:name>/password", api.routes(POST=api.reset_password)),
    path("admin/users/<str:name>/revoke", api.routes(POST=api.revoke_sessions)),
    path(
        "admin/users/<str:name>/devices/<str:device>",
        api.routes(DELETE=api.unbind_device),
    ),
    path("admin/groups", api.routes(GET=api.list_groups, POST=api.create_group)),
    path(
        "admin/groups/<str:group_id>",
        api.routes(PATCH=api.update_group, DELETE=api.delete_group),
    ),
    path("admin/groups/<str:group_id>/rotate-key", api.routes(POST=api.rotate_key)),
    path("admin/audit", api.routes(GET=api.read_audit)),
    # The old single-page admin moved to the server-rendered panel.
    path("admin", lambda request: redirect("panel-users")),
    path("panel/", include("core.panel_urls")),
]
