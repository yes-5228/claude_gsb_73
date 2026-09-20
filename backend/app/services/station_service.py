"""监测点台账业务逻辑."""
from sqlalchemy import cast, func, or_

from ..domain.constants import STATION_STATUS_LABELS, STATION_TYPE_LABELS
from ..errors import ConflictError, NotFoundError
from ..extensions import db
from ..models import Exceedance, Measurement, Station


def _split(value):
    if not value:
        return []
    return [item.strip() for item in str(value).split(",") if item.strip()]


def station_query(args):
    query = Station.query
    keyword = (args.get("keyword") or "").strip()
    if keyword:
        like = "%" + keyword + "%"
        query = query.filter(
            or_(Station.name.like(like), Station.code.like(like), Station.address.like(like))
        )
    area = (args.get("area") or "").strip()
    if area:
        query = query.filter(Station.area.in_(_split(area)))
    statuses = _split(args.get("status"))
    if statuses:
        query = query.filter(Station.status.in_(statuses))
    types = _split(args.get("station_type"))
    if types:
        query = query.filter(Station.station_type.in_(types))

    sort_field = {
        "code": Station.code,
        "name": Station.name,
        "area": Station.area,
        "created_at": Station.created_at,
    }.get(args.get("sort"), Station.code)
    direction = sort_field.desc() if (args.get("order") or "asc") == "desc" else sort_field.asc()
    return query.order_by(direction)


def get_station(station_id):
    station = db.session.get(Station, station_id)
    if station is None:
        raise NotFoundError("监测点不存在: id=%s" % station_id)
    return station


def create_station(data):
    code = data["code"]
    if Station.query.filter(func.lower(Station.code) == code.lower()).first():
        raise ConflictError("监测点编码 %s 已存在" % code)
    station = Station(**data)
    db.session.add(station)
    db.session.commit()
    return station


def update_station(station, data):
    code = data.get("code")
    if code and code.lower() != station.code.lower():
        exists = Station.query.filter(func.lower(Station.code) == code.lower()).first()
        if exists and exists.id != station.id:
            raise ConflictError("监测点编码 %s 已存在" % code)
    for field, value in data.items():
        setattr(station, field, value)
    db.session.commit()
    return station


def delete_station(station):
    """Remove a station together with its measurements and exceedance records."""
    measurement_count = Measurement.query.filter_by(station_id=station.id).count()
    exceedance_count = Exceedance.query.filter_by(station_id=station.id).count()
    db.session.delete(station)
    db.session.commit()
    return {"measurements_removed": measurement_count, "exceedances_removed": exceedance_count}


def stats_map(station_ids):
    """Aggregated counters for a page of stations."""
    if not station_ids:
        return {}
    measurements = dict(
        db.session.query(Measurement.station_id, func.count(Measurement.id))
        .filter(Measurement.station_id.in_(station_ids))
        .group_by(Measurement.station_id)
        .all()
    )
    exceeded = dict(
        db.session.query(Measurement.station_id, func.count(Measurement.id))
        .filter(Measurement.station_id.in_(station_ids), Measurement.is_exceeded.is_(True))
        .group_by(Measurement.station_id)
        .all()
    )
    pending = dict(
        db.session.query(Exceedance.station_id, func.count(Exceedance.id))
        .filter(Exceedance.station_id.in_(station_ids), Exceedance.status == "pending")
        .group_by(Exceedance.station_id)
        .all()
    )
    last_seen = dict(
        db.session.query(Measurement.station_id, func.max(Measurement.measured_at))
        .filter(Measurement.station_id.in_(station_ids))
        .group_by(Measurement.station_id)
        .all()
    )
    from ..models.base import iso

    return {
        station_id: {
            "measurement_count": int(measurements.get(station_id, 0)),
            "exceeded_count": int(exceeded.get(station_id, 0)),
            "pending_count": int(pending.get(station_id, 0)),
            "last_measured_at": iso(last_seen.get(station_id)),
        }
        for station_id in station_ids
    }


def detail_stats(station):
    """Per-pollutant counters for the station detail drawer."""
    rows = (
        db.session.query(
            Measurement.pollutant,
            func.count(Measurement.id),
            func.sum(cast(Measurement.is_exceeded, db.Integer)),
            func.avg(Measurement.value),
            func.max(Measurement.value),
        )
        .filter(Measurement.station_id == station.id)
        .group_by(Measurement.pollutant)
        .all()
    )
    pollutants = [
        {
            "pollutant": pollutant,
            "count": int(count or 0),
            "exceeded_count": int(exceeded or 0),
            "avg_value": round(float(avg), 2) if avg is not None else None,
            "max_value": float(max_value) if max_value is not None else None,
        }
        for pollutant, count, exceeded, avg, max_value in rows
    ]
    summary = stats_map([station.id]).get(station.id, {})
    summary["pollutants"] = sorted(pollutants, key=lambda item: item["pollutant"])
    return summary


def option_list():
    stations = Station.query.order_by(Station.area.asc(), Station.code.asc()).all()
    return [station.to_option() for station in stations]


def area_list():
    rows = db.session.query(Station.area).distinct().order_by(Station.area.asc()).all()
    return [row[0] for row in rows if row[0]]


def metadata_summary():
    total = Station.query.count()
    by_status = [
        {"key": key, "label": label, "count": Station.query.filter_by(status=key).count()}
        for key, label in STATION_STATUS_LABELS.items()
    ]
    by_type = [
        {"key": key, "label": label, "count": Station.query.filter_by(station_type=key).count()}
        for key, label in STATION_TYPE_LABELS.items()
    ]
    return {"total": total, "by_status": by_status, "by_type": by_type}
