"""Shared model helpers."""
from datetime import datetime

from ..extensions import db


def iso(value):
    """Serialise a datetime as an ISO-8601 string with second precision."""
    return value.isoformat(timespec="seconds") if value else None


def iso_date(value):
    return value.isoformat() if value else None


class TimestampMixin:
    created_at = db.Column(db.DateTime, default=datetime.now, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.now, onupdate=datetime.now, nullable=False)
