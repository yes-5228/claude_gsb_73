"""超标记录标注 API."""
from flask import Blueprint, current_app, request

from ..domain.constants import EXCEEDANCE_LEVEL_LABELS, EXCEEDANCE_STATUS_LABELS, PERIOD_LABELS
from ..services import exceedance_service
from ..utils.pagination import paginate_query
from ..utils.validation import Validator
from .helpers import json_payload, list_payload

bp = Blueprint("exceedances", __name__)


@bp.get("/", strict_slashes=False)
def list_exceedances():
    """超标记录列表: 支持状态/等级/因子/站点/时间过滤, 并附带筛选后的统计."""
    query = exceedance_service.exceedance_query(request.args)
    result = paginate_query(query, lambda row: row.to_dict())
    result["summary"] = exceedance_service.summary(request.args)
    return result


@bp.get("/summary")
def exceedance_summary():
    return exceedance_service.summary(request.args)


@bp.get("/options")
def exceedance_options():
    return {
        "levels": [
            {"value": key, "label": label}
            for key, label in EXCEEDANCE_LEVEL_LABELS.items()
        ],
        "statuses": [
            {"value": key, "label": label}
            for key, label in EXCEEDANCE_STATUS_LABELS.items()
        ],
        "periods": [{"value": key, "label": label} for key, label in PERIOD_LABELS.items()],
    }


@bp.get("/export")
def export_exceedances():
    from ..utils.csv_export import csv_response

    rows = exceedance_service.exceedance_query(request.args).limit(
        current_app.config["MAX_EXPORT_ROWS"]
    ).all()
    columns = [
        ("站点编码", lambda row: row.station.code if row.station else ""),
        ("站点名称", lambda row: row.station.name if row.station else ""),
        ("监测因子", "pollutant"),
        ("监测值", "value"),
        ("限值", "limit_value"),
        ("超标倍数", "exceed_ratio"),
        ("超标等级", lambda row: EXCEEDANCE_LEVEL_LABELS.get(row.level, row.level)),
        ("标注状态", lambda row: EXCEEDANCE_STATUS_LABELS.get(row.status, row.status)),
        ("监测时间", lambda row: row.measured_at.strftime("%Y-%m-%d %H:%M")),
        ("标注说明", "note"),
        ("标注人", "annotator"),
        ("标注时间", lambda row: row.annotated_at.strftime("%Y-%m-%d %H:%M")
            if row.annotated_at else ""),
    ]
    return csv_response(rows, columns, "exceedance_records")


@bp.get("/<int:exceedance_id>")
def get_exceedance(exceedance_id):
    exceedance = exceedance_service.get_exceedance(exceedance_id)
    return exceedance.to_dict(include_relations=True)


@bp.patch("/<int:exceedance_id>")
def annotate_exceedance(exceedance_id):
    """单条标注: 确认/忽略/调整等级并填写说明."""
    exceedance = exceedance_service.get_exceedance(exceedance_id)
    data = json_payload()
    validator = Validator(data)
    status = validator.choice(
        "status", "标注状态", choices=tuple(EXCEEDANCE_STATUS_LABELS.keys()), required=False
    )
    level = validator.choice(
        "level", "超标等级", choices=tuple(EXCEEDANCE_LEVEL_LABELS.keys()), required=False
    )
    note = validator.text("note", "标注说明", required=False, max_length=1000)
    annotator = validator.text("annotator", "标注人", required=False, max_length=64)
    validator.raise_if_invalid("标注信息不合法")

    updated = exceedance_service.annotate(
        exceedance, status=status, note=note, annotator=annotator, level=level
    )
    return updated.to_dict()


@bp.post("/annotations")
def batch_annotate():
    """批量标注: 工作台勾选多条后一次性确认或忽略."""
    data = json_payload()
    validator = Validator(data)
    status = validator.choice(
        "status", "标注状态", choices=tuple(EXCEEDANCE_STATUS_LABELS.keys()), required=True
    )
    level = validator.choice(
        "level", "超标等级", choices=tuple(EXCEEDANCE_LEVEL_LABELS.keys()), required=False
    )
    note = validator.text("note", "标注说明", required=False, max_length=1000)
    annotator = validator.text("annotator", "标注人", required=False, max_length=64)
    validator.raise_if_invalid("标注信息不合法")

    ids = list_payload("ids", data)
    return exceedance_service.annotate_batch(ids, status, note=note, annotator=annotator, level=level)
