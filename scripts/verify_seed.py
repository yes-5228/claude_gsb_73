#!/usr/bin/env python3
"""质量门禁: 直接对演示数据库做一致性校验 (不经 HTTP).

用法:
    DATABASE_URL=... python verify_seed.py

校验内容:
  1. 数量基准: 8 监测点 / 1200 监测数据 / 52 超标记录, 状态分布 18/17/17;
  2. 唯一约束: 站点编码、(站点, 因子, 周期, 时刻) 不重复;
  3. 超标记录与监测数据一一对应, is_exceeded / exceed_ratio 自洽;
  4. 每条监测数据都有限值快照或合理地不参与小时判定 (PM2.5/PM10 小时值).
任何一项不满足即以非零码退出.
"""
import os
import sys

from sqlalchemy import and_, func, not_

from app import create_app
from app.extensions import db
from app.models import Exceedance, Measurement, Station

EXPECT = {"stations": 8, "measurements": 1200, "exceedances": 52,
          "pending": 18, "confirmed": 17, "ignored": 17}

failures = []


def check(name, condition, detail=""):
    print("  [%s] %s" % ("PASS" if condition else "FAIL", name) +
          ((" -- %s" % detail) if detail and not condition else ""))
    if not condition:
        failures.append("%s (%s)" % (name, detail))


def main():
    app = create_app(os.getenv("FLASK_ENV", "development"))
    with app.app_context():
        print("数据库: %s" % str(db.engine.url))

        stations = Station.query.count()
        measurements = Measurement.query.count()
        exceedances = Exceedance.query.count()
        check("监测点 %d 个" % EXPECT["stations"], stations == EXPECT["stations"], "实际 %d" % stations)
        check("监测数据 %d 条" % EXPECT["measurements"], measurements == EXPECT["measurements"],
              "实际 %d" % measurements)
        check("超标记录 %d 条" % EXPECT["exceedances"], exceedances == EXPECT["exceedances"],
              "实际 %d" % exceedances)

        rows = dict(db.session.query(Exceedance.status, func.count())
                    .group_by(Exceedance.status).all())
        for key in ("pending", "confirmed", "ignored"):
            check("超标状态 %s == %d" % (key, EXPECT[key]),
                  rows.get(key, 0) == EXPECT[key], "实际 %r" % rows.get(key))

        # 唯一编码
        dup_codes = [r[0] for r in db.session.query(Station.code)
                     .group_by(Station.code).having(func.count() > 1).all()]
        check("站点编码唯一", not dup_codes, "重复: %s" % dup_codes)

        # 业务唯一键 (station_id, pollutant, period, measured_at)
        dup_key = (db.session.query(
                        Measurement.station_id, Measurement.pollutant,
                        Measurement.period, Measurement.measured_at)
                   .group_by(Measurement.station_id, Measurement.pollutant,
                             Measurement.period, Measurement.measured_at)
                   .having(func.count() > 1).limit(5).all())
        check("监测数据业务唯一键无重复", not dup_key, "样例: %s" % dup_key)

        # 超标记录与 is_exceeded 数据一一对应
        flagged = Measurement.query.filter_by(is_exceeded=True).count()
        check("超标记录数 == is_exceeded=True 数据数", flagged == exceedances,
              "is_exceeded=True 为 %d" % flagged)
        orphan = (db.session.query(Exceedance.id)
                  .outerjoin(Measurement, Exceedance.measurement_id == Measurement.id)
                  .filter(Measurement.id.is_(None)).count())
        check("超标记录均有关联监测数据", orphan == 0, "孤儿记录 %d 条" % orphan)
        mismatch = (db.session.query(func.count())
                    .select_from(Exceedance)
                    .join(Measurement, Exceedance.measurement_id == Measurement.id)
                    .filter(Measurement.is_exceeded.is_(False)).scalar())
        check("无超标记录挂在非超标数据上", mismatch == 0, "异常 %d 条" % mismatch)

        # 超标倍数必须 > 1; 非超标数据不应记录超标
        bad_ratio = Measurement.query.filter(
            Measurement.is_exceeded.is_(True), Measurement.exceed_ratio <= 1.0).count()
        check("超标数据 exceed_ratio 全部 > 1", bad_ratio == 0, "异常 %d 条" % bad_ratio)

        # PM2.5 / PM10 小时值不参与超标判定, 其余小时值与日均值均应有限值快照
        hourly_particulate = Measurement.query.filter(
            Measurement.period == "hourly",
            Measurement.pollutant.in_(["PM25", "PM10"])).count()
        check("PM2.5/PM10 小时值全部未判超标",
              Measurement.query.filter(
                  Measurement.period == "hourly",
                  Measurement.pollutant.in_(["PM25", "PM10"]),
                  Measurement.is_exceeded.is_(True)).count() == 0)
        snapshotted = Measurement.query.filter(
            Measurement.limit_value.is_(None),
            not_(and_(Measurement.period == "hourly",
                      Measurement.pollutant.in_(["PM25", "PM10"])))).count()
        check("参与判定的数据均有限值快照", snapshotted == 0, "缺快照 %d 条" % snapshotted)
        check("PM2.5/PM10 小时值样本数 > 0 (覆盖不判定分支)", hourly_particulate > 0,
              "实际 %d" % hourly_particulate)

    print("")
    if failures:
        print("演示数据校验失败 %d 项:" % len(failures))
        for item in failures:
            print("  - %s" % item)
        return 1
    print("演示数据校验全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
