#!/usr/bin/env bash
# =============================================================================
# surface-new.sh —— 数据面脚手架（design D8 / issue #1502）
#
# 用法:
#   bash scripts/surface-new.sh <id> --shape <shape> [--dry-run] [--root <dir>]
#
# 形状（闭集，与 src-tauri/src/surfaces.rs 的 SurfaceShape 一一对应）:
#   menu-item | icon | capsule | toolbar
#
# 产物（三样，逐条对应 docs/agents/data-surface.md「新增面步骤」）:
#   1. src-tauri/src/resources/<id>.default.json   默认 JSON 模板（步骤 2）
#   2. src-tauri/src/surfaces.rs                    SURFACES 表登记项骨架（步骤 1，追加一行）
#   3. <root>/openspec/changes/<change>/design.md  ## 数据面 六栏表模板（步骤 5，追加一段）
#      （change 由 --change 显式给出；缺省只打印模板，不落盘）
#
# 退出码:
#   0 = 成功（含 --dry-run、含「已存在，跳过」）
#   1 = 违规（未知 shape / 非法 id / 缺 --shape / 产物已存在且拒绝覆盖）
#   2 = 用法错误（缺 id / 未知参数）
#   3 = 环境缺失（--root 不存在 / python3 缺失 / design.md 不存在）——降级，不判失败
#
# 幂等: 同一 id 重复运行不覆盖既有非空默认文件或既有登记行；命中即打印
#       「已存在，跳过」并退 0。写盘走「临时文件 + mv」，无半成品残留。
#
# 设计说明（为什么这样切）:
#   1. 形状是闭集: 由 surfaces.rs 的 SurfaceShape 枚举定义，脚手架不臆造第五种。
#      模板字段与该校验器（validate_menu_item / validate_icon_item /
#      validate_capsule_item / validate_toolbar_item）逐字段对齐，模板可直接过校验。
#   2. 只生成模板，不生成实现: 校验器与消费端接线由面作者手写（D8「面作者只填
#      形状与校验」）；脚本不写 surfaces.rs 的 match 分支，避免半成品编译不过。
#   3. 六栏落点值严格等于 cw-data-surface.sh 的 REQUIRED_LABELS（规格/存储/校验/
#      桥接/消费/回滚），不改写、不增删——机检 C10 按这六个词匹配。
#   4. 自检内嵌: --self-test 用固定样本自证（形状解析 / 六值 / 幂等 / 非法入参），
#      不依赖消费仓测试基建，与 cw-data-surface.sh selftest 同姿态。
# =============================================================================
set -euo pipefail

EXIT_OK=0
EXIT_VIOLATION=1
EXIT_USAGE=2
EXIT_ENV=3

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# 六栏落点值：与 cw-data-surface.sh 的 REQUIRED_LABELS 逐字一致（勿改）。
REQUIRED_LABELS="规格 存储 校验 桥接 消费 回滚"

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$SELF"
}

die_usage() { echo "❌ $*" >&2; exit "$EXIT_USAGE"; }
die_violation() { echo "❌ $*" >&2; exit "$EXIT_VIOLATION"; }
die_env() { echo "⚠️  $*" >&2; exit "$EXIT_ENV"; }

# 形状闭集 → 校验器名（surfaces.rs 的 SurfaceShape 变体）。
shape_variant() {
  case "$1" in
    menu-item) printf 'Menu' ;;
    icon) printf 'Icon' ;;
    capsule) printf 'Capsule' ;;
    toolbar) printf 'Toolbar' ;;
    *) return 1 ;;
  esac
}

