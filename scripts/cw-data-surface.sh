#!/usr/bin/env bash
# =============================================================================
# cw-data-surface.sh —— 数据面落点机检（C10）
#
# 用法:
#   ./scripts/cw-data-surface.sh new     <change> [--dir <change目录>]
#   ./scripts/cw-data-surface.sh tickets <change> [--drafts <草稿目录>]
#   ./scripts/cw-data-surface.sh diff    <change>
#   ./scripts/cw-data-surface.sh signals <change>
#   ./scripts/cw-data-surface.sh pr      <基线ref>      # 缺陷线：diff(base..HEAD+未提交) 命中数据面路径 → 违规
#   ./scripts/cw-data-surface.sh selftest
#
# 规范: docs/agents/data-surface.md（六栏契约 / 触发信号 / 票面第 8 字段）
#
# 退出码（对齐 cw-evidence.sh / cw-conformance.sh）:
#   0 = 通过，或未命中数据面信号（打印 SKIP，不算失败）
#   1 = 契约违规（缺栏/占位符/覆盖不全/实现未落地/pr 命中数据面路径）
#   3 = 环境缺失（change 目录不存在、草稿目录不存在、基线 ref 无效）——降级，不判失败
#
# 设计说明（为什么是这三条子命令，而不是塞进 cw-tickets-check.sh）:
#   1. 分工: 父脚本管票形态（C1-C8），本脚本管「数据面这条链是否闭合」。
#      两者职责正交，混在一起会让 C2 六字段检查在非数据面票上误报。
#   2. 时点: new 在 G0 阶段二（propose 之后），tickets 在 G0-POST，diff 在 G1 出口。
#      三段分别对应「计划写了 / 有人负责 / 真的落地」三种失败。
#   3. 识别靠信号不靠意图: 路径 + 关键词双信号，命中任一即要求六栏。
#      误报成本 = 多填一张表；漏报成本 = 硬编码活过整个 change。
#   4. 脚本自带 selftest: 上游化时随脚本一起搬，不依赖消费仓测试基建。
# =============================================================================
set -euo pipefail

EXIT_OK=0
EXIT_VIOLATION=1
EXIT_ENV=3

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONF="$ROOT/.change-workflow.conf"

DEFAULT_PATHS="src-tauri/src/config.rs;src-tauri/src/extensions.rs;src/lib/extensions;src/lib/capabilities.ts;src/hooks/useConfig.ts;src/ui/icons.ts;src/editors/icons.ts;src/editors/orchestration/roulette.ts;src/editors/orchestration/roulette-view.ts;src/editors/orchestration/floating-toolbar.ts;src/editors/orchestration/horizontal-toolbar.ts;src/editors/orchestration/block-menu.ts;src/styles/tokens.css;src/components/SettingsView.tsx"
DEFAULT_KEYWORDS="可配置;数据文件;配置项;开关;白名单;主题色;图标;快捷键;轮盘;菜单项"

REQUIRED_LABELS="规格 存储 校验 桥接 消费 回滚"

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$SELF"
}

die_env() { echo "⚠️  $*" >&2; exit "$EXIT_ENV"; }
die_arg() { echo "❌ $*" >&2; exit 2; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# 与 pr-automation.sh / cw-update.sh 同语义的最小实现：只取字面值，不求值。
conf_get() {
  local key="$1" line v q rest
  [ -f "$CONF" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in \#*) continue ;; esac
    case "$line" in
      "$key"=*) v="${line#*=}" ;;
      *) continue ;;
    esac
    v="${v%$'\r'}"
    q="${v:0:1}"
    if [ "$q" = '"' ] || [ "$q" = "'" ]; then
      rest="${v#?}"
      case "$rest" in
        *"$q"*) v="${rest%%"$q"*}" ;;
        *) v="$rest" ;;
      esac
    else
      case "$v" in
        *" #"*) v="${v%%" #"*}" ;;
      esac
    fi
    trim "$v"
    return 0
  done < "$CONF"
  return 1
}

