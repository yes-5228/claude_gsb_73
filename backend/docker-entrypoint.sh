#!/bin/sh
# 容器启动流程: 等待数据库可用 -> 建表 -> 按需写入演示数据 -> gunicorn 启动
# 仅依赖镜像内的 python 与 pip 依赖, 不依赖 curl 等系统包
set -e

echo "[entrypoint] 初始化数据库表 ..."
attempt=0
until python -m flask --app wsgi init-db; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 15 ]; then
    echo "[entrypoint] 数据库不可用, 放弃重试" >&2
    exit 1
  fi
  echo "[entrypoint] 数据库暂不可用, 2 秒后重试 ($attempt/15)"
  sleep 2
done

if [ "${SEED_DEMO:-true}" = "true" ]; then
  echo "[entrypoint] 检查演示数据 ..."
  python -m flask --app wsgi seed || true
fi

echo "[entrypoint] 启动 gunicorn (workers=${GUNICORN_WORKERS:-2})"
exec gunicorn \
  --bind 0.0.0.0:5000 \
  --workers "${GUNICORN_WORKERS:-2}" \
  --timeout 60 \
  --access-logfile - \
  --error-logfile - \
  wsgi:app
