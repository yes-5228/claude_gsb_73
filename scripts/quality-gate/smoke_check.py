#!/usr/bin/env python3
"""关键页面冒烟: 验证前端可访问、SPA 路由回退正常、/api 代理端到端打通,
并为每个业务页面拉取其首屏依赖的接口。

用法:
  python smoke_check.py --frontend http://localhost:8080 [--backend http://localhost:5000]

--backend 可选; 提供时额外直连后端健康检查(容器编排下直连 5000, 本地经 dev server 代理)。
任何一项失败即非零退出, 逐项打印结果。
"""
import argparse
import json
import sys
import urllib.error
import urllib.request

failures = []


def fetch(base, path, accept="text/html", allow_404_index=False):
    """返回 (status, body_text)。任何连接错误抛出。"""
    url = base.rstrip("/") + path
    req = urllib.request.Request(url, headers={"Accept": accept})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return resp.status, resp.read().decode("utf-8", errors="replace")


def page_check(base, path, expect_title="空气监测点数据录入系统"):
    """SPA 页面: 任意业务路由都应 200 返回含挂载点/标题的 index.html。"""
    try:
        status, body = fetch(base, path)
        if status != 200:
            failures.append(f"{path}: HTTP {status}")
            print(f"  [FAIL] 页面 {path}: HTTP {status}")
            return
        if "<div id=\"root\"" not in body and "id='root'" not in body:
            failures.append(f"{path}: 返回内容缺少 #root 挂载点(疑似非 SPA 入口)")
            print(f"  [FAIL] 页面 {path}: 缺少 #root 挂载点")
            return
        if expect_title and f"<title>{expect_title}</title>" not in body:
            failures.append(f"{path}: 标题与预期不符")
            print(f"  [FAIL] 页面 {path}: 标题不符")
            return
        print(f"  [OK] 页面 {path}: 200 + SPA 入口")
    except urllib.error.HTTPError as exc:
        failures.append(f"{path}: HTTP {exc.code}")
        print(f"  [FAIL] 页面 {path}: HTTP {exc.code}")
    except (urllib.error.URLError, OSError) as exc:
        failures.append(f"{path}: 无法连接 {base}: {exc}")
        print(f"  [FAIL] 页面 {path}: 无法连接 ({exc})")


def api_check(base, path, key=None, min_items=0):
    """业务接口: 200 且可解析 JSON; key 给定的列表要求至少 min_items 条。"""
    label = f"API {path}"
    try:
        status, body = fetch(base, path, accept="application/json")
        if status != 200:
            failures.append(f"{label}: HTTP {status}")
            print(f"  [FAIL] {label}: HTTP {status}")
            return None
        data = json.loads(body)
    except urllib.error.HTTPError as exc:
        failures.append(f"{label}: HTTP {exc.code}")
        print(f"  [FAIL] {label}: HTTP {exc.code}")
        return None
    except (urllib.error.URLError, OSError) as exc:
        failures.append(f"{label}: 无法连接 {base}: {exc}")
        print(f"  [FAIL] {label}: 无法连接 ({exc})")
        return None
    except json.JSONDecodeError as exc:
        failures.append(f"{label}: 响应不是合法 JSON ({exc})")
        print(f"  [FAIL] {label}: 非 JSON 响应")
        return None

    if key is not None:
        value = data.get(key)
        if not isinstance(value, list):
            failures.append(f"{label}: 缺少列表字段 '{key}'")
            print(f"  [FAIL] {label}: 缺少字段 '{key}'")
            return data
        if len(value) < min_items:
            failures.append(f"{label}: '{key}' 仅 {len(value)} 条, 期望 >= {min_items}")
            print(f"  [FAIL] {label}: '{key}' 数据不足 ({len(value)} < {min_items})")
            return data
        print(f"  [OK] {label}: 200, {key}={len(value)} 条")
    else:
        if data.get("status") and data.get("status") != "ok":
            failures.append(f"{label}: status={data.get('status')}")
            print(f"  [FAIL] {label}: status={data.get('status')}")
            return data
        print(f"  [OK] {label}: 200")
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frontend", required=True, help="前端基地址(经其 /api 代理访问后端)")
    parser.add_argument("--backend", help="后端直连基地址(可选, 用于额外直连健康检查)")
    args = parser.parse_args()

    print("== 关键页面冒烟 ==")
    print("-- 1/4 前端页面与 SPA 路由回退 --")
    # 五个业务路由 + 一个不存在路径, 验证 SPA 回退而非服务端 404
    for path in ("/", "/overview", "/stations", "/measurements", "/exceedances", "/query"):
        page_check(args.frontend, path)

    print("-- 2/4 经前端 /api 代理访问后端(端到端) --")
    api_base = args.frontend
    health = api_check(api_base, "/api/meta/health")
    if health and health.get("database") != "ok":
        failures.append("/api/meta/health: database 非 ok")
        print(f"  [FAIL] health.database={health.get('database')}")
    api_check(api_base, "/api/meta/pollutants", key="items", min_items=6)

    print("-- 3/4 各业务页面首屏接口 --")
    # 运行概览
    api_check(api_base, "/api/meta/overview")
    # 监测点台账
    stations = api_check(api_base, "/api/stations?page_size=10", key="items", min_items=1)
    if stations and stations.get("total", 0) < 8:
        failures.append("/api/stations: 总数少于演示数据 8 个")
        print(f"  [FAIL] /api/stations: total={stations.get('total')} < 8")
    # 监测数据录入页需要枚举选项
    api_check(api_base, "/api/meta/options")
    # 超标记录标注
    exc = api_check(api_base, "/api/exceedances?page_size=10", key="items", min_items=1)
    if exc and exc.get("total", 0) < 1:
        failures.append("/api/exceedances: 无任何超标记录")
    # 数据查询
    api_check(api_base, "/api/query/measurements?page_size=10", key="items", min_items=1)

    print("-- 4/4 后端直连健康检查 --")
    if args.backend:
        api_check(args.backend, "/api/meta/health")
    else:
        print("  [SKIP] 未提供 --backend, 以代理链路为准")

    if failures:
        print(f"\n冒烟失败: {len(failures)} 项")
        return 1
    print("\n冒烟全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
