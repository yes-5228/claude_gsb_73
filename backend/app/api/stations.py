"""监测点台账 API."""
from flask import Blueprint, request

from ..domain.constants import STATION_STATUS_LABELS, STATION_TYPE_LABELS
from ..services import station_service
from ..utils.pagination import paginate_query
from ..utils.validation import Validator
from .helpers import json_payload

bp = Blueprint("stations", __name__)


def _validate_station(data, partial=False):
    validator = Validator(data)
    validator.text("code", "监测点编码", required=not partial, max_length=32)
    validator.text("name", "监测点名称", required=not partial, max_length=120)
    validator.text("area", "所属区域", required=not partial, max_length=64)
    validator.text("address", "详细地址", required=False, max_length=200)
    validator.choice(
        "station_type", "监测点类型",
        choices=tuple(STATION_TYPE_LABELS.keys()),
        required=False,
        default="ambient",
    )
    validator.choice(
        "status", "运行状态",
        choices=tuple(STATION_STATUS_LABELS.keys()),
        required=False,
        default="active",
    )
    validator.number("longitude", "经度", minimum=-180, maximum=180)
    validator.number("latitude", "纬度", minimum=-90, maximum=90)
    validator.date_field("installed_at", "投运日期")
    validator.text("remark", "备注", required=False, max_length=1000)
    cleaned = validator.raise_if_invalid("监测点信息不合法")

    if partial:
        # 未提交的字段保持原值; 显式提交空值表示清空该字段
        cleaned = {key: value for key, value in cleaned.items() if key in data}
    return cleaned


@bp.get("/", strict_slashes=False)
def list_stations():
    query = station_service.station_query(request.args)
    result = paginate_query(query, lambda station: station.to_dict())
    stats = station_service.stats_map([item["id"] for item in result["items"]])
    for item in result["items"]:
        item["stats"] = stats.get(item["id"], {})
    result["areas"] = station_service.area_list()
    return result


@bp.post("/", strict_slashes=False)
def create_station():
    payload = _validate_station(json_payload())
    station = station_service.create_station(payload)
    return station.to_dict(), 201


@bp.get("/options")
def station_options():
    return {"items": station_service.option_list(), "areas": station_service.area_list()}


@bp.get("/summary")
def station_summary():
    return station_service.metadata_summary()


@bp.get("/<int:station_id>")
def get_station(station_id):
    station = station_service.get_station(station_id)
    payload = station.to_dict(include_stats=True, stats=station_service.detail_stats(station))
    return payload


@bp.put("/<int:station_id>")
def update_station(station_id):
    station = station_service.get_station(station_id)
    payload = _validate_station(json_payload(), partial=True)
    return station_service.update_station(station, payload).to_dict()


@bp.delete("/<int:station_id>")
def delete_station(station_id):
    station = station_service.get_station(station_id)
    removed = station_service.delete_station(station)
    return {"id": station_id, "removed": removed}