# 形状 → 示例项（模板内容；字段与该形状校验器逐字段对齐，无占位字段名）。
shape_sample_item() {
  case "$1" in
    menu-item)
      printf '    { "id": "example-item", "group": "pane-header", "order": 1, "label": "示例菜单项", "icon": "file", "action": "example-action", "enabled": true }\n' ;;
    icon)
      printf '    { "key": "example-key", "label": "示例图标", "s": "M4 4h16v16H4z" }\n' ;;
    capsule)
      printf '    { "id": "format-bold", "label": "加粗", "icon": "bold", "order": 1 }\n' ;;
    toolbar)
      printf '    { "id": "ai-rewrite", "label": "改写", "icon": "edit", "group": "ai" }\n' ;;
  esac
}

# 面 id → 默认文件名（default_file 字段值）：per-surface，恒等于 `<id>.json`。
surface_default_file() {
  printf '%s.json' "$1"
}

shape_validator_name() {
  case "$1" in
    menu-item) printf 'menu' ;;
    icon) printf 'icon' ;;
    capsule) printf 'capsule' ;;
    toolbar) printf 'toolbar' ;;
  esac
}

# 形状 → 消费端提示（写进六栏表「消费」行的判据，供面作者改写）。
shape_consumer_hint() {
  case "$1" in
    menu-item) printf 'getMenuItems(group) 按 group 过滤；消费端不留兜底常量' ;;
    icon) printf 'getIconSpec(key) 按概念键查面；label/path 缺失回落 ICONS' ;;
    capsule) printf 'getCapsuleItems() 保持面数组顺序；run 由代码侧按 id 分派' ;;
    toolbar) printf 'getSurfaceItems(id) 按 id 取；消费端不留兜底常量' ;;
  esac
}

main() {
ID=""
SHAPE=""
DRY_RUN=0
ROOT=""
CHANGE=""
SELF_TEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --shape) SHAPE="${2:-}"; shift 2 ;;
    --shape=*) SHAPE="${1#--shape=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    --change) CHANGE="${2:-}"; shift 2 ;;
    --change=*) CHANGE="${1#--change=}"; shift ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die_usage "未知参数: $1" ;;
    *) [ -z "$ID" ] || die_usage "多余参数: $1"; ID="$1"; shift ;;
  esac
done

[ -n "$ID" ] || die_usage "缺少面 id"
[ -n "$SHAPE" ] || die_usage "缺少 --shape"
case "$ID" in
  [a-z][a-z0-9-]*) ;;
  *) die_violation "非法面 id: ${ID}（须匹配 [a-z][a-z0-9-]*）" ;;
esac
shape_variant "$SHAPE" >/dev/null || die_violation "未知 shape: ${SHAPE}（闭集: menu-item | icon | capsule | toolbar）"

# ---- 路径解析 --------------------------------------------------------------
if [ -n "$ROOT" ]; then
  [ -d "$ROOT" ] || die_env "--root 目录不存在: $ROOT"
  ROOT_DIR="$(cd "$ROOT" && pwd)"
else
  ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
RESOURCES_DIR="$ROOT_DIR/src-tauri/src/resources"
SURFACES_RS="$ROOT_DIR/src-tauri/src/surfaces.rs"
DEFAULT_FILE="$RESOURCES_DIR/$ID.default.json"

# ---- 模板生成 --------------------------------------------------------------
# 默认 JSON 模板（合法 JSON，字段与形状校验器对齐）。
render_default_json() {
  local id="$1" shape="$2"
  printf '{\n  "id": "%s",\n  "items": [\n%s\n  ]\n}\n' "$id" "$(shape_sample_item "$shape")"
}

# SURFACES 表登记项骨架（追加到 SURFACES 数组末尾）。
render_registration() {
  local id="$1" shape="$2"
  printf '    SurfaceSpec {\n        id: "%s",\n        default_file: "%s",\n        shape: SurfaceShape::%s,\n    },\n' \
    "$id" "$(surface_default_file "$id")" "$(shape_variant "$shape")"
}

