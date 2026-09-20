"""Shared helpers for the API layer."""
from flask import current_app, request
from sqlalchemy.exc import IntegrityError

from ..errors import ConflictError, ValidationError


def json_payload():
    data = request.get_json(silent=True)
    if data is None:
        raise ValidationError("请求体必须是合法的 JSON")
    if not isinstance(data, dict):
        raise ValidationError("请求体必须是 JSON 对象")
    return data


def list_payload(field, data):
    value = data.get(field)
    if not isinstance(value, list):
        raise ValidationError("字段 %s 必须是数组" % field, fields={field: "invalid"})
    if len(value) > current_app.config["MAX_BATCH_SIZE"]:
        raise ValidationError(
            "%s 一次最多提交 %d 条" % (field, current_app.config["MAX_BATCH_SIZE"]),
            fields={field: "too_many"},
        )
    return value


def commit_or_conflict(message="数据冲突, 请检查唯一性约束"):
    from ..extensions import db

    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        raise ConflictError(message)
