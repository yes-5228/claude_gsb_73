#!/usr/bin/env bash
# =============================================================================
# 空气监测点数据录入系统 —— 统一质量门禁
#
# 一条命令顺序完成:
#   1. 建表与初始化检查    5. (容器) 镜像构建内含前端生产构建
#   2. 演示数据校验        6. 容器编排启动 / 本地前后台进程启动
#   3. 后端测试 (pytest)   7. 健康检查 + 关键页面与 API 冒烟
#   4. 前端生产构建
#
# 用法:
#   ./scripts/quality-gate.sh local            # 本地方式: Python venv + Vite dev
#   ./scripts/quality-gate.sh docker           # 容器方式: docker compose (SQLite)
#   ./scripts/quality-gate.sh docker --postgres# 容器方式: docker compose (PostgreSQL)
#
# 可选参数:
#   --clean        忽略依赖/镜像缓存, 全量重建 (本地重装依赖, 容器 --no-cache)
#   --keep-up      冒烟结束后保留运行中的服务 (默认自动清理)
#   --help         查看帮助
#
# 特性:
#   * 可重复执行: 每次使用全新隔离数据库 (本地 .gate/gate.db, 容器独立卷),
#     不依赖也不读取上一次运行的数据; 结束后自动清理, 不触碰已有业务数据
#     (backend/instance/air_monitor.db 与日常 compose 卷/容器均不受影响)
#   * 结论稳定: seed 固定随机种子, 断言 8 站点 / 1200 数据 / 52 超标 (18/17/17)
#   * 失败即停: 每一步独立编号, 失败时打印卡点与修复建议, 最终以非零码退出
#   * 容器方式: 必须等待 backend(db) / frontend 全部 healthy 才进入冒烟
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_DIR="$ROOT_DIR/.gate"
LOG_DIR="$GATE_DIR/logs"
VENV_DIR="$GATE_DIR/venv"

# 门禁使用独立高位端口, 避免与日常开发实例冲突
LOCAL_BACKEND_PORT="${LOCAL_BACKEND_PORT:-15000}"
LOCAL_FRONTEND_PORT="${LOCAL_FRONTEND_PORT:-15173}"
DOCKER_BACKEND_PORT="${DOCKER_BACKEND_PORT:-15000}"
DOCKER_FRONTEND_PORT="${DOCKER_FRONTEND_PORT:-18080}"
DOCKER_DB_PORT="${DOCKER_DB_PORT:-15432}"

BACKEND_URL=""
FRONTEND_URL=""
BACKEND_PGID=""
FRONTEND_PGID=""
MODE=""
CLEAN=0
KEEP_UP=0
WITH_POSTGRES=0
STEP_CUR=""
COMPOSE_FILES=(-f docker-compose.yml -f scripts/quality-gate.compose.yml)
COMPOSE_OPTS=(-p qualitygate)

# ---------------------------------------------------------------- 输出与步骤
if [ -t 1 ]; then
  C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_RED=$'\033[1;31m'
  C_YELLOW=$'\033[1;33m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_BLUE=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_DIM=""; C_RESET=""
fi

step() { STEP_CUR="$2"; printf "\n%s==> [%s] %s%s\n" "$C_BLUE" "$1" "$2" "$C_RESET"; }
ok()   { printf "%s✔ %s%s\n" "$C_GREEN" "$1" "$C_RESET"; }
info() { printf "%s%s%s\n" "$C_DIM" "$1" "$C_RESET"; }
die()  { printf "\n%s✖ 质量门禁在 [%s] 失败%s\n" "$C_RED" "${STEP_CUR:-未知}" "$C_RESET"; printf "  %s\n" "$1"; exit 1; }

# ---------------------------------------------------------------- 通用工具
have() { command -v "$1" >/dev/null 2>&1; }

# docker 模式只需标准库, 直接用系统 python3; local 模式用门禁 venv
PY="python3"