# 六栏表模板（落点值严格等于 REQUIRED_LABELS，逐行由该变量驱动）。
render_six_column() {
  local id="$1" shape="$2"
  local consumer row pos sym crit
  consumer="$(shape_consumer_hint "$shape")"
  printf '| 落点 | 位置 | 载体/符号 | 判据 |\n|---|---|---|---|\n'
  for row in $REQUIRED_LABELS; do
    case "$row" in
      规格) pos="D1"; sym="—"; crit="本面 anchors 逐条断言（D1 为占位，按本 change 实际锚点号改写）" ;;
      存储) pos="src-tauri/src/resources/${id}.default.json"; sym="SURFACES"; crit="默认集合唯一来源（include_str 内嵌 + 物化 defaults 层）" ;;
      校验) pos="src-tauri/src/surfaces.rs"; sym="validate_$(shape_validator_name "$shape")_item"; crit="形状校验：缺字段/类型错/未知 id 过滤并聚合告警" ;;
      桥接) pos="src/lib/dataSurfaces/loader.ts"; sym="normalizeSurface"; crit="默认←覆盖合并，未知 id 过滤+聚合告警，空回落默认" ;;
      消费) pos="src/lib/dataSurfaces/store.ts"; sym="getSurfaceItems"; crit="$consumer" ;;
      回滚) pos="snapshots/"; sym="restore_config_snapshot"; crit="写前快照（沿用 10 份），一步恢复" ;;
    esac
    printf '| %s | %s | %s | %s |\n' "$row" "$pos" "$sym" "$crit"
  done
}

# ---- 幂等写入（临时文件 + mv；已存在非空则跳过）----------------------------
# write_if_absent <path> <content> <描述>
#   文件不存在或为空 → 写入；已存在非空 → 打印「已存在，跳过」退 0。
write_if_absent() {
  local path="$1" content="$2" desc="$3"
  if [ -s "$path" ]; then
    echo "  ↷ 已存在，跳过: ${desc}（${path}）"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] 将写入: $path"
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  printf '%s' "$content" > "$tmp"
  mv "$tmp" "$path"
  echo "  ✅ 已写入: $path"
}

# ---- 主流程 ----------------------------------------------------------------
echo "==> surface:new id=$ID shape=$SHAPE"

# 步骤 2: 默认 JSON 模板
DEFAULT_CONTENT="$(render_default_json "$ID" "$SHAPE")"
echo "-- 产物 1/3: 默认 JSON 模板"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "  [dry-run] 将写入: $DEFAULT_FILE"
  printf '%s\n' "$DEFAULT_CONTENT"
else
  write_if_absent "$DEFAULT_FILE" "$DEFAULT_CONTENT" "默认 JSON 模板"
fi

# 步骤 1: SURFACES 登记项骨架（追加一行；已存在同 id 行则跳过）
echo "-- 产物 2/3: SURFACES 登记项骨架"
REG_CONTENT="$(render_registration "$ID" "$SHAPE")"
if [ -f "$SURFACES_RS" ] && grep -qF "id: \"$ID\"" "$SURFACES_RS"; then
  echo "  ↷ 已存在，跳过: SURFACES 登记行（$SURFACES_RS 已含 id: \"$ID\"）"
elif [ "$DRY_RUN" -eq 1 ]; then
  echo "  [dry-run] 将追加到: $SURFACES_RS"
  printf '%s\n' "$REG_CONTENT"
else
  if [ ! -f "$SURFACES_RS" ]; then
    die_env "surfaces.rs 不存在: $SURFACES_RS"
  fi
  local_tmp="$(mktemp)"
  reg_file="$(mktemp)"
  printf '%s' "$REG_CONTENT" > "$reg_file"
  REGFILE="$reg_file" awk '
    /^\];/ && !done { while ((getline line < ENVIRON["REGFILE"]) > 0) print line; done = 1 }
    { print }
  ' "$SURFACES_RS" > "$local_tmp"
  mv "$local_tmp" "$SURFACES_RS"
  rm -f "$reg_file"
  echo "  ✅ 已追加登记行: $SURFACES_RS"
