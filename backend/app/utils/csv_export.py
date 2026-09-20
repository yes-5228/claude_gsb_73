"""CSV export helper (UTF-8 BOM so Excel opens Chinese text correctly)."""
import csv
import io
from datetime import datetime

from flask import Response


def csv_response(rows, columns, filename_prefix):
    """columns: list of (header, key-or-callable)."""
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow([header for header, _ in columns])
    for row in rows:
        writer.writerow([_resolve(row, accessor) for _, accessor in columns])

    filename = "%s_%s.csv" % (filename_prefix, datetime.now().strftime("%Y%m%d%H%M%S"))
    payload = "\ufeff" + buffer.getvalue()
    return Response(
        payload,
        mimetype="text/csv; charset=utf-8",
        headers={"Content-Disposition": "attachment; filename=%s" % filename},
    )


def _resolve(row, accessor):
    """Read a column from a model instance, a mapping or a callable."""
    value = accessor(row) if callable(accessor) else getattr(row, accessor, None)
    return "" if value is None else value
