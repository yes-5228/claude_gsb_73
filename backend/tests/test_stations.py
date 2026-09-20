"""监测点台账接口测试."""
from app.models import Measurement, Station


def test_create_station(client):
    response = client.post(
        "/api/stations/",
        json={
            "code": "SZ-AQ-100",
            "name": "新增监测点",
            "area": "南山区",
            "station_type": "traffic",
            "status": "active",
            "longitude": 113.9,
            "latitude": 22.5,
            "installed_at": "2024-03-01",
        },
    )
    assert response.status_code == 201
    body = response.get_json()
    assert body["code"] == "SZ-AQ-100"
    assert body["station_type_label"] == "道路交通"
    assert body["installed_at"] == "2024-03-01"


def test_create_station_requires_name_and_unique_code(client, station):
    invalid = client.post("/api/stations/", json={"code": "SZ-AQ-101", "area": "福田区"})
    assert invalid.status_code == 422
    assert "name" in invalid.get_json()["error"]["fields"]

    duplicated = client.post(
        "/api/stations/", json={"code": "TEST-001", "name": "重复编码", "area": "福田区"}
    )
    assert duplicated.status_code == 409


def test_list_stations_supports_keyword_and_pagination(client, station, second_station):
    response = client.get("/api/stations?keyword=工业")
    body = response.get_json()
    assert body["total"] == 1
    assert body["items"][0]["code"] == "TEST-002"

    paged = client.get("/api/stations?page=1&page_size=1").get_json()
    assert len(paged["items"]) == 1
    assert paged["pages"] == 2


def test_partial_update_keeps_untouched_fields(client, station):
    response = client.put(
        "/api/stations/%d" % station.id, json={"status": "maintenance", "remark": "设备检修"}
    )
    assert response.status_code == 200
    body = response.get_json()
    assert body["status"] == "maintenance"
    assert body["area"] == "测试区"
    assert body["address"] == "测试路 1 号"


def test_invalid_choice_is_rejected(client, station):
    response = client.put("/api/stations/%d" % station.id, json={"status": "unknown"})
    assert response.status_code == 422
    assert "status" in response.get_json()["error"]["fields"]


def test_station_detail_returns_pollutant_stats(client, station, entry_payload):
    client.post("/api/measurements/entries", json=entry_payload(station.id))
    body = client.get("/api/stations/%d" % station.id).get_json()
    assert body["stats"]["measurement_count"] == 3
    assert body["stats"]["exceeded_count"] == 1
    assert body["stats"]["pending_count"] == 1
    pollutants = {item["pollutant"] for item in body["stats"]["pollutants"]}
    assert pollutants == {"PM25", "SO2", "CO"}


def test_delete_station_removes_measurements_and_exceedances(client, app, station, entry_payload):
    client.post("/api/measurements/entries", json=entry_payload(station.id))
    assert Measurement.query.count() == 3

    response = client.delete("/api/stations/%d" % station.id)
    assert response.status_code == 200
    assert response.get_json()["removed"] == {"measurements_removed": 3, "exceedances_removed": 1}
    assert Station.query.count() == 0
    assert Measurement.query.count() == 0


def test_station_options_and_summary(client, station, second_station):
    options = client.get("/api/stations/options").get_json()
    assert len(options["items"]) == 2
    assert options["areas"] == ["工业园区", "测试区"]

    summary = client.get("/api/stations/summary").get_json()
    assert summary["total"] == 2
    assert {item["key"] for item in summary["by_status"]} == {"active", "maintenance", "offline"}


def test_missing_station_returns_404(client):
    response = client.get("/api/stations/999")
    assert response.status_code == 404
    assert response.get_json()["error"]["code"] == "NOT_FOUND"
