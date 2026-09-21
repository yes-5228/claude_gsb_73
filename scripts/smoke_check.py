#!/usr/bin/env python3
"""质量门禁冒烟检查: 在运行中的系统上验证关键页面与关键 API.

用法:
    python smoke_check.py <BASE_URL>

BASE_URL 可以直接指向后端 (如 http://127.0.0.1:15000), 也可以指向
带 nginx / vite 代理的前端入口 (如 http://127.0.0.1:18080):
脚本会自行判断入口类型, 并在前端入口上同时验证静态页、SPA 回退与 /api 代理.

仅使用 Python 标准库; 任何断言失败都以非零码退出并打印差异.
"""
import json
import sys
import urllib.error
import urllib.request

# 五个关键业务页面 (react-router 路由, 依赖 SPA fallback)
KEY_PAGES = ["/overview", "/stations", "/measurements", "/exceedances", "/query"]

# 演示数据的确定性基准 (seed 使用固定随机种子, 见 backend/app/seed.py)
EXPECT = {
    "stations": 8,
    "measurements": 1200,
    "exceedances": 52,
    "pending": 18,
    "confirmed": 17,
    "ignored": 17,
}

failures = []


def request(url, timeout=10):
    req = urllib.request.Request(url, headers={"Accept": "application/json,text/html"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read()
        ctype = resp.headers.get("Content-Type", "")
        return resp.status, ctype, body


def check(name, condition, detail=""):
    mark = "PASS" if condition else "FAIL"
    print("  [%s] %s%s" % (mark, name, (" -- " + detail) if (detail and not condition) else ""))
    if not condition:
        failures.append("%s: %s" % (name, detail))


def fetch_json(url):
    status, ctype, body = request(url)
    if status != 200:
        raise AssertionError("HTTP %s (期望 200)" % status)
    if "json" not in ctype:
        raise AssertionError("Content-Type=%s, 期望 application/json" % ctype)
    return json.loads(body.decode("utf-8"))


def run(base_url):
    base_url = base_url.rstrip("/")
    print("冒烟目标: %s" % base_url)

    # 1. 后端健康检查 (直连或经代理)
    print("[1/4] 健康检查 GET /api/meta/health")
    health = fetch_json(base_url + "/api/meta/health")
    check("status == ok", health.get("status") == "ok", "实际: %r" % health.get("status"))
    check("database == ok", health.get("database") == "ok", "实际: %r" % health.get("database"))

    # 2. 演示数据一致性: 概览聚合必须与 seed 基准完全一致
    print("[2/4] 演示数据校验 GET /api/meta/overview")
    overview = fetch_json(base_url + "/api/meta/overview")
    station_total = overview.get("stations", {}).get("total")
    measurement_total = overview.get("measurements", {}).get("total")
    exceeded_count = overview.get("measurements", {}).get("exceeded_count")
    check("监测点总数 == %d" % EXPECT["stations"], station_total == EXPECT["stations"],
          "实际: %r" % station_total)
    check("监测数据总数 == %d" % EXPECT["measurements"], measurement_total == EXPECT["measurements"],
          "实际: %r" % measurement_total)
    check("超标数据数 == %d" % EXPECT["exceedances"], exceeded_count == EXPECT["exceedances"],
          "实际: %r" % exceeded_count)

    by_status = {item["key"]: item["count"] for item in
                 overview.get("exceedances", {}).get("by_status", [])}
    for key in ("pending", "confirmed", "ignored"):
        check("超标记录 %s == %d" % (key, EXPECT[key]), by_status.get(key) == EXPECT[key],
              "实际: %r" % by_status.get(key))
    check("超标状态合计 == 52",
          sum(by_status.get(k, 0) for k in ("pending", "confirmed", "ignored")) == 52,
          "实际: %r" % by_status)
    check("近 7 日趋势非空", len(overview.get("trend", [])) > 0,
          "trend 长度: %d" % len(overview.get("trend", [])))

    # 3. 关键列表接口可正常返回分页数据
    print("[3/4] 关键列表接口")
    stations = fetch_json(base_url + "/api/stations?page=1&page_size=20")
    check("GET /api/stations 返回 8 条", stations.get("total") == 8 and len(stations.get("items", [])) == 8,
          "实际 total=%r items=%d" % (stations.get("total"), len(stations.get("items", []))))
    measurements = fetch_json(base_url + "/api/measurements?page=1&page_size=20")
    check("GET /api/measurements total == 1200", measurements.get("total") == 1200,
          "实际: %r" % measurements.get("total"))
    exceedances = fetch_json(base_url + "/api/exceedances?page=1&page_size=20")
    check("GET /api/exceedances total == 52", exceedances.get("total") == 52,
          "实际: %r" % exceedances.get("total"))

    # 4. 前端关键页面 (仅对前端入口执行; 直连后端时跳过)
    print("[4/4] 前端关键页面")
    try:
        status, ctype, body = request(base_url + "/overview")
    except urllib.error.HTTPError as exc:
        status, ctype, body = exc.code, exc.headers.get("Content-Type", ""), b""
    html = body.decode("utf-8", errors="replace")
    is_frontend = status == 200 and ("html" in ctype) and '<div id="root">' in html
    if not is_frontend:
        print("  [SKIP] 目标不是前端入口 (status=%s, content-type=%s), 跳过页面冒烟" % (status, ctype))
    else:
        check("GET /overview (SPA)", status == 200 and "空气监测点数据录入系统" in html,
              "HTTP %s, 未找到应用标题" % status)
        for path in KEY_PAGES:
            try:
                st, _, page_body = request(base_url + path)
                page = page_body.decode("utf-8", errors="replace")
                ok_page = (st == 200 and '<div id="root">' in page
                           and "空气监测点数据录入系统" in page)
            except urllib.error.HTTPError as exc:
                st, page, ok_page = exc.code, "", False
            check("GET %s (SPA fallback)" % path, ok_page, "HTTP %s" % st)
        try:
            st, _, root_body = request(base_url + "/")
            root = root_body.decode("utf-8", errors="replace")
            # 生产构建的入口 JS 带哈希文件名; dev server 下 /src/main.jsx 可直接取到
            asset_ok = st == 200 and ("/assets/index-" in root or "/src/main.jsx" in root)
        except urllib.error.HTTPError as exc:
            st, root, asset_ok = exc.code, "", False
        check("GET / 引用入口脚本", asset_ok, "HTTP %s" % st)

    print("")
    if failures:
        print("冒烟失败 %d 项:" % len(failures))
        for item in failures:
            print("  - %s" % item)
        return 1
    print("冒烟检查全部通过")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    try:
        sys.exit(run(sys.argv[1]))
    except (urllib.error.URLError, AssertionError, ValueError, KeyError) as exc:
        print("冒烟检查异常终止: %s" % exc, file=sys.stderr)
        sys.exit(1)