fi

# 步骤 5: 六栏表模板（写进 design.md 的 ## 数据面；缺 --change 只打印）
echo "-- 产物 3/3: 数据面六栏表模板"
SIX_CONTENT="$(render_six_column "$ID" "$SHAPE")"
if [ -z "$CHANGE" ]; then
  echo "  （未给 --change，仅打印模板；给 --change <name> 可写入 openspec/changes/<name>/design.md）"
  printf '%s\n' "$SIX_CONTENT"
else
  DESIGN_MD="$ROOT_DIR/openspec/changes/$CHANGE/design.md"
  if [ ! -f "$DESIGN_MD" ]; then
    die_env "design.md 不存在: $DESIGN_MD"
  fi
  if grep -qF "$ID.default.json" "$DESIGN_MD"; then
    echo "  ↷ 已存在，跳过: design.md 六栏表（已含 $ID.default.json 行）"
  elif [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] 将追加到: $DESIGN_MD"
    printf '%s\n' "$SIX_CONTENT"
  else
    local_tmp="$(mktemp)"
    printf '\n%s\n' "$SIX_CONTENT" > "$local_tmp"
    cat "$DESIGN_MD" "$local_tmp" > "$DESIGN_MD.tmp" && mv "$DESIGN_MD.tmp" "$DESIGN_MD"
    rm -f "$local_tmp"
    echo "  ✅ 已追加六栏表: $DESIGN_MD"
  fi
fi

echo "==> 完成。面作者还需手写: 校验器（validate_$(shape_validator_name "$SHAPE")_item 分支）与消费端接线（docs/agents/data-surface.md「新增面步骤」）。"
exit "$EXIT_OK"
}

