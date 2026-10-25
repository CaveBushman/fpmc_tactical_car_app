from django.urls import path

from . import panel

urlpatterns = [
    path("login", panel.PanelLoginView.as_view(), name="panel-login"),
    path("logout", panel.logout_view, name="panel-logout"),
    path("", panel.users, name="panel-users"),
    path("users/new", panel.user_create, name="panel-user-create"),
    path("users/import", panel.users_import, name="panel-users-import"),
    path("password", panel.own_password, name="panel-own-password"),
    path("users/<str:name>", panel.user_edit, name="panel-user-edit"),
    path("users/<str:name>/password", panel.user_password, name="panel-user-password"),
    path("users/<str:name>/revoke", panel.user_revoke, name="panel-user-revoke"),
    path(
        "users/<str:name>/devices/<int:pk>/unbind",
        panel.device_unbind,
        name="panel-device-unbind",
    ),
    path("groups", panel.groups, name="panel-groups"),
    path("groups/new", panel.group_create, name="panel-group-create"),
    path("groups/<str:group_id>", panel.group_edit, name="panel-group-edit"),
    path("groups/<str:group_id>/delete", panel.group_delete, name="panel-group-delete"),
    path("groups/<str:group_id>/rotate", panel.group_rotate, name="panel-group-rotate"),
    path("situation", panel.situation, name="panel-situation"),
    path("situation/message", panel.group_message_send, name="panel-situation-message"),
    path("audit", panel.audit_log, name="panel-audit"),
]