# 等待 HTTP 端点返回 2xx; 参数: url 最大秒数
wait_http() {
  local url="$1" timeout="${2:-90}"
  "$PY" - "$url" "$timeout" <<'HTTP_PY'
import sys, time, urllib.request
url, deadline = sys.argv[1], int(sys.argv[2])
end = time.time() + deadline
last = "未开始"
while time.time() < end:
    try:
        with urllib.request.urlopen(url, timeout=4) as r:
            if 200 <= r.status < 300:
                sys.exit(0)
            last = "HTTP %s" % r.status
    except Exception as exc:
        last = str(exc)
    time.sleep(1)
print("等待超时 (%ss): %s" % (deadline, last), file=sys.stderr)
sys.exit(1)
HTTP_PY
}

# 回收上一轮 --keep-up 或异常中断遗留的门禁服务 (仅按端口 inode 反查, 不碰无关进程)
# 参数: 端口
reap_port_owner() {
  local port="$1"
  local pid pgid cmd
  pid="$(PORT_LOOKUP="$port" "$PY" - <<'LOOKUP'
import glob, os
target = int(os.environ["PORT_LOOKUP"])
inodes = set()
for path in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        lines = open(path).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        f = line.split()
        if f[3] != "0A":  # 只关心 LISTEN
            continue
        if int(f[1].rsplit(":", 1)[1], 16) == target:
            inodes.add(f[9])
if not inodes:
    raise SystemExit(0)
for fd in glob.glob("/proc/[0-9]*/fd/*"):
    try:
        link = os.readlink(fd)
    except OSError:
        continue
    if link.startswith("socket:[") and link[8:-1] in inodes:
        print(fd.split("/")[2]); raise SystemExit(0)
LOOKUP
)"
  [ -n "$pid" ] || return 0
  cmd="$(ps -o args= -p "$pid" 2>/dev/null)"
  # 只回收确认是门禁拉起的 gunicorn / vite (含自定义端口), 绝不误杀其他服务
  local is_gate=0
  case "$cmd" in
    *gunicorn*)
      case "$cmd" in *"$LOCAL_BACKEND_PORT"*|*"$DOCKER_BACKEND_PORT"*) is_gate=1;; esac ;;
    *vite*)
      case "$cmd" in *"$LOCAL_FRONTEND_PORT"*) is_gate=1;; esac ;;
  esac
  [ "$is_gate" -eq 1 ] || return 0
  pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
  info "发现上一轮门禁遗留服务 (pid=$pid, pgid=$pgid, 端口 $port), 自动回收"
  kill -TERM -- "-$pgid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  sleep 1
  kill -KILL -- "-$pgid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
}

# 检查端口是否可被新服务绑定:
# 无 LISTEN 即可; TIME_WAIT 不影响真实服务 (gunicorn/vite 均设 SO_REUSEADDR)
assert_port_free() {
  local port="$1"
  reap_port_owner "$port"
  "$PY" - "$port" <<'PORT_PY' || die "端口 $1 存在非本门禁的 LISTEN 进程 (未自动处理)。请停掉该服务, 或用环境变量换端口, 例如 LOCAL_BACKEND_PORT=15001 LOCAL_FRONTEND_PORT=15174 $0 local"
import socket, sys

port = int(sys.argv[1])

def has_listener():
    # connect 探测: 只有 LISTEN 状态才能连上 (TIME_WAIT 不响应)
    probe = socket.socket()
    probe.settimeout(0.5)
    try:
        probe.connect(("127.0.0.1", port))
        return True
    except OSError:
        return False
    finally:
        probe.close()

# 带 SO_REUSEADDR 绑定: 仅当存在 LISTEN 时才失败
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("127.0.0.1", port))
    sys.exit(1 if has_listener() else 0)
except OSError:
    sys.exit(1)
finally:
    s.close()
PORT_PY
}

