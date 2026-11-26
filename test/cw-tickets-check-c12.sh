#!/usr/bin/env bash
# cw-tickets-check.sh C12（交付对账机检）的脱机回归
#
# 用法: bash test/cw-tickets-check-c12.sh
# 退出码: 0 = 全部用例符合预期；1 = 有反例没被拦（门禁假绿）
#
# 为什么要有它: C12 的判据是「表头/状态/功能点列」的形态黑名单，写成脚本就得证明
# 真能拦住「阶段进度汇报冒充交付对账」与「拿 PR 号当验收语言」——否则它和没写一样。
# 全程 stub gh + 临时仓，不碰真实 GitHub 与真实工作区。
set -euo pipefail

UPSTREAM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
BIN="$TMP/bin"
CHANGE="feat-x"
mkdir -p "$REPO/scripts" "$REPO/openspec/changes/$CHANGE" "$BIN"

cp "$UPSTREAM/scripts/cw-tickets-check.sh" "$REPO/scripts/"
cat > "$REPO/.change-workflow.conf" <<'CONF'
# 只开 C12；C11 留空 → 跳过（本测试不覆盖输入对账）
INPUT_ALIGNMENT_SINCE=""
DELIVERY_ALIGNMENT_SINCE="2026-11-26"
CONF
cat > "$REPO/openspec/changes/$CHANGE/tasks.md" <<'MD'
- [x] 1.1 做点什么
MD

# ---- stub gh：list 固定一张票，view 读当前 fixture -------------------------
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "issue list") cat "$GH_FIXTURE/list.json" ;;
  "issue view") cat "$GH_FIXTURE/view.json" ;;
  *) echo "stub gh: 未预期调用 $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$BIN/gh"

mkdir -p "$TMP/fx"
cat > "$TMP/fx/list.json" <<JSON
[{"number": 101, "title": "[change=$CHANGE/1.1] 做点什么", "body": "**Parent**: #100"}]
JSON

# fixture markdown → gh issue view 的 JSON（正文放评论里，贴近回填留档形态）
write_view() {
  python3 - "$1" > "$TMP/fx/view.json" <<'PY'
import json, sys
print(json.dumps({
    "body": "",
    "comments": [{"body": open(sys.argv[1]).read()}],
    "createdAt": "2026-11-27T00:00:00Z",
}))
PY
}

FAIL=0
expect() { run_case "$@" || FAIL=1; }

run_case() { # $1=用例名 $2=markdown $3=期望退出码 $4=期望输出子串
  printf '%s\n' "$2" > "$TMP/case.md"
  write_view "$TMP/case.md"
  local out rc=0
  out="$(GH_FIXTURE="$TMP/fx" PATH="$BIN:$PATH" \
    bash "$REPO/scripts/cw-tickets-check.sh" --change "$CHANGE" --live 2>&1)" || rc=$?
  if [[ "$rc" != "$3" ]]; then
    echo "❌ $1: 退出码 $rc，期望 $3" >&2
    printf '%s\n' "$out" >&2
    return 1
  fi
  if [[ -n "$4" && "$out" != *"$4"* ]]; then
    echo "❌ $1: 输出缺「$4」" >&2
    printf '%s\n' "$out" >&2
    return 1
  fi
  echo "✅ $1"
}

GOOD_TABLE='## 交付对账

| # | 功能模块 | 交付功能点（新增 / 调整 / 优化） | 状态 |
| --- | --- | --- | --- |
| 1 | 页签条 | 页签宽度改为弹性收缩，窗格变小时标题不再被裁切 | 已交付 |
| 2 | 徽标 | —— | 未交付（暂缓：等下一轮对账定形态） |
| 3 | 设置面板 | 字体候选列表改为中文名优先排序 | 超出对账（请裁决：保留还是退票） |'

expect "合规表通过" "$GOOD_TABLE" 0 "交付对账表结构合规"
expect "显式豁免通过" "交付对账豁免: 纯基建 change，无用户可见功能点" 0 "已显式豁免交付对账"
expect "豁免缺理由被拦" "交付对账豁免:" 1 "交付对账豁免\` 缺理由"

# 反例 1：阶段进度汇报冒充交付对账（表头三列、含「阶段」）
expect "阶段进度表冒充被拦" '## 交付对账

| 阶段 | 完成动作 | 产出物编号 |
| --- | --- | --- |
| G0 拆票 | 需求拆为 8 张可开工票 | #1559–#1566 |
| G0 规划制品 | proposal / design / tasks 落库 | PR #1567 |' 1 "表头不合格"

# 反例 2：功能点列写引用（PR 号 / 文件 / 门禁名）
expect "功能点写 PR 号被拦" '## 交付对账

| # | 功能模块 | 交付功能点（新增 / 调整 / 优化） | 状态 |
| --- | --- | --- | --- |
| 1 | 工具包 | PR #1567 合并 | 已交付 |' 1 "功能点列写了引用"

# 反例 3：状态不是三值之一
expect "状态非三值被拦" '## 交付对账

| # | 功能模块 | 交付功能点（新增 / 调整 / 优化） | 状态 |
| --- | --- | --- | --- |
| 1 | 页签条 | 页签宽度改为弹性收缩 | 完成 |' 1 "状态列不合格"

# 反例 4：没有交付对账段，也没有豁免
expect "缺段被拦" '## 输入对账

| # | 原文 | 处置 |
| --- | --- | --- |
| 1 | 页签太窄 | 做票 |' 1 "缺 \`## 交付对账\` 段"

if [[ $FAIL -ne 0 ]]; then
  echo "❌ 有反例没被拦住（门禁假绿）" >&2
  exit 1
fi
echo "✅ C12 全部用例通过"
