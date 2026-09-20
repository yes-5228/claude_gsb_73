"""超标记录标注接口测试."""
from app.models import Exceedance


def _make_exceedances(client, station, entry_payload, measured_at="2026-09-01 10:00"):
    return client.post(
        "/api/measurements/entries",
        json=entry_payload(
            station.id,
            measured_at=measured_at,
            entries=[
                {"pollutant": "SO2", "value": 600.0},
                {"pollutant": "NO2", "value": 300.0},
                {"pollutant": "PM25", "value": 40.0},
            ],
        ),
    ).get_json()


def test_exceedance_records_are_created_automatically(client, station, entry_payload):
    body = _make_exceedances(client, station, entry_payload)
    assert body["summary"]["exceeded_count"] == 2

    listed = client.get("/api/exceedances").get_json()
    assert listed["total"] == 2
    levels = {item["pollutant"]: item["level"] for item in listed["items"]}
    assert levels == {"SO2": "light", "NO2": "moderate"}
    assert listed["summary"]["pending"] == 2
    assert listed["summary"]["by_status"][0]["key"] == "pending"


def test_annotation_requires_note_when_not_pending(client, station, entry_payload):
    _make_exceedances(client, station, entry_payload)
    exceedance_id = Exceedance.query.first().id

    response = client.patch("/api/exceedances/%d" % exceedance_id, json={"status": "confirmed"})
    assert response.status_code == 422
    assert response.get_json()["error"]["fields"]["note"] == "required"


def test_single_annotation_persists_note_and_annotator(client, station, entry_payload):
    _make_exceedances(client, station, entry_payload)
    exceedance_id = Exceedance.query.order_by(Exceedance.id.asc()).first().id

    response = client.patch(
        "/api/exceedances/%d" % exceedance_id,
        json={
            "status": "confirmed",
            "level": "severe",
            "note": "复核确认超标, 已通知现场核查",
            "annotator": "王敏",
        },
    )
    assert response.status_code == 200
    body = response.get_json()
    assert body["status"] == "confirmed"
    assert body["status_label"] == "已确认"
    assert body["level"] == "severe"
    assert body["note"] == "复核确认超标, 已通知现场核查"
    assert body["annotator"] == "王敏"
    assert body["annotated_at"] is not None


def test_batch_annotation_updates_selected_records(client, station, entry_payload):
    _make_exceedances(client, station, entry_payload)
    ids = [item.id for item in Exceedance.query.all()]

    response = client.post(
        "/api/exceedances/annotations",
        json={"ids": ids, "status": "ignored", "note": "仪器校准异常值", "annotator": "李静"},
    )
    assert response.status_code == 200
    body = response.get_json()
    assert body["updated"] == 2
    assert body["missing"] == []
    assert Exceedance.query.filter_by(status="ignored").count() == 2

    missing = client.post(
        "/api/exceedances/annotations",
        json={"ids": [9999], "status": "confirmed", "note": "不存在"},
    )
    assert missing.get_json()["missing"] == [9999]


def test_batch_annotation_without_note_is_rejected(client, station, entry_payload):
    _make_exceedances(client, station, entry_payload)
    ids = [item.id for item in Exceedance.query.all()]
    response = client.post(
        "/api/exceedances/annotations", json={"ids": ids, "status": "confirmed"}
    )
    assert response.status_code == 422


def test_exceedance_filters_and_summary(client, station, entry_payload):
    _make_exceedances(client, station, entry_payload)
    only_so2 = client.get("/api/exceedances?pollutant=SO2&level=light").get_json()
    assert only_so2["total"] == 1
    assert only_so2["items"][0]["pollutant"] == "SO2"
    assert only_so2["summary"]["total"] == 1

    annotated = client.get("/api/exceedances?annotated=false").get_json()
    assert annotated["total"] == 2

    detail = client.get("/api/exceedances/%d" % only_so2["items"][0]["id"]).get_json()
    assert detail["measurement"]["station"]["code"] == "TEST-001"


def test_exceedance_options_and_export(client, station, entry_payload):
    _make_exceedances(client, station, entry_payload)
    options = client.get("/api/exceedances/options").get_json()
    assert {item["value"] for item in options["statuses"]} == {"pending", "confirmed", "ignored"}

    csv_body = client.get("/api/exceedances/export").get_data(as_text=True)
    assert csv_body.startswith("\ufeff站点编码")
    assert "SO₂" not in csv_body  # 导出使用标准因子代码
    assert "SO2" in csv_body