# 等待 compose 服务健康; 参数: 服务名 最大秒数
wait_container_healthy() {
  local service="$1" timeout="${2:-150}" waited=0 cid line
  cid="$(docker compose "${COMPOSE_OPTS[@]}" "${COMPOSE_FILES[@]}" ps -q "$service")"
  [ -n "$cid" ] || die "服务 $service 容器未创建, 请查看上方 compose 输出"
  while [ "$waited" -lt "$timeout" ]; do
    line="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo missing)"
    case "$line" in
      healthy) ok "$service 健康检查通过"; return 0 ;;
      unhealthy|exited|dead)
        docker compose "${COMPOSE_OPTS[@]}" "${COMPOSE_FILES[@]}" ps "$service" || true
        docker logs --tail 40 "$cid" 2>/dev/null | sed 's/^/    | /' || true
        die "$service 健康检查状态为 '$line'。上方为容器日志; 常见原因: 数据库未就绪/端口冲突/应用启动报错"
        ;;
    esac
    sleep 2; waited=$((waited + 2))
    if [ $((waited % 20)) -eq 0 ]; then info "  ... 等待 $service 健康 ($waited s, 当前 $line)"; fi
  done
  die "$service 在 ${timeout}s 内未变为 healthy。可用 'docker compose -p qualitygate logs $service' 排查"
}

# ---------------------------------------------------------------- 清理
# 在独立进程组中启动后台服务
# 用法: start_grouped 工作目录 日志文件 命令...
# 通过 $! 拿到 setsid 出的子进程 PID; setsid 保证该 PID 即为新进程组 PGID
start_grouped() {
  local workdir="$1" logfile="$2"; shift 2
  ( cd "$workdir" && exec setsid "$@" ) >"$logfile" 2>&1 &
  SERVICE_PID=$!
  # setsid 不经额外 fork 时, 子进程 PID 即新组 PGID
  SERVICE_PGID="$(ps -o pgid= -p "$SERVICE_PID" 2>/dev/null | tr -d ' ')"
  [ -n "$SERVICE_PGID" ] || SERVICE_PGID="$SERVICE_PID"
}

_stop_group() {
  local pgid="$1"
  [ -n "$pgid" ] || return 0
  kill -TERM -- "-$pgid" 2>/dev/null || kill -TERM "$pgid" 2>/dev/null || true
}
_kill_group() {
  local pgid="$1"
  [ -n "$pgid" ] || return 0
  kill -KILL -- "-$pgid" 2>/dev/null || kill -KILL "$pgid" 2>/dev/null || true
}

cleanup_local() {
  [ -n "$FRONTEND_PGID" ] && info "停止本地前端进程组 (pgid=$FRONTEND_PGID)"
  _stop_group "$FRONTEND_PGID"
  [ -n "$BACKEND_PGID" ] && info "停止本地后端进程组 (pgid=$BACKEND_PGID)"
  _stop_group "$BACKEND_PGID"
  sleep 1
  _kill_group "$FRONTEND_PGID"
  _kill_group "$BACKEND_PGID"
}

# 确认已无 LISTEN 进程 (TIME_WAIT 不算占用, 不阻塞下一轮启动)
wait_ports_released() {
  "$PY" "$LOCAL_BACKEND_PORT" "$LOCAL_FRONTEND_PORT" <<'PORT_WAIT'
import socket, sys, time

def listening(port):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("127.0.0.1", port))
        s.close()
        probe = socket.socket()
        probe.settimeout(0.3)
        try:
            probe.connect(("127.0.0.1", port))
            probe.close()
            return True
        except OSError:
            return False
    except OSError:
        return True
    finally:
        s.close()

deadline = time.time() + 10
while time.time() < deadline:
    busy = [p for p in (int(x) for x in sys.argv[1:]) if listening(p)]
    if not busy:
        sys.exit(0)
    time.sleep(0.2)
