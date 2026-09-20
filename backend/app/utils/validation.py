"""Small declarative request payload validator (no third-party dependency)."""
from datetime import date, datetime

from ..errors import ValidationError

DATETIME_FORMATS = (
    "%Y-%m-%dT%H:%M:%S",
    "%Y-%m-%dT%H:%M",
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%d %H:%M",
)
DATE_FORMATS = ("%Y-%m-%d", "%Y/%m/%d")


def parse_datetime(value, field="时间"):
    if isinstance(value, datetime):
        return value
    text = str(value or "").strip().replace("Z", "")
    if not text:
        raise ValidationError("%s不能为空" % field, fields={field: "required"})
    for fmt in DATETIME_FORMATS:
        try:
            return datetime.strptime(text, fmt)
        except ValueError:
            continue
    raise ValidationError(
        "%s格式应为 YYYY-MM-DD HH:MM" % field, fields={field: "invalid_datetime"}
    )


def parse_date(value, field="日期"):
    if value in (None, ""):
        return None
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    text = str(value).strip()
    for fmt in DATE_FORMATS:
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    raise ValidationError("%s格式应为 YYYY-MM-DD" % field, fields={field: "invalid_date"})


class Validator:
    """Collects field level errors and returns a cleaned payload."""

    def __init__(self, data):
        self.data = data if isinstance(data, dict) else {}
        self.errors = {}
        self.cleaned = {}

    # ---- primitives -------------------------------------------------
    def _missing(self, field, label, required):
        if required:
            self.errors[field] = "%s不能为空" % label
        return None

    def text(self, field, label, required=True, max_length=None, default=None):
        raw = self.data.get(field)
        if raw is None or str(raw).strip() == "":
            value = self._missing(field, label, required)
            if value is None:
                self.cleaned[field] = default if not required else None
            return value
        value = str(raw).strip()
        if max_length and len(value) > max_length:
            self.errors[field] = "%s长度不能超过 %d 个字符" % (label, max_length)
            return None
        self.cleaned[field] = value
        return value

    def number(self, field, label, required=False, minimum=None, maximum=None, default=None):
        raw = self.data.get(field)
        if raw is None or str(raw).strip() == "":
            if required:
                self.errors[field] = "%s不能为空" % label
            self.cleaned[field] = default
            return None
        try:
            value = float(raw)
        except (TypeError, ValueError):
            self.errors[field] = "%s必须是数字" % label
            return None
        if minimum is not None and value < minimum:
            self.errors[field] = "%s不能小于 %s" % (label, minimum)
            return None
        if maximum is not None and value > maximum:
            self.errors[field] = "%s不能大于 %s" % (label, maximum)
            return None
        self.cleaned[field] = value
        return value

    def choice(self, field, label, choices, required=True, default=None):
        raw = self.data.get(field)
        if raw is None or str(raw).strip() == "":
            if required:
                self.errors[field] = "%s不能为空" % label
                return None
            self.cleaned[field] = default
            return None
        value = str(raw).strip()
        if value not in choices:
            self.errors[field] = "%s取值不合法, 可选: %s" % (label, ", ".join(choices))
            return None
        self.cleaned[field] = value
        return value

    def datetime_field(self, field, label, required=True):
        raw = self.data.get(field)
        if raw in (None, ""):
            if required:
                self.errors[field] = "%s不能为空" % label
            return None
        try:
            value = parse_datetime(raw, label)
        except ValidationError as exc:
            self.errors[field] = exc.message
            return None
        self.cleaned[field] = value
        return value

    def date_field(self, field, label, required=False):
        raw = self.data.get(field)
        if raw in (None, ""):
            if required:
                self.errors[field] = "%s不能为空" % label
            self.cleaned[field] = None
            return None
        try:
            value = parse_date(raw, label)
        except ValidationError as exc:
            self.errors[field] = exc.message
            return None
        self.cleaned[field] = value
        return value

    def boolean(self, field, default=False):
        raw = self.data.get(field, default)
        if isinstance(raw, bool):
            value = raw
        else:
            value = str(raw).strip().lower() in {"1", "true", "yes", "on"}
        self.cleaned[field] = value
        return value

    # ---- finish -----------------------------------------------------
    def raise_if_invalid(self, message="请求参数不合法"):
        if self.errors:
            raise ValidationError(message, fields=self.errors)
        return self.cleaned

    def error_count(self):
        return len(self.errors)

    def fail(self, field, message):
        self.errors[field] = message
