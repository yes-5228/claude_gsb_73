"""Unified API error handling."""
from werkzeug.exceptions import HTTPException

from .extensions import db


class ApiError(Exception):
    """Business level error rendered as a JSON payload."""

    def __init__(self, message, status_code=400, code="BAD_REQUEST", fields=None):
        super().__init__(message)
        self.message = message
        self.status_code = status_code
        self.code = code
        self.fields = fields or {}

    def to_dict(self):
        payload = {"message": self.message, "code": self.code}
        if self.fields:
            payload["fields"] = self.fields
        return payload


class NotFoundError(ApiError):
    def __init__(self, message="资源不存在"):
        super().__init__(message, status_code=404, code="NOT_FOUND")


class ValidationError(ApiError):
    def __init__(self, message="请求参数不合法", fields=None):
        super().__init__(message, status_code=422, code="VALIDATION_ERROR", fields=fields)


class ConflictError(ApiError):
    def __init__(self, message="数据冲突"):
        super().__init__(message, status_code=409, code="CONFLICT")


def register_error_handlers(app):
    @app.errorhandler(ApiError)
    def _handle_api_error(error):
        return {"error": error.to_dict()}, error.status_code

    @app.errorhandler(HTTPException)
    def _handle_http_error(error):
        code = (error.name or "HTTP_ERROR").upper().replace(" ", "_")
        return {"error": {"message": error.description or error.name, "code": code}}, error.code

    @app.errorhandler(Exception)
    def _handle_unexpected(error):
        db.session.rollback()
        app.logger.exception("unexpected error: %s", error)
        return {"error": {"message": "服务器内部错误", "code": "INTERNAL_ERROR"}}, 500