sys.stderr.write("仍有监听: %s\n" % busy)
sys.exit(1)
PORT_WAIT
}

cleanup_docker() {
  info "清理门禁编排资源 (project=qualitygate, 含数据卷)"
  docker compose "${COMPOSE_OPTS[@]}" "${COMPOSE_FILES[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
}

on_exit() {
  local code=$?
  trap - EXIT INT TERM
  if [ "$code" -eq 0 ] && [ "$KEEP_UP" -eq 1 ]; then
    printf "%s门禁通过, --keep-up 保留服务: 前端 %s, 后端 %s%s\n" "$C_YELLOW" "$FRONTEND_URL" "$BACKEND_URL" "$C_RESET"
    exit 0
  fi
  if [ "$code" -ne 0 ]; then
    printf "%s日志目录: %s%s\n" "$C_YELLOW" "$LOG_DIR" "$C_RESET"
  fi
  if [ "$MODE" = "local" ]; then
    cleanup_local
    wait_ports_released 2>/dev/null || true
    if [ "$code" -eq 0 ]; then rm -f "$GATE_DIR/gate.db"; fi
  elif [ "$MODE" = "docker" ] && [ "$KEEP_UP" -eq 0 ]; then
    cleanup_docker
  fi
  exit "$code"
}
trap on_exit EXIT
trap 'exit 130' INT TERM
# ---------------------------------------------------------------- 前置检查
usage() { sed -n '2,30p' "$0"; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    local) MODE=local ;;
    docker) MODE=docker ;;
    --postgres) WITH_POSTGRES=1 ;;
    --clean) CLEAN=1 ;;
    --keep-up) KEEP_UP=1 ;;
    -h|--help) usage ;;
    *) echo "未知参数: $1" >&2; usage ;;
  esac
  shift
done

[ -n "$MODE" ] || { echo "必须指定启动方式: local 或 docker" >&2; usage; }

mkdir -p "$LOG_DIR"
step "0" "环境前置检查 ($MODE)"

if [ "$MODE" = "local" ]; then
  have python3 || die "未找到 python3。请安装 Python 3.10+ (后端要求 3.12 语法兼容, 实测 3.11 可运行)"
  PY_VER="$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')"
  info "python3 $PY_VER"
  have node || die "未找到 node。请安装 Node.js 18+ (推荐 20/22): https://nodejs.org"
  have npm  || die "未找到 npm, 请随 Node.js 一并安装"
  info "node $(node --version), npm $(npm --version)"
  assert_port_free "$LOCAL_BACKEND_PORT"
  assert_port_free "$LOCAL_FRONTEND_PORT"
  BACKEND_URL="http://127.0.0.1:$LOCAL_BACKEND_PORT"
  FRONTEND_URL="http://127.0.0.1:$LOCAL_FRONTEND_PORT"
else
  have docker || die "未找到 docker。请安装并启动 Docker Desktop / Docker Engine: https://docs.docker.com/engine/install/"
  if docker compose version >/dev/null 2>&1; then info "$(docker compose version | head -1)"
  elif have docker-compose; then
    die "检测到旧版 docker-compose (v1)。请升级为 Docker Compose v2 插件"
  else
    die "未找到 docker compose v2, 请安装 compose 插件或新版 Docker Desktop"
  fi
  if ! docker info >/dev/null 2>&1; then
    die "docker 守护进程不可用。请启动 Docker Desktop 或检查当前用户是否在 docker 用户组"
  fi
  assert_port_free "$DOCKER_BACKEND_PORT"
  assert_port_free "$DOCKER_FRONTEND_PORT"
  if [ "$WITH_POSTGRES" -eq 1 ]; then
    COMPOSE_FILES+=(-f docker-compose.postgres.yml)
    assert_port_free "$DOCKER_DB_PORT"
    # 门禁覆盖: 给 postgres 也映射独立端口并关闭重启策略
    cat > "$GATE_DIR/quality-gate-pg.override.yml" <<YML
