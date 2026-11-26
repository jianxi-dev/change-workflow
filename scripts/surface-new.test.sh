#!/usr/bin/env bash
# =============================================================================
# surface-new.test.sh —— surface-new.sh 的自检入口（CI-less 形态）
#
# 用法: bash scripts/surface-new.test.sh
#
# 直接转调 `surface-new.sh --self-test`（内嵌固定样本，不依赖消费仓测试基建）。
# 退出码与 --self-test 一致: 0 = 全通过；1 = 有失败。
#
# 为什么是薄包装而不是第二套实现: 判据只该有一份真相源。测试入口与脚手架
# 同目录、同姿态（与 cw-data-surface.sh selftest 一致），CI 可直接跑本文件。
# =============================================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SELF_DIR/surface-new.sh" --self-test
