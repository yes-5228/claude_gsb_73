#!/usr/bin/env bash
# =============================================================================
# 统一质量门禁 (Quality Gate)
#
# 一条命令依次完成 6 个门禁步骤:
#   1. 建表与初始化检查
#   2. 演示数据校验
#   3. 后端测试 (pytest)
#   4. 前端构建 (vite build)
#   5. 编排启动并等待全部服务健康 (本地起 dev server / 容器用 docker compose)
#   6. 关键页面冒烟访问
#
# 两种启动方式:
#   scripts/quality-gate/gate.sh local     # 本地: 隔离 venv + Vite(preview 构建产物)
#   scripts/quality-gate/gate.sh docker    # 容器: docker compose 独立项目/镜像/卷
#
# 特性:
#   - 可重复执行: 每次使用独立临时目录/独立 compose 项目与数据卷, 结束即清理
#   - 不污染已有业务数据: 不触碰 backend/instance, 不使用默认 compose 项目/镜像/卷
#   - 端口预检: 固定门禁端口被占用时直接报修复建议, 而不是与现有服务混连
#   - 失败定位: 每步打印编号与日志位置, 附修复建议, 任一步失败整体非零退出
#   - 容器方式: 必须等 backend(healthcheck healthy) 与 frontend(/healthz) 就绪才冒烟
# =============================================================================

set -uo pipefail

# ---------- 路径 ----------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/scripts/quality-gate"
GATE_HOME="$ROOT_DIR/.tools/quality-gate"
WORK_DIR=""
LOG_PREFIX=""
MODE=""
GATE_OK=0

# 门禁专用端口: 避开 README 默认开发端口, 避免与开发中服务串数据
LOCAL_BACKEND_PORT="${GATE_BACKEND_PORT:-5055}"
LOCAL_FRONTEND_PORT="${GATE_FRONTEND_PORT:-5188}"
DOCKER_PROJECT="airqgate"
DOCKER_BACKEND_PORT="${GATE_DOCKER_BACKEND_PORT:-5090}"
DOCKER_FRONTEND_PORT="${GATE_DOCKER_FRONTEND_PORT:-8098}"

STEP=""
STEP_NO=0
TOTAL_STEPS=6
CLEANUP_RAN=0
INSTANCE_EXISTED=0
INSTANCE_DIR=""

# ---------- 输出 ----------
c_red()   { printf '\033[31m%s\033[0m' "$*"; }
c_green() { printf '\033[32m%s\033[0m' "$*"; }
c_dim()   { printf '\033[2m%s\033[0m' "$*"; }
c_bold()  { printf '\033[1m%s\033[0m' "$*"; }

phase_start() {
  # 不计入门禁编号的准备阶段
  STEP="$1"
  LOG_PREFIX="$WORK_DIR/logs/00-$2.log"
  mkdir -p "$WORK_DIR/logs"
  echo
  echo "----------------------------------------------------------"
  echo "[$(date '+%H:%M:%S')] 准备: $(c_bold "$STEP") $(c_dim "(不计入 6 步门禁)")"
  echo "----------------------------------------------------------"
}

step_start() {
  STEP_NO=$((STEP_NO + 1))
  STEP="$1"
  LOG_PREFIX="$WORK_DIR/logs/$(printf '%02d' "$STEP_NO")-$2.log"
  mkdir -p "$WORK_DIR/logs"
  echo
  echo "=========================================================="
  echo "[$(date '+%H:%M:%S')] 步骤 ${STEP_NO}/${TOTAL_STEPS}: $(c_bold "$STEP")"
  echo "----------------------------------------------------------"
}

step_ok() { echo "[$(date '+%H:%M:%S')] $(c_green '[通过]') $STEP"; }

die() {
  # die <修复建议>
  local advice="$1"
  echo
  echo "$(c_red '✗ 门禁失败') 于步骤 ${STEP_NO}/${TOTAL_STEPS}: $(c_bold "$STEP")"
  echo "  日志: ${LOG_PREFIX}"
  echo "  修复建议: ${advice}"
  GATE_OK=1
  exit 1
}

