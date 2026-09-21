#!/usr/bin/env python3
"""演示数据校验: 校验 seed 产出的规模、分布与关键完整性约束。

两种用法(均为门禁内部调用):

1. 本地 / 一次性容器, 直接对数据库做校验(强一致, 可检查约束):
     python verify_seed.py --app wsgi
   通过 DATABASE_URL 指定目标库。

2. 容器编排启动后, 通过 HTTP 接口校验(验证对外真实行为):
     python verify_seed.py --url http://localhost:5000

任何一项不满足即以非零码退出并打印具体差异。
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

# 与 README 承诺、seed 固定随机种子(rng=Random(20260914))的产出保持一致
EXPECT = {
    "stations": 8,
    "measurements": 1200,
    "exceedances": 52,
    "daily": 240,       # 8 站 × 5 天 × 6 因子
    "hourly": 960,      # 8 站 × 5 天 × 4 时刻 × 6 因子
    "pending": 18,
    "confirmed": 17,
    "ignored": 17,
}

failures = []


def check(name, actual, expected):
    if actual == expected:
        print(f"  [OK] {name}: {actual}")
    else:
        failures.append(f"{name}: 期望 {expected}, 实际 {actual}")
        print(f"  [FAIL] {name}: 期望 {expected}, 实际 {actual}")


def verify_db():
    import importlib

    app_module = os.environ.get("FLASK_APP", "wsgi")
    sys.path.insert(0, os.getcwd())
    module = importlib.import_module(app_module)  # wsgi/run 模块暴露 app 对象
    app = module.app

    from sqlalchemy import func

    from app.extensions import db
    from app.models import Exceedance, Measurement, Station

    with app.app_context():
        check("监测点数量", Station.query.count(), EXPECT["stations"])
        check("监测数据数量", Measurement.query.count(), EXPECT["measurements"])
        check("超标记录数量", Exceedance.query.count(), EXPECT["exceedances"])

        periods = dict(
            db.session.query(Measurement.period, func.count())
            .group_by(Measurement.period)
            .all()
        )
        check("日均值数据量", periods.get("daily", 0), EXPECT["daily"])
        check("小时值数据量", periods.get("hourly", 0), EXPECT["hourly"])

        statuses = dict(
            db.session.query(Exceedance.status, func.count())
            .group_by(Exceedance.status)
            .all()
        )
        check("待标注超标", statuses.get("pending", 0), EXPECT["pending"])
        check("已确认超标", statuses.get("confirmed", 0), EXPECT["confirmed"])
        check("已忽略超标", statuses.get("ignored", 0), EXPECT["ignored"])

        # 完整性约束: 每条超标记录必须对应一条被标记为超标的监测数据
        orphans = (
            db.session.query(Exceedance)
            .outerjoin(Measurement, Exceedance.measurement_id == Measurement.id)
            .filter(Measurement.id.is_(None))
            .count()
        )
        check("无孤立超标记录", orphans, 0)

        mismarked = (
            db.session.query(func.count())
            .select_from(Exceedance)
            .join(Measurement, Exceedance.measurement_id == Measurement.id)
            .filter(Measurement.is_exceeded.is_(False))
            .scalar()
        )
        check("超标记录与数据标记一致", mismarked, 0)

        # 唯一约束: (station_id, pollutant, period, measured_at) 不允许重复
        dup_keys = (
            db.session.query(
                Measurement.station_id,
                Measurement.pollutant,
                Measurement.period,
                Measurement.measured_at,
            )
            .group_by(
                Measurement.station_id,
                Measurement.pollutant,
                Measurement.period,
                Measurement.measured_at,
            )
            .having(func.count() > 1)
            .count()
        )
        check("业务唯一键无重复", dup_keys, 0)


def _get_json(base, path):
    url = base.rstrip("/") + path
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        if resp.status != 200:
            raise RuntimeError(f"{url} 返回 HTTP {resp.status}")
        return json.loads(resp.read().decode("utf-8"))


def verify_http(base):
    health = _get_json(base, "/api/meta/health")
    check("健康检查 status", health.get("status"), "ok")
    check("健康检查 database", health.get("database"), "ok")

    stations = _get_json(base, "/api/stations?page_size=1")
    check("监测点数量", stations.get("total"), EXPECT["stations"])

    measurements = _get_json(base, "/api/measurements?page_size=1")
    check("监测数据数量", measurements.get("total"), EXPECT["measurements"])

    exceedances = _get_json(base, "/api/exceedances?page_size=1")
    check("超标记录数量", exceedances.get("total"), EXPECT["exceedances"])

    for status, expected in (
        ("pending", EXPECT["pending"]),
        ("confirmed", EXPECT["confirmed"]),
        ("ignored", EXPECT["ignored"]),
    ):
        data = _get_json(base, f"/api/exceedances?page_size=1&status={status}")
        check(f"{status} 超标记录", data.get("total"), expected)

    daily = _get_json(base, "/api/measurements?page_size=1&period=daily")
    check("日均值数据量", daily.get("total"), EXPECT["daily"])
    hourly = _get_json(base, "/api/measurements?page_size=1&period=hourly")
    check("小时值数据量", hourly.get("total"), EXPECT["hourly"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", help="Flask 应用模块(如 wsgi), 走数据库直连校验")
    parser.add_argument("--url", help="后端基地址, 走 HTTP 接口校验")
    args = parser.parse_args()

    print("== 演示数据校验 ==")
    try:
        if args.url:
            verify_http(args.url)
        else:
            if args.app:
                os.environ["FLASK_APP"] = args.app
            verify_db()
    except (urllib.error.URLError, OSError, RuntimeError) as exc:
        print(f"[FAIL] 校验无法执行: {exc}")
        return 2

    if failures:
        print(f"\n演示数据校验失败: {len(failures)} 项不符合预期")
        return 1
    print("\n演示数据校验全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
