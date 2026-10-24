def panel_section(request):
    """Which top-level panel section the page belongs to (for the nav)."""
    name = getattr(request.resolver_match, "url_name", "") or ""
    for section in ("user", "group", "audit"):
        if name.startswith(f"panel-{section}"):
            return {"section": section + ("s" if section != "audit" else "")}
    return {}
