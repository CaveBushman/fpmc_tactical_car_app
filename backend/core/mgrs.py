"""Latitude/longitude to a 1 m MGRS reference ("33U VR 58556 48514"), the
same digits the app shows (WGS84, truncated like the app's mgrs_dart)."""

import math

_A = 6378137.0
_F = 1 / 298.257223563
_E2 = _F * (2 - _F)
_EP2 = _E2 / (1 - _E2)
_K0 = 0.9996
_BANDS = "CDEFGHJKLMNPQRSTUVWXX"
_SET_COLUMNS = ("ABCDEFGH", "JKLMNPQR", "STUVWXYZ")
_ROW_LETTERS = "ABCDEFGHJKLMNPQRSTUV"


def _zone(lat, lon):
    zone = int((lon + 180) // 6) + 1
    if 56 <= lat < 64 and 3 <= lon < 12:
        return 32  # Norway
    if 72 <= lat < 84 and lon >= 0:  # Svalbard
        if lon < 9:
            return 31
        if lon < 21:
            return 33
        if lon < 33:
            return 35
        if lon < 42:
            return 37
    return zone


def _utm(lat, lon, zone):
    phi = math.radians(lat)
    lam = math.radians(lon - ((zone - 1) * 6 - 180 + 3))
    n = _A / math.sqrt(1 - _E2 * math.sin(phi) ** 2)
    t = math.tan(phi) ** 2
    c = _EP2 * math.cos(phi) ** 2
    a = math.cos(phi) * lam
    m = _A * (
        (1 - _E2 / 4 - 3 * _E2**2 / 64 - 5 * _E2**3 / 256) * phi
        - (3 * _E2 / 8 + 3 * _E2**2 / 32 + 45 * _E2**3 / 1024) * math.sin(2 * phi)
        + (15 * _E2**2 / 256 + 45 * _E2**3 / 1024) * math.sin(4 * phi)
        - (35 * _E2**3 / 3072) * math.sin(6 * phi)
    )
    easting = _K0 * n * (
        a
        + (1 - t + c) * a**3 / 6
        + (5 - 18 * t + t**2 + 72 * c - 58 * _EP2) * a**5 / 120
    ) + 500000
    northing = _K0 * (
        m
        + n * math.tan(phi) * (
            a**2 / 2
            + (5 - t + 9 * c + 4 * c**2) * a**4 / 24
            + (61 - 58 * t + t**2 + 600 * c - 330 * _EP2) * a**6 / 720
        )
    )
    if lat < 0:
        northing += 10000000
    return easting, northing


def to_mgrs(lat, lon):
    """None outside the UTM area (polar regions use UPS, not supported)."""
    if not -80 <= lat < 84:
        return None
    zone = _zone(lat, lon)
    easting, northing = _utm(lat, lon, zone)
    band = _BANDS[int((lat + 80) // 8)]
    set_index = (zone - 1) % 3
    column = _SET_COLUMNS[set_index][int(easting // 100000) - 1]
    row_offset = 5 if zone % 2 == 0 else 0
    row = _ROW_LETTERS[(int(northing // 100000) + row_offset) % 20]
    e = int(easting) % 100000
    n = int(northing) % 100000
    return f"{zone}{band} {column}{row} {e:05d} {n:05d}"