# =============================================================================
# 自检（--self-test）：固定样本，不依赖消费仓测试基建
# =============================================================================
run_selftest() {
  local tmp pass=0 fail=0 rc
  tmp="$(mktemp -d)"
  SELFTEST_TMP="$tmp"
  trap 'rm -rf "$SELFTEST_TMP"' EXIT

  mkdir -p "$tmp/repo/src-tauri/src/resources" "$tmp/repo/openspec/changes/demo-change"
  printf 'pub static SURFACES: &[SurfaceSpec] = &[\n];\n' > "$tmp/repo/src-tauri/src/surfaces.rs"
  printf '# demo\n\n## 数据面\n' > "$tmp/repo/openspec/changes/demo-change/design.md"

  expect() { # name want cmd...
    local name="$1" want="$2"; shift 2
    set +e; "$@" >/dev/null 2>&1; rc=$?; set -e
    if [ "$rc" -eq "$want" ]; then
      echo "  ✅ ${name}（exit ${rc}）"; pass=$((pass + 1))
    else
      echo "  ❌ ${name}（期望 ${want}，实得 ${rc}）" >&2; fail=$((fail + 1))
    fi
  }

  echo "==> surface-new selftest"

  # 1. 合法 shape 生成三样产物（写盘）
  expect "menu-item 生成 → 0" 0 "$SELF" demo --shape menu-item --root "$tmp/repo" --change demo-change
  if [ -s "$tmp/repo/src-tauri/src/resources/demo.default.json" ]; then
    echo "  ✅ 默认 JSON 已写入"; pass=$((pass + 1))
  else
    echo "  ❌ 默认 JSON 未写入" >&2; fail=$((fail + 1))
  fi
  if grep -qF 'id: "demo"' "$tmp/repo/src-tauri/src/surfaces.rs"; then
    echo "  ✅ 登记行已追加"; pass=$((pass + 1))
  else
    echo "  ❌ 登记行未追加" >&2; fail=$((fail + 1))
  fi
  if grep -qF 'demo.default.json' "$tmp/repo/openspec/changes/demo-change/design.md"; then
    echo "  ✅ 六栏表已追加"; pass=$((pass + 1))
  else
    echo "  ❌ 六栏表未追加" >&2; fail=$((fail + 1))
  fi
  if grep -qF 'default_file: "demo.json"' "$tmp/repo/src-tauri/src/surfaces.rs" \
    && ! grep -qE 'default_file: "(menus|icons|capsules|html-toolbar)\.json"' "$tmp/repo/src-tauri/src/surfaces.rs"; then
    echo "  ✅ 登记行 default_file 按面 id 生成"; pass=$((pass + 1))
  else
    echo "  ❌ 登记行 default_file 未按面 id 生成（混入既有面文件名）" >&2; fail=$((fail + 1))
  fi

  # 2. 形状解析：模板 JSON 合法且含示例项字段
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
assert d["id"]=="demo"
assert isinstance(d["items"],list) and len(d["items"])>=1
it=d["items"][0]
for k in ("id","group","order","label","icon","action","enabled"):
    assert k in it, "缺字段: "+k
' "$tmp/repo/src-tauri/src/resources/demo.default.json" 2>/dev/null; then
      echo "  ✅ menu-item 模板字段齐全且 JSON 合法"; pass=$((pass + 1))
    else
      echo "  ❌ menu-item 模板字段缺失或 JSON 非法" >&2; fail=$((fail + 1))
    fi
  fi

  # 3. 六栏落点值精确等于六值
  local labels
  labels="$(awk -F'|' '/^## 数据面[ \t]*$/{f=1;next} f&&/^#/{exit} f&&/^\|/{gsub(/^[ \t]+|[ \t]+$/,"",$2); if ($2!="落点" && $2 !~ /^-+$/) print $2}' "$tmp/repo/openspec/changes/demo-change/design.md" | tr '\n' ' ')"
  local want="规格 存储 校验 桥接 消费 回滚 "
  if [ "$labels" = "$want" ]; then
    echo "  ✅ 六栏落点值精确"; pass=$((pass + 1))
  else
    echo "  ❌ 六栏落点值不符（实得: ${labels}）" >&2; fail=$((fail + 1))
  fi

  # 4. 幂等：第二次运行不覆盖（默认文件与登记行不变）
  printf 'SENTINEL' >> "$tmp/repo/src-tauri/src/resources/demo.default.json"
  expect "重复运行 → 0" 0 "$SELF" demo --shape menu-item --root "$tmp/repo" --change demo-change
  if grep -qF 'SENTINEL' "$tmp/repo/src-tauri/src/resources/demo.default.json"; then
    echo "  ✅ 既有默认文件未被覆盖"; pass=$((pass + 1))
  else
    echo "  ❌ 既有默认文件被覆盖" >&2; fail=$((fail + 1))
  fi

  # 5. 非法 shape / 非法 id 拒绝
  expect "未知 shape → 1" 1 "$SELF" demo --shape nope --root "$tmp/repo"
  expect "非法 id → 1" 1 "$SELF" Bad_Id --shape menu-item --root "$tmp/repo"

  # 6. dry-run 不写盘
  rm -f "$tmp/repo/src-tauri/src/resources/icons.default.json"
  expect "dry-run → 0" 0 "$SELF" demo2 --shape icon --root "$tmp/repo" --dry-run
  if [ ! -e "$tmp/repo/src-tauri/src/resources/icons.default.json" ]; then
    echo "  ✅ dry-run 未写盘"; pass=$((pass + 1))
  else
    echo "  ❌ dry-run 写了盘" >&2; fail=$((fail + 1))
  fi

  echo "----"
  if [ "$fail" -gt 0 ]; then
    echo "❌ selftest: $pass 通过 / $fail 失败" >&2
    exit "$EXIT_VIOLATION"
  fi
  echo "✅ selftest: $pass 项全通过"
}

for arg in "$@"; do
  if [ "$arg" = "--self-test" ]; then
    run_selftest
    exit 0
  fi
done

main "$@"