services:
  db:
    container_name: qualitygate-db
    restart: "no"
    ports:
      - "${DOCKER_DB_PORT}:5432"
YML
    COMPOSE_FILES+=(-f "$GATE_DIR/quality-gate-pg.override.yml")
  fi
  BACKEND_URL="http://127.0.0.1:$DOCKER_BACKEND_PORT"
  FRONTEND_URL="http://127.0.0.1:$DOCKER_FRONTEND_PORT"
fi

# 门禁全程使用全新数据库, 保证可重复且不污染业务数据
if [ "$MODE" = "local" ]; then
  rm -f "$GATE_DIR/gate.db"
else
  # 清掉可能由上次中断遗留的同名项目资源 (独立卷, 与日常 air-monitor-data 无关)
  cleanup_docker
fi
ok "隔离工作区: $GATE_DIR"

# ============================================================ LOCAL 模式
run_local() {
  # ---- [L1] Python 依赖 (venv) ------------------------------------------
  step "L1" "准备 Python 虚拟环境与后端依赖"
  if [ "$CLEAN" -eq 1 ]; then rm -rf "$VENV_DIR"; fi
  if [ ! -x "$VENV_DIR/bin/python" ]; then
    info "创建虚拟环境 $VENV_DIR (与系统站点包隔离)"
    if ! python3 -m venv "$VENV_DIR" >"$LOG_DIR/venv.log" 2>&1; then
      info "标准 venv 失败 (常见于 Debian/Ubuntu 缺少 python3-venv), 改用 --without-pip 引导"
      rm -rf "$VENV_DIR"
      python3 -m venv --without-pip "$VENV_DIR" >>"$LOG_DIR/venv.log" 2>&1 \
        || die "无法创建虚拟环境, 见 $LOG_DIR/venv.log。Debian/Ubuntu 可执行: sudo apt install python3-venv"
      if [ ! -f "$GATE_DIR/get-pip.py" ]; then
        curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "$GATE_DIR/get-pip.py" 2>>"$LOG_DIR/venv.log" \
          || die "下载 get-pip.py 失败 (网络问题?), 见 $LOG_DIR/venv.log; 也可直接安装系统包 python3-venv"
      fi
      "$VENV_DIR/bin/python" "$GATE_DIR/get-pip.py" >>"$LOG_DIR/venv.log" 2>&1 \
        || die "向虚拟环境引导 pip 失败, 见 $LOG_DIR/venv.log"
    fi
  fi
  if ! "$VENV_DIR/bin/python" -c "import flask, pytest, sqlalchemy" 2>/dev/null || [ "$CLEAN" -eq 1 ]; then
    info "安装 backend/requirements-dev.txt"
    "$VENV_DIR/bin/python" -m pip install -q --disable-pip-version-check \
      -r "$ROOT_DIR/backend/requirements-dev.txt" >"$LOG_DIR/pip-install.log" 2>&1 \
      || die "后端依赖安装失败, 见 $LOG_DIR/pip-install.log (多为网络/镜像问题, 可设置 pip 镜像源重试)"
  fi
  PY="$VENV_DIR/bin/python"
  ok "Python 环境就绪"

  local gate_db="sqlite:///$GATE_DIR/gate.db"
  local common_env=(DATABASE_URL="$gate_db" AUTO_INIT_DB=false AUTO_SEED=false
                    FLASK_ENV=development PYTHONDONTWRITEBYTECODE=1
                    PYTHONPATH="$ROOT_DIR/backend")

  # ---- [L2] 建表 ----------------------------------------------------------
  step "L2" "建表与初始化检查 (flask init-db, 全新 SQLite)"
  ( cd "$ROOT_DIR/backend" && env "${common_env[@]}" \
      "$VENV_DIR/bin/python" -m flask --app wsgi init-db ) >"$LOG_DIR/init-db.log" 2>&1 \
    || die "建表失败, 见 $LOG_DIR/init-db.log"
  grep -q "数据库表已创建" "$LOG_DIR/init-db.log" \
    || die "init-db 未输出成功标志, 见 $LOG_DIR/init-db.log"
  ok "数据库表已在隔离库中创建"

  # ---- [L3] 写入演示数据 --------------------------------------------------
  step "L3" "写入演示数据 (flask seed)"
  ( cd "$ROOT_DIR/backend" && env "${common_env[@]}" \
      "$VENV_DIR/bin/python" -m flask --app wsgi seed ) >"$LOG_DIR/seed.log" 2>&1 \
    || die "演示数据写入失败, 见 $LOG_DIR/seed.log"
  ok "演示数据写入完成"

  # ---- [L4] 演示数据校验 --------------------------------------------------
  step "L4" "演示数据一致性校验 (scripts/verify_seed.py)"
  ( cd "$ROOT_DIR/backend" && env "${common_env[@]}" \
      "$VENV_DIR/bin/python" "$ROOT_DIR/scripts/verify_seed.py" ) 2>&1 | tee "$LOG_DIR/verify-seed.log" \
    || die "演示数据不符合基准或存在脏数据, 见上方明细与 $LOG_DIR/verify-seed.log; 检查 backend/app/seed.py 与业务规则"

  # ---- [L5] 后端测试 ------------------------------------------------------
  step "L5" "后端测试 (pytest, 独立内存库, 不触碰门禁库)"
  ( cd "$ROOT_DIR/backend" && FLASK_ENV=testing \
      "$VENV_DIR/bin/python" -m pytest ) 2>&1 | tee "$LOG_DIR/pytest.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] \
    || die "后端测试存在失败用例, 见 $LOG_DIR/pytest.log; 修复对应 tests/ 用例或业务代码后重跑本命令"

  # ---- [L6] 前端依赖与构建 ------------------------------------------------
  step "L6" "前端生产构建 (npm ci + vite build)"
  if [ "$CLEAN" -eq 1 ]; then rm -rf "$ROOT_DIR/frontend/node_modules" "$ROOT_DIR/frontend/dist"; fi
  if [ ! -d "$ROOT_DIR/frontend/node_modules" ]; then
    info "安装前端依赖 (npm ci)"
    ( cd "$ROOT_DIR/frontend" && npm ci --no-audit --no-fund ) >"$LOG_DIR/npm-ci.log" 2>&1 \
      || die "前端依赖安装失败, 见 $LOG_DIR/npm-ci.log (可尝试 npm config 设置 registry 镜像)"
  fi
  ( cd "$ROOT_DIR/frontend" && npm run build ) >"$LOG_DIR/frontend-build.log" 2>&1 \
    || { tail -30 "$LOG_DIR/frontend-build.log" | sed 's/^/    | /';
         die "前端构建失败, 完整日志 $LOG_DIR/frontend-build.log; 按上方 vite 报错修正代码后重跑"; }
  ok "前端生产构建成功 (frontend/dist)"

  # ---- [L7] 启动本地服务 --------------------------------------------------
  step "L7" "启动本地后端与前端 (隔离端口 $LOCAL_BACKEND_PORT/$LOCAL_FRONTEND_PORT)"
  # 服务以独立进程组启动 (setsid), 退出时按 PGID 整组回收 (含 npx->vite / gunicorn worker)
  # 优先 gunicorn (无 debug reloader); 不可用时退回 flask run
  if "$VENV_DIR/bin/python" -c "import gunicorn" 2>/dev/null; then
    start_grouped "$ROOT_DIR/backend" "$LOG_DIR/backend.log" \
      env "${common_env[@]}" "$VENV_DIR/bin/python" -m gunicorn \
      --bind "127.0.0.1:$LOCAL_BACKEND_PORT" --workers 1 --timeout 60 wsgi:app
  else
    start_grouped "$ROOT_DIR/backend" "$LOG_DIR/backend.log" \
      env "${common_env[@]}" "$VENV_DIR/bin/python" -m flask --app wsgi run \
      --host 127.0.0.1 --port "$LOCAL_BACKEND_PORT" --without-threads
  fi
  BACKEND_PGID="$SERVICE_PGID"
  wait_http "$BACKEND_URL/api/meta/health" 60 \
    || { tail -30 "$LOG_DIR/backend.log" | sed 's/^/    | /';
         die "后端在 60s 内未就绪, 见 $LOG_DIR/backend.log"; }
  ok "后端就绪: $BACKEND_URL"

  start_grouped "$ROOT_DIR/frontend" "$LOG_DIR/frontend.log" \
    env VITE_PROXY_TARGET="$BACKEND_URL" npx vite \
    --port "$LOCAL_FRONTEND_PORT" --strictPort
  FRONTEND_PGID="$SERVICE_PGID"
  wait_http "$FRONTEND_URL/" 90 \
    || { tail -30 "$LOG_DIR/frontend.log" | sed 's/^/    | /';
         die "Vite 开发服务器在 90s 内未就绪, 见 $LOG_DIR/frontend.log"; }
  ok "前端就绪: $FRONTEND_URL (/api 代理到后端)"
  wait_http "$FRONTEND_URL/" 90 \
    || { tail -30 "$LOG_DIR/frontend.log" | sed 's/^/    | /';
         die "Vite 开发服务器在 90s 内未就绪, 见 $LOG_DIR/frontend.log"; }
  ok "前端就绪: $FRONTEND_URL (/api 代理到后端)"

  # ---- [L8] 冒烟 ----------------------------------------------------------
  step "L8" "关键页面与 API 冒烟 (经前端代理入口)"
  "$PY" "$ROOT_DIR/scripts/smoke_check.py" "$FRONTEND_URL" \
    2>&1 | tee "$LOG_DIR/smoke.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] \
    || die "冒烟未通过, 见 $LOG_DIR/smoke.log 与 backend/frontend 运行日志"
}

