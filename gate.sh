#!/usr/bin/env bash
# 统一质量门禁便捷入口, 等价于 scripts/quality-gate/gate.sh
# 用法: ./gate.sh local | docker
set -euo pipefail
exec "$(dirname "$0")/scripts/quality-gate/gate.sh" "$@"
