#!/usr/bin/env bash
# =============================================================================
# change-workflow 消费仓滚动验证（发布前本地门禁；CI 跑不了，因为 CI 没有消费仓检出）
#
# 为什么存在：工具包改动的影响面只在「消费仓升级之后」才显形 —— 1.1.5 静默覆盖用户
# 定制、1.2.0 接管模式永不归一，都是从消费侧暴露的。发布前必须确认：把本工具包
# 当前 HEAD 装到每个消费仓**不会冲突**，且所有 LOCAL 哨兵仍被正确识别。
#
# 用法:
#   ./test/rollout-check.sh <消费仓目录> [<消费仓目录> ...]
#   CW_CONSUMERS="dirA dirB" ./test/rollout-check.sh
#
# 退出码: 0 全部干净；1 有冲突 / LOCAL 未被识别 / 覆盖数不符 / 环境错误
# 只读：内部走 update.sh --dry-run，不落盘。
# =============================================================================
set -euo pipefail

CW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0

ok() {
  local name="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✅ $name: $actual"; PASS=$((PASS + 1))
  else
    echo "  ❌ $name: 实际=$actual 期望=$expected"; FAIL=$((FAIL + 1))
  fi
}

CONSUMERS=()
if [[ "$#" -gt 0 ]]; then
  CONSUMERS=("$@")
elif [[ -n "${CW_CONSUMERS:-}" ]]; then
  # shellcheck disable=SC2206  # 空格分隔是 `CW_CONSUMERS` 的约定输入格式，此处需要分词
  CONSUMERS=(${CW_CONSUMERS})
else
  sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  echo "❌ 未指定消费仓：传入目录参数，或设 CW_CONSUMERS" >&2
  exit 1
fi

MANAGED_TOTAL="$(bash -c "source '$CW_ROOT/lib/render.sh'; cw_list_files" | wc -l | tr -d ' ')"
echo "工具包: ${CW_ROOT}（$(tr -d '[:space:]' < "$CW_ROOT/VERSION")）· 受管文件 ${MANAGED_TOTAL} 个"

for dir in "${CONSUMERS[@]}"; do
  echo ""
  echo "[$dir]"
  if [[ ! -d "$dir" ]]; then
    echo "  ❌ 目录不存在"; FAIL=$((FAIL + 1)); continue
  fi
  adir="$(cd "$dir" && pwd -P)"
  manifest="$adir/.change-workflow.manifest"
  if [[ ! -f "$manifest" ]]; then
    echo "  ❌ 缺 .change-workflow.manifest（不是 change-workflow 消费仓？）"; FAIL=$((FAIL + 1)); continue
  fi
  local_expected="$(grep -c '^LOCAL' "$manifest" || true)"

  out=""; rc=0
  out="$("$CW_ROOT/update.sh" --target "$adir" --dry-run 2>&1)" || rc=$?
  summary="$(printf '%s\n' "$out" | grep '更新完成' | tail -1 || true)"
  if [[ -z "$summary" ]]; then
    echo "  ❌ 未取到汇总行（update.sh 异常，退出码 ${rc}）"
    printf '%s\n' "$out" | tail -5
    FAIL=$((FAIL + 1)); continue
  fi
  echo "  $summary"
  updated="$(printf '%s' "$summary" | sed -n 's/.*更新 \([0-9][0-9]*\).*/\1/p')"
  added="$(printf '%s' "$summary" | sed -n 's/.*新增 \([0-9][0-9]*\).*/\1/p')"
  current="$(printf '%s' "$summary" | sed -n 's/.*已最新 \([0-9][0-9]*\).*/\1/p')"
  conflicts="$(printf '%s' "$summary" | sed -n 's/.*冲突 \([0-9][0-9]*\).*/\1/p')"
  kept="$(printf '%s' "$summary" | sed -n 's/.*本地保留 \([0-9][0-9]*\).*/\1/p')"

  ok "冲突为 0" "$conflicts" "0"
  ok "LOCAL 哨兵全部识别" "$kept" "$local_expected"
  ok "覆盖受管文件总数" "$((updated + added + current + conflicts + kept))" "$MANAGED_TOTAL"
done

echo ""
echo "=============================================="
echo " 消费仓 ${#CONSUMERS[@]} 个 · 通过 $PASS · 失败 $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  echo " ❌ 不可发布：升级会冲突或覆盖消费仓定制"
  echo "=============================================="
  exit 1
fi
echo " ✅ 全部消费仓升级无冲突、LOCAL 哨兵完整、覆盖数与受管清单一致"
echo "=============================================="