# ============================================================ DOCKER 模式
compose() { docker compose "${COMPOSE_OPTS[@]}" "${COMPOSE_FILES[@]}" "$@"; }

run_docker() {
  # ---- [D0] compose 文件合并校验 (在构建前快速暴露 YAML/合并错误) ---------
  step "D0" "校验 docker compose 编排配置"
  compose config >"$LOG_DIR/compose-config.yml" 2>&1 \
    || { cat "$LOG_DIR/compose-config.yml" | sed 's/^/    | /';
         die "compose 配置合并失败, 检查 docker-compose*.yml 与 scripts/quality-gate.compose.yml"; }
  info "合并配置已输出: $LOG_DIR/compose-config.yml"

  # ---- [D1] 后端镜像构建 (构建即验证 Dockerfile) --------------------------
  step "D1" "构建后端镜像 (air-monitor-backend)"
  local cache_flag=""
  [ "$CLEAN" -eq 1 ] && cache_flag="--no-cache"
  compose build $cache_flag backend >"$LOG_DIR/docker-build-backend.log" 2>&1 \
    || { tail -40 "$LOG_DIR/docker-build-backend.log" | sed 's/^/    | /';
         die "后端镜像构建失败, 完整日志 $LOG_DIR/docker-build-backend.log"; }
  ok "后端镜像构建成功"

  # ---- [D2] 后端测试 (一次性容器, 测试目录只读挂载) -----------------------
  step "D2" "后端测试 (pytest, 一次性容器, 独立内存 SQLite 库)"
  compose run --rm --no-deps \
    -e FLASK_ENV=testing \
    -v "$ROOT_DIR/backend/tests:/app/tests:ro" \
    --entrypoint sh \
    backend -c "pip install -q pytest==8.3.2 && python -m pytest" 2>&1 | tee "$LOG_DIR/pytest.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] \
    || die "后端测试存在失败用例, 见 $LOG_DIR/pytest.log"

  # ---- [D3] 前端镜像构建 (内含 npm install + vite build) ------------------
  step "D3" "前端生产构建 (Docker 多阶段构建: npm install + vite build)"
  compose build $cache_flag frontend >"$LOG_DIR/docker-build-frontend.log" 2>&1 \
    || { tail -40 "$LOG_DIR/docker-build-frontend.log" | sed 's/^/    | /';
         die "前端镜像/构建失败, 完整日志 $LOG_DIR/docker-build-frontend.log; 构建已执行 vite build, 按报错修正前端代码"; }
  ok "前端镜像构建成功 (构建阶段已通过 vite build)"

  # ---- [D4] 编排启动 ------------------------------------------------------
  step "D4" "docker compose 启动全新编排栈 (独立卷, 首次启动建表+seed)"
  # 使用全新卷: 上面 cleanup_docker 已清; 若 --keep-up 重跑则再保险一次
  compose up -d >"$LOG_DIR/compose-up.log" 2>&1 \
    || { tail -40 "$LOG_DIR/compose-up.log" | sed 's/^/    | /';
         die "编排启动失败, 见 $LOG_DIR/compose-up.log"; }
  if [ "$WITH_POSTGRES" -eq 1 ]; then wait_container_healthy db 120; fi
  wait_container_healthy backend 180
  wait_container_healthy frontend 120
  compose ps 2>&1 | sed 's/^/    /'

  # ---- [D5] 初始化检查: 建表与演示数据 (HTTP 侧确定性校验) ----------------
  step "D5" "建表与演示数据校验 (经运行中容器的 HTTP API)"
  # 冒烟脚本同时承担: 健康检查、8/1200/52(18/17/17) 数据基准与一致性
  "$PY" "$ROOT_DIR/scripts/smoke_check.py" "$BACKEND_URL" \
    2>&1 | tee "$LOG_DIR/verify-seed.log" \
    || die "容器内建表/演示数据与基准不符, 见 $LOG_DIR/verify-seed.log; 可执行 compose 日志排查: docker compose -p qualitygate logs backend"

  # ---- [D6] 关键页面冒烟 (nginx 静态托管 + /api 代理) ---------------------
  step "D6" "关键页面与 API 冒烟 (经 nginx 前端入口 + 反代)"
  "$PY" "$ROOT_DIR/scripts/smoke_check.py" "$FRONTEND_URL" \
    2>&1 | tee "$LOG_DIR/smoke.log"
  [ "${PIPESTATUS[0]}" -eq 0 ] \
    || die "冒烟未通过, 见 $LOG_DIR/smoke.log; nginx 代理或前端产物异常时查看: docker compose -p qualitygate logs"
}

# ---------------------------------------------------------------- 执行门禁
START_TS=$(date +%s)
if [ "$MODE" = "local" ]; then
  run_local
else
  run_docker
fi

ELAPSED=$(( $(date +%s) - START_TS ))
printf "\n%s════════════════════════════════════════════%s\n" "$C_GREEN" "$C_RESET"
printf "%s✔ 质量门禁全部通过 (%s 模式, 耗时 %ds)%s\n" "$C_GREEN" "$MODE" "$ELAPSED" "$C_RESET"
if [ "$MODE" = "local" ]; then
  printf "  覆盖: 建表初始化 → 演示数据校验 → 后端 pytest → 前端 vite build → 本地起服 → 冒烟\n"
else
  printf "  覆盖: 镜像构建(含前端构建) → 容器内 pytest → 编排启动 → 健康检查 → 数据校验 → 页面冒烟\n"
  [ "$WITH_POSTGRES" -eq 1 ] && printf "  数据库: PostgreSQL 16 覆盖方式\n"
fi
printf "  日志: %s\n" "$LOG_DIR"
