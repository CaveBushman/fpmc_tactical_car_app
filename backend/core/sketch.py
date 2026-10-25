"""Schematic map of member positions for the situation page.

Drawn as inline SVG on the server: no tiles, no JavaScript, so it works
offline and under the panel's strict CSP. Positions are projected
equirectangularly around their centre, which is accurate enough for the
few kilometres a team spreads over.
"""

import math

WIDTH, HEIGHT, PADDING = 640, 360, 48
EARTH_RADIUS_M = 6_371_000
# Smallest area shown, so one member or a tight group is not blown up.
MIN_SPAN_M = 500
NICE_STEPS_M = (
    10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10_000, 20_000, 50_000,
    100_000, 200_000, 500_000,
)


def _scale_bar(metres_per_px):
    """Largest nice distance whose bar fits in a quarter of the width."""
    limit = WIDTH / 4 * metres_per_px
    metres = NICE_STEPS_M[0]
    for step in NICE_STEPS_M:
        if step <= limit:
            metres = step
    label = f"{metres // 1000} km" if metres >= 1000 else f"{metres} m"
    return {"px": f"{metres / metres_per_px:.1f}", "label": label}


def build(rows):
    """Plot data for ``rows`` from the situation view, or None if empty."""
    if not rows:
        return None
    lat0 = sum(r["position"].latitude for r in rows) / len(rows)
    lon0 = sum(r["position"].longitude for r in rows) / len(rows)
    cos_lat = math.cos(math.radians(lat0))
    local = []
    for row in rows:
        position = row["position"]
        east = math.radians(position.longitude - lon0) * cos_lat * EARTH_RADIUS_M
        north = math.radians(position.latitude - lat0) * EARTH_RADIUS_M
        local.append((row, east, north))
    min_e = min(e for _, e, _ in local)
    max_e = max(e for _, e, _ in local)
    min_n = min(n for _, _, n in local)
    max_n = max(n for _, _, n in local)
    span_e = max(max_e - min_e, MIN_SPAN_M)
    span_n = max(max_n - min_n, MIN_SPAN_M)
    metres_per_px = max(
        span_e / (WIDTH - 2 * PADDING), span_n / (HEIGHT - 2 * PADDING)
    )
    mid_e, mid_n = (min_e + max_e) / 2, (min_n + max_n) / 2
    points = []
    for row, east, north in local:
        x = WIDTH / 2 + (east - mid_e) / metres_per_px
        y = HEIGHT / 2 - (north - mid_n) / metres_per_px
        member = row["member"]
        points.append({
            # Strings, so the Czech locale cannot turn the dot into a comma.
            "x": f"{x:.1f}",
            "y": f"{y:.1f}",
            "label": member.display_name or member.username,
            # Labels near the right edge go to the left of the dot.
            "anchor": "end" if x > WIDTH - 160 else "start",
            "dx": -11 if x > WIDTH - 160 else 11,
            "urgent": row["urgent"],
            "stale": row["stale"],
        })
    # Urgent members are drawn last so nothing covers them.
    points.sort(key=lambda p: (p["urgent"], not p["stale"]))
    return {
        "width": WIDTH,
        "height": HEIGHT,
        "points": points,
        "scale": _scale_bar(metres_per_px),
    }
