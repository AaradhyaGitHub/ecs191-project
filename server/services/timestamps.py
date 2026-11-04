"""Timestamps as API.md writes them (ISO 8601 in UTC). Shared by every service.

The app sends `2026-11-02T17:02:00Z`; fractional seconds and `+00:00` are accepted too.
The server sends `2026-11-02T17:02:00Z` (with fractions only when the value has them).
"""
from __future__ import annotations

from datetime import datetime, timezone


def iso(value) -> str | None:
    """A UTC timestamp as API.md writes it: 2026-11-01T18:10:00Z. Non-datetimes pass through."""
    if not isinstance(value, datetime):
        return value
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse(text) -> datetime | None:
    """A timezone-aware UTC datetime from an ISO 8601 string, or None when it isn't one.

    A timestamp without an offset is taken as UTC (API.md: timestamps are UTC).
    """
    if not isinstance(text, str) or not text:
        return None
    try:
        value = datetime.fromisoformat(text.replace("Z", "+00:00").replace("z", "+00:00"))
    except ValueError:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