# bash 3.2 没有 `trap RETURN`；用全局清单 + EXIT 清理（路径无空格）。
TMPFILES=""
cleanup_tmp() {
  local f
  for f in $TMPFILES; do
    if [ -d "$f" ]; then rm -rf "$f"; else rm -f "$f"; fi
  done
}
trap cleanup_tmp EXIT
newtmp() {
  local f
  f="$(mktemp)"
  TMPFILES="$TMPFILES $f"
  printf '%s' "$f"
}

changedir() {
  local change="$1" override="${2:-}"
  if [ -n "$override" ]; then
    [ -d "$override" ] || die_env "change 目录不存在: $override"
    printf '%s' "$override"
    return 0
  fi
  [ -n "$change" ] || die_arg "缺少 change 名"
  if [ -d "$ROOT/openspec/changes/$change" ]; then
    printf '%s' "$ROOT/openspec/changes/$change"
  elif [ -d "$ROOT/openspec/changes/archive/$change" ]; then
    printf '%s' "$ROOT/openspec/changes/archive/$change"
  else
    die_env "找不到 change: ${change}（openspec/changes 与 archive 均无）"
  fi
}

# 信号：路径（含 basename）或关键词命中任一
has_signal() {
  local dir="$1" text p k paths keywords hit=0
  text="$(cat "$dir/design.md" "$dir/tasks.md" "$dir/proposal.md" 2>/dev/null || true)"
  [ -n "$text" ] || { echo 0; return 0; }
  paths="$(conf_get DATA_SURFACE_PATHS 2>/dev/null || printf '%s' "$DEFAULT_PATHS")"
  keywords="$(conf_get DATA_SURFACE_KEYWORDS 2>/dev/null || printf '%s' "$DEFAULT_KEYWORDS")"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$text" in *"$p"*) hit=1; break ;; esac
    case "$text" in *"$(basename "$p")"*) hit=1; break ;; esac
  done < <(printf '%s' "$paths" | tr ',;' '\n\n')
  if [ "$hit" -eq 0 ]; then
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      case "$text" in *"$k"*) hit=1; break ;; esac
    done < <(printf '%s' "$keywords" | tr ',;' '\n\n')
  fi
  echo "$hit"
}

