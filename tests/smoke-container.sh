#!/usr/bin/env bash
# 宿主机驱动:在 Ubuntu 24.04 容器里模拟 WSL 环境完整跑 setup.sh(两遍,验证幂等)
# 用法: bash tests/smoke-container.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> 拉起 ubuntu:24.04 容器执行冒烟测试…"
docker run --rm \
    -v "$REPO:/kit-src:ro" \
    -e DEBIAN_FRONTEND=noninteractive \
    ubuntu:24.04 \
    bash /kit-src/tests/smoke-inner.sh
echo "==> 冒烟测试通过 ✅"
