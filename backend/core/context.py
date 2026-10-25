def panel_section(request):
    """Which top-level panel section the page belongs to (for the nav)."""
    name = getattr(request.resolver_match, "url_name", "") or ""
    for prefix, section in (
        ("panel-user", "users"),
        ("panel-group", "groups"),
        ("panel-audit", "audit"),
        ("panel-situation", "situation"),
    ):
        if name.startswith(prefix):
            return {"section": section}
    return {}