# 解析 `## 数据面` 小节内的表格 → 落点<TAB>位置<TAB>载体<TAB>判据
extract_rows() {
  local f="$1" out="$2"
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function clean(s) { gsub(/\*|`/, "", s); return trim(s) }
    {
      line = $0
      if (!inb) {
        if (line ~ /^#+[ \t]*数据面[ \t]*$/) inb = 1
        next
      }
      if (line ~ /^#+[ \t]/) exit
      if (line ~ /^[ \t]*\|/) {
        n = split(line, a, "|")
        if (n < 6) next
        c1 = clean(a[2]); c2 = clean(a[3]); c3 = clean(a[4]); c4 = clean(a[5])
        if (c1 == "" || c1 ~ /^-+$/) next
        if (c1 == "落点") next
        printf "%s\t%s\t%s\t%s\n", c1, c2, c3, c4
      }
    }
  ' "$f" > "$out"
}

row_of() { # rows label -> line
  awk -F'\t' -v l="$2" '$1==l {print; exit}' "$1"
}

field_of() { # line n
  printf '%s' "$1" | awk -F'\t' -v n="$2" '{print $n}'
}

is_placeholder() {
  case "$1" in
    ""|TBD|tbd|TODO|todo|待定|待补|—|-) return 0 ;;
    *) return 1 ;;
  esac
}

check_new() {
  local dir="$1" change="$2" rows viol=0 label line pos sym crit
  rows="$(newtmp)"

  if ! grep -Eq '^#+[[:space:]]*数据面[[:space:]]*$' "$dir/design.md" 2>/dev/null; then
    echo "❌ design.md 缺「## 数据面」小节（信号已命中：本 change 触及可配置面）" >&2
    echo "   规范: docs/agents/data-surface.md 第三节" >&2
    exit "$EXIT_VIOLATION"
  fi

  extract_rows "$dir/design.md" "$rows"
  echo "==> 数据面六栏（new）: $change"

  for label in $REQUIRED_LABELS; do
    line="$(row_of "$rows" "$label")"
    if [ -z "$line" ]; then
      echo "  ❌ 缺落点行: $label" >&2
      viol=$((viol + 1))
      continue
    fi
    pos="$(field_of "$line" 2)"
    sym="$(field_of "$line" 3)"
    crit="$(field_of "$line" 4)"
    if is_placeholder "$pos"; then echo "  ❌ [$label] 位置为空或占位" >&2; viol=$((viol + 1)); fi
    if is_placeholder "$crit"; then echo "  ❌ [$label] 判据为空或占位" >&2; viol=$((viol + 1)); fi
    if [ "$label" != "规格" ] && is_placeholder "$sym"; then
      echo "  ❌ [$label] 载体/符号为空或占位" >&2; viol=$((viol + 1))
    fi
    case "$label" in
      规格)
        if ! printf '%s' "$pos" | grep -Eq 'design-system:§[0-9]+|(^|[^A-Za-z])D[0-9]+'; then
          echo "  ❌ [规格] 位置须为 design-system:§N 或 D<n>，当前: $pos" >&2
          viol=$((viol + 1))
        fi ;;
      回滚)
        if ! printf '%s' "$crit" | grep -Eq '快照|snapshot|确认卡|confirm|缺省|默认|回退|回落|fallback'; then
          echo "  ❌ [回滚] 判据须含 快照/确认卡/缺省回落 之一，当前: $crit" >&2
          viol=$((viol + 1))
        fi ;;
    esac
  done

  local extra
  extra="$(awk -F'\t' -v req="$REQUIRED_LABELS" '
    BEGIN { n = split(req, r, " "); for (i = 1; i <= n; i++) want[r[i]] = 1 }
    !($1 in want) { print $1 }
  ' "$rows" | sort -u | tr '\n' ' ')"
  if [ -n "$(trim "$extra")" ]; then
    echo "  ⚠️  未识别的落点行（已忽略）: $(trim "$extra")"
  fi

  if [ "$viol" -gt 0 ]; then
    echo "  ❌ $viol 项违规 —— 回 propose 补齐后再拆票" >&2
    exit "$EXIT_VIOLATION"
  fi
  echo "  ✅ 六栏齐全"
}

check_tickets() {
  local dir="$1" change="$2" drafts="$3" rows viol=0 f declared all="" label n=0
  if [ "$(has_signal "$dir")" != "1" ]; then
    echo "SKIP 数据面（未命中信号）: $change"
    return 0
  fi
  if [ ! -d "$drafts" ]; then
    die_env "草稿目录不存在: ${drafts}（已发布则跳过本步；请在拆票阶段运行）"
  fi
  rows="$(newtmp)"
  extract_rows "$dir/design.md" "$rows" 2>/dev/null || true

  echo "==> 数据面票面覆盖（tickets）: $change"
  for f in "$drafts"/*.md; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    declared="$(grep -E '^\*\*数据面\*\*[:：]' "$f" 2>/dev/null | head -1 || true)"
    if [ -z "$declared" ]; then
      echo "  ❌ $(basename "$f") 缺「**数据面**:」字段（无数据面写 无）" >&2
      viol=$((viol + 1))
      continue
    fi
    declared="${declared#*数据面}"
    declared="${declared#*:}"; declared="${declared#*：}"
    declared="${declared//,/ }"
    declared="${declared//，/ }"
    declared="${declared//、/ }"
    all="$all $declared"
  done
  for label in $REQUIRED_LABELS; do
    case " $all " in
      *" $label "*) ;;
      *) echo "  ❌ 无票认领落点: $label" >&2; viol=$((viol + 1)) ;;
    esac
  done
  if [ "$viol" -gt 0 ]; then
    echo "  ❌ $viol 项违规（$n 张草稿）—— 重切票补落点归属" >&2
    exit "$EXIT_VIOLATION"
  fi
  echo "  ✅ 六栏均被认领（$n 张草稿）"
}

check_diff() {
  local dir="$1" change="$2" rows viol=0 label line pos sym crit target
  if [ "$(has_signal "$dir")" != "1" ]; then
    echo "SKIP 数据面（未命中信号）: $change"
    return 0
  fi
  rows="$(newtmp)"
  extract_rows "$dir/design.md" "$rows" 2>/dev/null || true

  echo "==> 数据面落地（diff）: $change"
  for label in $REQUIRED_LABELS; do
    line="$(row_of "$rows" "$label")"
    if [ -z "$line" ]; then
      echo "  ❌ design.md 缺落点行: $label" >&2; viol=$((viol + 1)); continue
    fi
    pos="$(field_of "$line" 2)"; sym="$(field_of "$line" 3)"; crit="$(field_of "$line" 4)"
    case "$label" in
      规格|回滚) continue ;;
    esac
    target="$pos"
    case "$target" in /*) ;; *) target="$ROOT/$pos" ;; esac
    if [ ! -e "$target" ]; then
      echo "  ❌ [$label] 位置不存在: $pos" >&2; viol=$((viol + 1)); continue
    fi
    if [ -d "$target" ]; then
      if ! grep -rqF -- "$sym" "$target" 2>/dev/null; then
        echo "  ❌ [$label] 目录 $pos 内找不到符号: $sym" >&2; viol=$((viol + 1))
      fi
    elif ! grep -qF -- "$sym" "$target" 2>/dev/null; then
      echo "  ❌ [$label] $pos 内找不到符号: $sym" >&2; viol=$((viol + 1))
    fi
  done
  if [ "$viol" -gt 0 ]; then
    echo "  ❌ $viol 项未落地 —— 回修后可 commit" >&2
    exit "$EXIT_VIOLATION"
  fi
  echo "  ✅ 四栏文件与符号均已落地（规格/回滚按判据人工复核）"
}

# ---- pr: 缺陷线扫描（无 change 目录可挂信号，直接扫 diff 文件名单） ----------

check_pr() {
  local base="$1" paths p b f hit=0
  [ -n "$base" ] || die_arg "缺少基线 ref（如 main）"
  git rev-parse --verify "$base^{commit}" >/dev/null 2>&1 || die_env "基线不存在: $base"
  local mb
  mb="$(git merge-base "$base" HEAD 2>/dev/null)" || die_env "基线与 HEAD 无共同祖先: $base"
  paths="$(conf_get DATA_SURFACE_PATHS 2>/dev/null || printf '%s' "$DEFAULT_PATHS")"
  echo "==> 数据面 PR 扫描（$base..HEAD，含未提交改动）"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      b="$(basename "$p")"
      case "$f" in
        "$p" | "*/$b")
          echo "  ❌ 命中数据面路径: $f"
          hit=$((hit + 1))
          break ;;
      esac
    done < <(printf '%s' "$paths" | tr ',;' '\n\n')
  done < <({ git diff --name-only "$mb" HEAD; git diff --name-only HEAD; } | sort -u)
  if [ "$hit" -gt 0 ]; then
    echo "  ❌ $hit 个文件命中数据面 —— 缺陷修复须走既有数据链路（docs/agents/defect-workflow.md）：" >&2
    echo "     ① 既有链路 bug → 正常修复 + 回归测试；② 根因是该面未数据化 → 升级 change" >&2
    echo "     禁止新增硬编码常量（新动作 id / 新扇区 / 新图标名直接写死常量数组）" >&2
    exit "$EXIT_VIOLATION"
  fi
  echo "  SKIP 数据面（未命中路径信号）"
}

# ---- selftest: 固定样本，不依赖消费仓测试基建 ------------------------------
make_fixture() { # dir kind
  local d="$1" kind="$2"
  mkdir -p "$d"
  case "$kind" in
    nosignal)
      printf '# 无信号\n\n纯文档改动，不涉及配置。\n' > "$d/design.md" ;;
    complete)
      cat > "$d/design.md" <<'EOF'
# t

数据面：把轮盘各层做成可配置。

## 数据面

| 落点 | 位置 | 载体/符号 | 判据 |
|---|---|---|---|
| 规格 | design-system:§2 | — | 图标尺寸只允许 14/18/24 |
| 存储 | src-tauri/src/config.rs | AppConfig | 字段可空，缺省回落 |
| 校验 | src-tauri/src/config.rs | validate_config | 枚举白名单 |
| 桥接 | src/hooks/useConfig.ts | applyRustConfig | 未知 id 忽略 |
| 消费 | src/editors/orchestration/floating-toolbar.ts | createRoulette | 数组顺序即显示顺序 |
| 回滚 | snapshots/ | restore_config_snapshot | 写前快照 10 份 |
EOF
      ;;
    no_rollback)
      cat > "$d/design.md" <<'EOF'
# t

数据面：轮盘可配置。

## 数据面

| 落点 | 位置 | 载体/符号 | 判据 |
|---|---|---|---|
| 规格 | design-system:§2 | — | 图标尺寸 |
| 存储 | src-tauri/src/config.rs | AppConfig | 可空 |
| 校验 | src-tauri/src/config.rs | validate_config | 白名单 |
| 桥接 | src/hooks/useConfig.ts | applyRustConfig | 忽略未知 |
| 消费 | src/editors/orchestration/floating-toolbar.ts | createRoulette | 顺序 |
EOF
      ;;
    bad_path)
      sed 's#src-tauri/src/config.rs#src/nope.rs#' "$3/complete/design.md" > "$d/design.md" ;;
  esac
}

run_selftest() {
  local tmp pass=0 fail=0 rc
  tmp="$(mktemp -d)"
  TMPFILES="$TMPFILES $tmp"
  make_fixture "$tmp/complete" complete
  make_fixture "$tmp/no_rollback" no_rollback
  make_fixture "$tmp/nosignal" nosignal
  make_fixture "$tmp/bad_path" bad_path "$tmp"

  # 自包含 git 夹具：diff 子命令按 ROOT 检查「位置」文件与「载体/符号」，
  # 不能依赖安装仓里恰有这几个文件（否则换一个仓 selftest 就假红）。
  local fakerepo="$tmp/fakerepo"
  mkdir -p "$fakerepo/src-tauri/src" "$fakerepo/src/hooks" "$fakerepo/src/editors/orchestration"
  printf 'pub struct AppConfig;\npub fn validate_config() {}\n' > "$fakerepo/src-tauri/src/config.rs"
  printf 'export function applyRustConfig() {}\n' > "$fakerepo/src/hooks/useConfig.ts"
  printf 'export function createRoulette() {}\n' > "$fakerepo/src/editors/orchestration/floating-toolbar.ts"
  git -C "$fakerepo" init -q

  expect() {
    local name="$1" want="$2"; shift 2
    set +e
    "$@" >/dev/null 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq "$want" ]; then
      echo "  ✅ ${name}（exit ${rc}）"; pass=$((pass + 1))
    else
      echo "  ❌ ${name}（期望 ${want}，实得 ${rc}）" >&2; fail=$((fail + 1))
    fi
  }

  expect_in() { # 在指定 cwd 下运行（pr 模式 ROOT 随 cwd 解析）
    local name="$1" want="$2" dir="$3"; shift 3
    set +e
    ( cd "$dir" && "$@" ) >/dev/null 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq "$want" ]; then
      echo "  ✅ ${name}（exit ${rc}）"; pass=$((pass + 1))
    else
      echo "  ❌ ${name}（期望 ${want}，实得 ${rc}）" >&2; fail=$((fail + 1))
    fi
  }

  git_fix() { # dir base_or_hit ... 极简 git 夹具
    local dir="$1" seed="$2" msg="$3"
    git -C "$dir" init -q
    printf '%s\n' "$seed" > "$dir/seed.txt"
    git -C "$dir" add -A
    git -C "$dir" -c user.email=t@t -c user.name=t commit -qm "$msg"
  }
  commit_more() {
    local dir="$1" msg="$2"
    git -C "$dir" add -A
    git -C "$dir" -c user.email=t@t -c user.name=t commit -qm "$msg"
  }

  echo "==> selftest"
  expect "无信号 → SKIP" 0 "$SELF" new x --dir "$tmp/nosignal"
  expect "六栏齐全 → 通过" 0 "$SELF" new x --dir "$tmp/complete"
  expect "缺回滚 → 违规" 1 "$SELF" new x --dir "$tmp/no_rollback"
  mkdir -p "$tmp/drafts"
  printf '# 票\n\n**数据面**: 存储,桥接,校验,消费\n' > "$tmp/drafts/1.md"
  expect "票面缺两栏 → 违规" 1 "$SELF" tickets x --dir "$tmp/complete" --drafts "$tmp/drafts"
  printf '# 票\n\n**数据面**: 规格,存储,校验,桥接,消费,回滚\n' > "$tmp/drafts/1.md"
  expect "票面覆盖六栏 → 通过" 0 "$SELF" tickets x --dir "$tmp/complete" --drafts "$tmp/drafts"
  printf '# 票\n\n**数据面**: 规格，存储，校验，桥接，消费，回滚\n' > "$tmp/drafts/1.md"
  expect "全角逗号覆盖 → 通过" 0 "$SELF" tickets x --dir "$tmp/complete" --drafts "$tmp/drafts"
  expect_in "落地符号缺失 → 违规" 1 "$fakerepo" "$SELF" diff x --dir "$tmp/bad_path"
  expect_in "落地校验 → 通过" 0 "$fakerepo" "$SELF" diff x --dir "$tmp/complete"

  local grepo grepo2 prbase prbase2
  grepo="$tmp/gitrepo"
  mkdir -p "$grepo/src/hooks"
  git_fix "$grepo" base base
  prbase="$(git -C "$grepo" rev-parse HEAD)"
  printf 'hit\n' > "$grepo/src/hooks/useConfig.ts"
  commit_more "$grepo" hit
  expect_in "pr 命中数据面路径 → 违规" 1 "$grepo" "$SELF" pr "$prbase"
  expect_in "pr 基线不存在 → 环境缺失" 3 "$grepo" "$SELF" pr nope

  grepo2="$tmp/gitrepo2"
  mkdir -p "$grepo2/src/hooks" "$grepo2/docs"
  printf 'hit\n' > "$grepo2/src/hooks/useConfig.ts"
  git_fix "$grepo2" base base
  prbase2="$(git -C "$grepo2" rev-parse HEAD)"
  printf 'docs\n' > "$grepo2/docs/note.md"
  commit_more "$grepo2" docs
  expect_in "pr 仅文档改动 → SKIP" 0 "$grepo2" "$SELF" pr "$prbase2"

  echo "----"
  if [ "$fail" -gt 0 ]; then
    echo "❌ selftest: $pass 通过 / $fail 失败" >&2
    exit "$EXIT_VIOLATION"
  fi
  echo "✅ selftest: $pass 项全通过"
}

MODE=""
CHANGE=""
DIR_OVERRIDE=""
DRAFTS_OVERRIDE=""

[ $# -gt 0 ] || { usage; exit 2; }
case "$1" in
  new|tickets|diff|signals|pr|selftest) MODE="$1"; shift ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR_OVERRIDE="${2:-}"; shift 2 ;;
    --drafts) DRAFTS_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) die_arg "未知参数: $1" ;;
    *) CHANGE="$1"; shift ;;
  esac
done

if [ "$MODE" = "selftest" ]; then
  run_selftest
  exit 0
fi

[ -n "$CHANGE" ] || die_arg "缺少参数"

case "$MODE" in
  pr)
    check_pr "$CHANGE" ;;
  *)
    CHANGE_DIR="$(changedir "$CHANGE" "$DIR_OVERRIDE")"
    case "$MODE" in
      new)
        if [ "$(has_signal "$CHANGE_DIR")" != "1" ]; then
          echo "SKIP 数据面（未命中信号）: $CHANGE"
          exit 0
        fi
        check_new "$CHANGE_DIR" "$CHANGE" ;;
      tickets)
        check_tickets "$CHANGE_DIR" "$CHANGE" "${DRAFTS_OVERRIDE:-$ROOT/.tickets-draft/$CHANGE}" ;;
      diff)
        check_diff "$CHANGE_DIR" "$CHANGE" ;;
      signals)
        echo "paths:    $(conf_get DATA_SURFACE_PATHS 2>/dev/null || printf '%s' "$DEFAULT_PATHS")"
        echo "keywords: $(conf_get DATA_SURFACE_KEYWORDS 2>/dev/null || printf '%s' "$DEFAULT_KEYWORDS")"
        echo "hit:      $(has_signal "$CHANGE_DIR")" ;;
    esac ;;
esac