# ---------- 公共工具 ----------
port_in_use() {
  # 优先用 ss; 否则用 python3 socket(比 bash /dev/tcp 在沙箱下可靠, python3 为必需依赖)
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -Eq "[:.]${port}[[:space:]]"
  else
    python3 - "$port" <<'PY'
import socket, sys
s = socket.socket(); s.settimeout(1)
rc = s.connect_ex(("127.0.0.1", int(sys.argv[1])))
s.close()
sys.exit(0 if rc == 0 else 1)
PY
  fi
}

wait_http() {
  # wait_http <url> <秒数上限> <描述>
  local url="$1" deadline="$2" label="$3" waited=0
  while (( waited < deadline )); do
    if curl -fsS -o /dev/null --max-time 4 "$url" 2>/dev/null; then
      echo "  $label 已就绪 (${waited}s): $url"
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  echo "  [FAIL] $label 等待 ${deadline}s 仍不可用: $url"
  return 1
}

# =============================================================================
# 清理: 只清理本门禁创建的进程/容器/临时目录
# =============================================================================
cleanup() {
  [[ $CLEANUP_RAN -eq 1 ]] && return
  CLEANUP_RAN=1
  echo
  echo "== 清理门禁临时资源 =="

  if [[ "$MODE" == "local" && -n "$WORK_DIR" ]]; then
    # 递归回收门禁启动的进程树(不依赖 setsid, 兼容 macOS), 避免漏杀 node/python 子进程
    kill_tree() {
      local pid="$1" child
      while read -r child; do
        [[ -n "$child" ]] && kill_tree "$child"
      done < <(pgrep -P "$pid" 2>/dev/null || true)
      kill -TERM "$pid" 2>/dev/null || true
    }
    for pidfile in "$WORK_DIR"/backend.pid "$WORK_DIR"/frontend.pid; do
      if [[ -f "$pidfile" ]]; then
        local pid
        pid="$(cat "$pidfile" 2>/dev/null || true)"
        if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
          kill_tree "$pid"
          sleep 1
          kill -KILL "$pid" 2>/dev/null || true
          echo "  已停止本地进程树 pid=$pid ($(basename "$pidfile"))"
        fi
      fi
    done
  fi

  if [[ "$MODE" == "docker" && -n "$WORK_DIR" && -f "$WORK_DIR/docker-compose.gate.yml" ]]; then
    ( cd "$ROOT_DIR" && docker compose -p "$DOCKER_PROJECT" \
        -f docker-compose.yml -f "$WORK_DIR/docker-compose.gate.yml" \
        down -v --remove-orphans ) >>"$WORK_DIR/logs/cleanup.log" 2>&1 || true
    echo "  已删除容器与项目卷 (project=$DOCKER_PROJECT)"
    # 清理门禁专用镜像(独立 tag, 不影响 air-monitor-*:1.0.0)
    docker image rm -f "${DOCKER_PROJECT}-backend:latest" "${DOCKER_PROJECT}-frontend:latest" \
      >>"$WORK_DIR/logs/cleanup.log" 2>&1 || true
    echo "  已删除门禁专用镜像 ${DOCKER_PROJECT}-{backend,frontend}:latest"
  fi

  if [[ -n "${KEEP_WORKDIR:-}" ]]; then
    echo "  保留工作目录(KEEP_WORKDIR=1): $WORK_DIR"
  elif [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
    echo "  已删除临时工作目录"
  fi

  # 回收 create_app() 自动创建的空 backend/instance; 仅当门禁前不存在且当前为空
  if [[ "$MODE" == "local" && $INSTANCE_EXISTED -eq 0 && -d "$INSTANCE_DIR" ]] \
     && [[ -z "$(ls -A "$INSTANCE_DIR" 2>/dev/null)" ]]; then
    rmdir "$INSTANCE_DIR" 2>/dev/null && echo "  已回收自动生成的空 backend/instance"
  fi
  echo "  未触碰 backend/instance 与默认 air-monitor 栈, 已有业务数据不受影响。"
}

on_exit() {
  local code=$?
  cleanup
  if [[ $code -eq 0 && $GATE_OK -eq 0 ]]; then
    echo
    echo "=========================================================="
    echo "$(c_green '✓ 质量门禁全部通过') 模式=$MODE 步骤=${TOTAL_STEPS}/${TOTAL_STEPS}"
    echo "  临时资源已清理, 仓库工作区与已有业务数据未被修改。"
    echo "=========================================================="
  fi
  exit $code
}
trap on_exit EXIT
trap 'exit 130' INT TERM

# =============================================================================
# 前置检查
# =============================================================================
preflight() {
  echo "$(c_bold '统一质量门禁') 模式: $(c_green "$MODE")   仓库: $ROOT_DIR"
  mkdir -p "$GATE_HOME/runs"
  WORK_DIR="$(mktemp -d "$GATE_HOME/runs/run-XXXXXX")"
  mkdir -p "$WORK_DIR/logs"
  echo "本次隔离工作目录: $WORK_DIR"

  # 记录 backend/instance 是否原本存在: create_app() 会无条件创建该空目录,
  # 清理时仅当它是门禁新建且仍为空才回收, 绝不动用户已有的业务库。
  INSTANCE_DIR="$ROOT_DIR/backend/instance"
  [[ -e "$INSTANCE_DIR" ]] && INSTANCE_EXISTED=1

  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=("curl")
  command -v python3 >/dev/null 2>&1 || missing+=("python3")
  if [[ "$MODE" == "local" ]]; then
    command -v node >/dev/null 2>&1 || missing+=("node")
    command -v npm >/dev/null 2>&1 || missing+=("npm")
  else
    if ! command -v docker >/dev/null 2>&1; then
      echo "$(c_red '未找到 docker 命令。') 请安装 Docker 后重试, 或改用: scripts/quality-gate/gate.sh local"
      exit 2
    fi
    if ! docker info >/dev/null 2>&1; then
      echo "$(c_red 'Docker 守护进程不可用。') 请启动 Docker Desktop/daemon 后重试。"
      exit 2
    fi
    docker compose version >/dev/null 2>&1 || { echo "$(c_red '需要 docker compose v2。')"; exit 2; }
  fi
  if (( ${#missing[@]} )); then
    echo "$(c_red "缺少必需命令: ${missing[*]}")"
    exit 2
  fi

  local ports
  if [[ "$MODE" == "local" ]]; then
    ports=("$LOCAL_BACKEND_PORT" "$LOCAL_FRONTEND_PORT")
  else
    ports=("$DOCKER_BACKEND_PORT" "$DOCKER_FRONTEND_PORT")
  fi
  local p
  for p in "${ports[@]}"; do
    if port_in_use "$p"; then
      echo "$(c_red "门禁端口 $p 已被占用。") 为避免连到已有服务, 请先释放该端口,"
      echo "  或通过 GATE_BACKEND_PORT/GATE_FRONTEND_PORT(local)、"
      echo "  GATE_DOCKER_BACKEND_PORT/GATE_DOCKER_FRONTEND_PORT(docker) 指定其他端口。"
      exit 2
    fi
  done
}

# =============================================================================
# 本地环境准备: 隔离 venv(系统无 pip 时用 get-pip 引导)
# =============================================================================
PYTHON_BIN=""
ensure_python_env() {
  local venv_dir="$GATE_HOME/venv"
  PYTHON_BIN="$venv_dir/bin/python"
  if [[ -x "$PYTHON_BIN" ]] && "$PYTHON_BIN" -c "import flask, pytest" >/dev/null 2>&1; then
    echo "  复用后端虚拟环境: $venv_dir"
    return 0
  fi
  echo "  创建后端虚拟环境: $venv_dir (首次较慢)"
  rm -rf "$venv_dir"
  python3 -m venv "$venv_dir" >>"$LOG_PREFIX" 2>&1 || \
    python3 -m venv --without-pip "$venv_dir" >>"$LOG_PREFIX" 2>&1 || \
    die "python3 venv 不可用; Debian/Ubuntu 请先安装 python3-venv"

  if ! "$PYTHON_BIN" -m pip --version >>"$LOG_PREFIX" 2>&1; then
    echo "  venv 未带 pip, 使用 get-pip.py 引导 ..."
    curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "$WORK_DIR/get-pip.py" \
      >>"$LOG_PREFIX" 2>&1 || die "无法下载 get-pip.py, 检查网络/代理后重试"
    "$PYTHON_BIN" "$WORK_DIR/get-pip.py" >>"$LOG_PREFIX" 2>&1 || die "pip 引导失败, 见日志"
  fi
  "$PYTHON_BIN" -m pip install -q -r "$ROOT_DIR/backend/requirements-dev.txt" \
    >>"$LOG_PREFIX" 2>&1 || \
    die "后端依赖安装失败; 可手动执行: $PYTHON_BIN -m pip install -r backend/requirements-dev.txt"
}

# 前端依赖装在隔离目录, 不触碰开发者已有的 frontend/node_modules
FRONTEND_WORK=""
ensure_frontend_env() {
  FRONTEND_WORK="$GATE_HOME/frontend-work"
  mkdir -p "$FRONTEND_WORK"
  ( cd "$ROOT_DIR/frontend" && \
    tar --exclude='./node_modules' --exclude='./dist' --exclude='./.vite' -cf - . ) \
    | ( cd "$FRONTEND_WORK" && tar -xf - )
  if [[ -d "$FRONTEND_WORK/node_modules/vite" ]]; then
    echo "  复用前端依赖: $FRONTEND_WORK/node_modules"
  else
    echo "  安装前端依赖到隔离目录(首次较慢) ..."
    ( cd "$FRONTEND_WORK" && npm install --no-audit --no-fund ) >>"$LOG_PREFIX" 2>&1 || \
      die "npm install 失败, 见日志; 也可手动重试: cd frontend && npm install"
  fi
}

# =============================================================================
# 本地模式
# =============================================================================
run_local() {
  local db="$GATE_HOME/gate.db"
  # 关闭启动期自动建表/seed —— 建表与演示数据必须由步骤 1/2 显式完成, 才能证明初始化链路
  local app_env=(
    env "DATABASE_URL=sqlite:///$db"
    "FLASK_ENV=development"
    "AUTO_INIT_DB=false"
    "AUTO_SEED=false"
    "PYTHONPATH=$ROOT_DIR/backend"
    "PYTHONDONTWRITEBYTECODE=1"
  )

  # ---- 步骤 1 ----
  step_start "建表与初始化检查 (flask init-db + 空库 stats)" "01-initdb"
  rm -f "$db" "$db-journal" "$db-wal" "$db-shm"
  echo "  门禁专用数据库: $db (不触碰 backend/instance/)"
  ( cd "$ROOT_DIR/backend" && "${app_env[@]}" "$PYTHON_BIN" -m flask --app wsgi init-db ) \
    >>"$LOG_PREFIX" 2>&1 || die "init-db 失败, 见日志(常见: DATABASE_URL 不可写、模型导入错误)"
  ( cd "$ROOT_DIR/backend" && "${app_env[@]}" "$PYTHON_BIN" -m flask --app wsgi stats ) \
    >>"$LOG_PREFIX" 2>&1 || die "应用无法加载(stats 失败), 见日志"
  grep -q "监测点 0 个 / 监测数据 0 条 / 超标记录 0 条" "$LOG_PREFIX" \
    || die "空库计数不为 0, init-db 未在干净库上执行"
  echo "  空库计数归零, 建表正常"
  step_ok

  # ---- 步骤 2 ----
  step_start "写入演示数据并做确定性校验" "02-seed"
  ( cd "$ROOT_DIR/backend" && "${app_env[@]}" "$PYTHON_BIN" -m flask --app wsgi seed ) \
    >>"$LOG_PREFIX" 2>&1 || die "seed 失败, 见日志"
  ( cd "$ROOT_DIR/backend" && "${app_env[@]}" \
      "$PYTHON_BIN" "$SCRIPT_DIR/verify_seed.py" --app wsgi ) 2>&1 | tee -a "$LOG_PREFIX"
  [[ ${PIPESTATUS[0]} -eq 0 ]] || \
    die "演示数据与预期(8 站/1200 数据/52 超标及分布)不符, 检查 seed.py / domain 规则改动"
  step_ok

  # ---- 步骤 3 ----
  step_start "后端测试 (pytest 全量, 内存 SQLite 隔离)" "03-pytest"
  ( cd "$ROOT_DIR/backend" && env "PYTHONPATH=$ROOT_DIR/backend" "PYTHONDONTWRITEBYTECODE=1" \
      "$PYTHON_BIN" -m pytest ) 2>&1 | tee -a "$LOG_PREFIX"
  [[ ${PIPESTATUS[0]} -eq 0 ]] || \
    die "按日志修复失败用例后重跑: cd backend && python -m pytest"
  step_ok

  # ---- 步骤 4 ----
  step_start "前端生产构建 (vite build)" "04-build"
  rm -rf "$FRONTEND_WORK/dist"
  ( cd "$FRONTEND_WORK" && npm run build ) 2>&1 | tee -a "$LOG_PREFIX"
  [[ ${PIPESTATUS[0]} -eq 0 ]] || \
    die "构建失败, 见日志中 vite/rollup 报错(语法错误/导入缺失/类型问题)"
  [[ -f "$FRONTEND_WORK/dist/index.html" && -d "$FRONTEND_WORK/dist/assets" ]] \
    || die "构建完成但缺少 dist/index.html 或 dist/assets"
  echo "  构建产物: $FRONTEND_WORK/dist"
  step_ok

  # ---- 步骤 5 ----
  step_start "本地启动后端 + 前端(preview 构建产物), 等待健康" "05-serve"
  # 内联启动 Flask 并显式关闭 reloader(run.py 的 debug reloader 会派生子进程, 干扰回收)
  env "DATABASE_URL=sqlite:///$db" "FLASK_ENV=development" \
    "AUTO_INIT_DB=false" "AUTO_SEED=false" "PORT=$LOCAL_BACKEND_PORT" \
    "PYTHONPATH=$ROOT_DIR/backend" "PYTHONDONTWRITEBYTECODE=1" \
    "$PYTHON_BIN" -c '
import os
from app import create_app
app = create_app(os.getenv("FLASK_ENV"))
app.run(host="127.0.0.1", port=int(os.environ["PORT"]),
        debug=False, use_reloader=False)
' >>"$WORK_DIR/logs/05-backend-run.log" 2>&1 &
  echo "$!" >"$WORK_DIR/backend.pid"

  # preview 需要 preview.proxy(vite 7 支持); strictPort 保证端口不符即失败
  cat >"$FRONTEND_WORK/vite.gate.config.js" <<EOF
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
export default defineConfig({
  plugins: [react()],
  preview: {
    host: '127.0.0.1',
    port: $LOCAL_FRONTEND_PORT,
    strictPort: true,
    proxy: { '/api': { target: 'http://127.0.0.1:$LOCAL_BACKEND_PORT', changeOrigin: true } }
  }
})
EOF
  ( cd "$FRONTEND_WORK" && exec npx vite preview --config vite.gate.config.js ) \
    >>"$WORK_DIR/logs/05-frontend-run.log" 2>&1 &
  echo "$!" >"$WORK_DIR/frontend.pid"

  wait_http "http://127.0.0.1:$LOCAL_BACKEND_PORT/api/meta/health" 40 "后端" || {
    die "后端未就绪, 见 logs/05-backend-run.log(端口/依赖/数据库问题)"
  }
  wait_http "http://127.0.0.1:$LOCAL_FRONTEND_PORT/" 40 "前端" || {
    die "前端未就绪, 见 logs/05-frontend-run.log"
  }
  step_ok

  # ---- 步骤 6 ----
  step_start "关键页面冒烟 (5 业务页 + SPA 回退 + /api 代理链路)" "06-smoke"
  "$PYTHON_BIN" "$SCRIPT_DIR/smoke_check.py" \
    --frontend "http://127.0.0.1:$LOCAL_FRONTEND_PORT" 2>&1 | tee -a "$LOG_PREFIX"
  [[ ${PIPESTATUS[0]} -eq 0 ]] || die "冒烟失败: 按上方 [FAIL] 项检查对应页面/接口"
  step_ok
}

# =============================================================================
# 容器模式
# =============================================================================
compose() {
  docker compose -p "$DOCKER_PROJECT" \
    -f "$ROOT_DIR/docker-compose.yml" \
    -f "$WORK_DIR/docker-compose.gate.yml" "$@"
}

run_docker() {
  # 门禁专用覆盖:
  #  - 独立镜像 tag / 容器名, 绝不覆盖或干扰默认 air-monitor 栈
  #  - 独立宿主端口
  #  - SEED_DEMO=false: 建表与 seed 由步骤 1/2 显式执行并校验
  #  - 把门禁脚本只读挂入 backend, 供一次性容器复用
  cat >"$WORK_DIR/docker-compose.gate.yml" <<EOF
services:
  backend:
    image: ${DOCKER_PROJECT}-backend:latest
    container_name: airqgate-backend
    environment:
      SEED_DEMO: "false"
      AUTO_INIT_DB: "false"
    ports:
      - "$DOCKER_BACKEND_PORT:5000"
    volumes:
      - air-monitor-data:/data
      - $SCRIPT_DIR:/gate:ro
  frontend:
    image: ${DOCKER_PROJECT}-frontend:latest
    container_name: airqgate-frontend
    ports:
      - "$DOCKER_FRONTEND_PORT:80"
EOF

  # ---- 准备(不计数): 构建 backend 镜像 ----
  phase_start "构建后端镜像 (docker build)" "00-backend-image"
  compose build backend >>"$LOG_PREFIX" 2>&1 || \
    die "后端镜像构建失败, 见日志(多为依赖下载问题, 重跑即可)"
  echo "  ${DOCKER_PROJECT}-backend:latest 就绪"

  # ---- 步骤 1 ----
  step_start "建表与初始化检查 (一次性容器, 独立项目卷)" "01-initdb"
  compose run --rm --no-deps --entrypoint sh backend -c \
    "python -m flask --app wsgi init-db && python -m flask --app wsgi stats" \
    >>"$LOG_PREFIX" 2>&1 || die "容器内 init-db 失败, 见日志"
  grep -q "监测点 0 个 / 监测数据 0 条 / 超标记录 0 条" "$LOG_PREFIX" \
    || die "容器内空库计数不为 0, 初始化异常"
  echo "  容器内空库建表正常"
  step_ok

  # ---- 步骤 2 ----
  step_start "写入演示数据并校验 (确定性断言)" "02-seed"
  compose run --rm --no-deps --entrypoint sh backend -c \
    "python -m flask --app wsgi seed && python /gate/verify_seed.py --app wsgi" \
    >>"$LOG_PREFIX" 2>&1 || \
    die "容器内 seed/演示数据校验失败, 见日志; 卷 air-monitor-data 随门禁清理"
  step_ok

  # ---- 步骤 3 ----
  step_start "后端测试 (容器内 pytest 全量, 内存 SQLite)" "03-pytest"
  # 镜像以非 root appuser 运行, pytest 装到用户目录(系统 site-packages 不可写)。
  # backend/.dockerignore 排除了 tests/(不进交付镜像), 这里一次性只读挂载进容器,
  # 不修改镜像与 .dockerignore。
  compose run --rm --no-deps \
    -v "$ROOT_DIR/backend/tests:/app/tests:ro" \
    -e PYTHONDONTWRITEBYTECODE=1 \
    --entrypoint sh backend -c \
    "pip install --user -q --no-cache-dir pytest==8.3.2 && cd /app && python -m pytest -p no:cacheprovider" \
    2>&1 | tee -a "$LOG_PREFIX"
  [[ ${PIPESTATUS[0]} -eq 0 ]] || die "容器内 pytest 失败, 按日志修复用例"
  step_ok

  # ---- 步骤 4 ----
  step_start "前端构建 (镜像内多阶段 vite build) 并校验产物" "04-frontend-build"
  compose build frontend 2>&1 | tee -a "$LOG_PREFIX"
  [[ ${PIPESTATUS[0]} -eq 0 ]] || \
    die "前端镜像构建失败, vite build 报错见日志(语法错误/导入缺失等)"
  docker run --rm --entrypoint sh "${DOCKER_PROJECT}-frontend:latest" -c \
    "test -f /usr/share/nginx/html/index.html && test -d /usr/share/nginx/html/assets" \
    >>"$LOG_PREFIX" 2>&1 || die "前端镜像缺少 dist 产物(index.html/assets)"
  echo "  ${DOCKER_PROJECT}-frontend:latest 构建产物 index.html + assets/ 就位"
  step_ok

  # ---- 步骤 5 ----
  step_start "docker compose 启动, 等待全部服务健康" "05-up"
  compose up -d >>"$LOG_PREFIX" 2>&1 || die "compose up 失败, 见日志"

  local waited=0 healthy=""
  echo "  等待 backend healthcheck=healthy ..."
  while (( waited < 100 )); do
    healthy="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
      airqgate-backend 2>/dev/null | tr -d '[:space:]' || true)"
    [[ "$healthy" == "healthy" ]] && break
    if [[ "$healthy" == "unhealthy" ]]; then
      docker logs airqgate-backend >>"$LOG_PREFIX" 2>&1 || true
      die "backend healthcheck 已为 unhealthy, 见日志(docker logs airqgate-backend)"
    fi
    sleep 2
    waited=$((waited + 2))
  done
  [[ "$healthy" == "healthy" ]] || {
    docker logs airqgate-backend >>"$LOG_PREFIX" 2>&1 || true
    die "backend 在 100s 内未变 healthy, 见日志(docker logs airqgate-backend)"
  }
  echo "  backend healthy (${waited}s)"

  wait_http "http://127.0.0.1:$DOCKER_FRONTEND_PORT/healthz" 30 "frontend(/healthz)" || {
    docker logs airqgate-frontend >>"$LOG_PREFIX" 2>&1 || true
    die "frontend /healthz 不可用, 见日志(docker logs airqgate-frontend)"
  }
  wait_http "http://127.0.0.1:$DOCKER_BACKEND_PORT/api/meta/health" 15 "backend(宿主直连)" || \
    die "backend 健康接口经宿主端口不可达, 端口映射可能异常"
  compose ps
  step_ok

  # ---- 步骤 6 ----
  step_start "关键页面冒烟 (nginx 托管 + /api 反代端到端) + HTTP 数据复核" "06-smoke"
  python3 "$SCRIPT_DIR/verify_seed.py" --url "http://127.0.0.1:$DOCKER_BACKEND_PORT" \
    2>&1 | tee -a "$LOG_PREFIX"
  [[ ${PIPESTATUS[0]} -eq 0 ]] || die "运行栈 HTTP 演示数据复核失败, 数据与启动前不一致"

  python3 "$SCRIPT_DIR/smoke_check.py" \
    --frontend "http://127.0.0.1:$DOCKER_FRONTEND_PORT" \
    --backend "http://127.0.0.1:$DOCKER_BACKEND_PORT" 2>&1 | tee -a "$LOG_PREFIX"
  [[ ${PIPESTATUS[0]} -eq 0 ]] || die "冒烟失败: 按上方 [FAIL] 项检查 nginx 代理/后端接口"
  step_ok
}

# =============================================================================
main() {
  MODE="${1:-}"
  case "$MODE" in
    local|docker) ;;
    *)
      cat <<USAGE
用法: scripts/quality-gate/gate.sh <local|docker>

  local   本地方式: 隔离 venv + 门禁专用 SQLite + Vite preview(构建产物), 无需 Docker
  docker  容器方式: docker compose 独立项目/镜像/卷, 等全部健康后冒烟

环境变量:
  GATE_BACKEND_PORT / GATE_FRONTEND_PORT                 本地门禁端口 (默认 5055/5188)
  GATE_DOCKER_BACKEND_PORT / GATE_DOCKER_FRONTEND_PORT   容器宿主端口 (默认 5090/8098)
  KEEP_WORKDIR=1                                         保留临时工作目录便于排查
USAGE
      exit 2
      ;;
  esac

  preflight

  if [[ "$MODE" == "local" ]]; then
    phase_start "准备隔离运行环境 (venv + 前端依赖)" "00-env"
    ensure_python_env
    ensure_frontend_env
    run_local
  else
    run_docker
  fi
}

main "$@"
