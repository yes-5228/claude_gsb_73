"""Pagination helpers used by every list endpoint."""
from flask import current_app, request


def page_params():
    config = current_app.config
    try:
        page = int(request.args.get("page", 1))
    except (TypeError, ValueError):
        page = 1
    try:
        page_size = int(request.args.get("page_size", config["DEFAULT_PAGE_SIZE"]))
    except (TypeError, ValueError):
        page_size = config["DEFAULT_PAGE_SIZE"]
    page = max(page, 1)
    page_size = min(max(page_size, 1), config["MAX_PAGE_SIZE"])
    return page, page_size


def paginate_query(query, serializer, page=None, page_size=None):
    page, page_size = (page, page_size) if page and page_size else page_params()
    total = query.count()
    rows = query.limit(page_size).offset((page - 1) * page_size).all()
    items = [serializer(row) for row in rows]
    return {
        "items": items,
        "total": total,
        "page": page,
        "page_size": page_size,
        "pages": (total + page_size - 1) // page_size if page_size else 0,
    }


def arg_bool(name, default=None):
    raw = request.args.get(name)
    if raw is None or raw == "":
        return default
    return str(raw).strip().lower() in {"1", "true", "yes", "on"}


def arg_int(name, default=None):
    raw = request.args.get(name)
    if raw in (None, ""):
        return default
    try:
        return int(raw)
    except (TypeError, ValueError):
        return default
