#!/usr/bin/env bash
# =============================================================================
# change-workflow 更新向导
#
# 用法:
#   ./update.sh [--target <项目目录>] [--check] [--dry-run] [--force] [--adopt]
#
# 行为:
#   --check     仅比对版本，不落盘（进度用）
#   --dry-run   打印将执行的动作，不落盘
#   --force     忽略本地改动强制覆盖（覆盖前一律备份 .bak）
#   --adopt     强制进入接管模式（用于 1.0.0 时代无基线记录的既有安装）
#
# 冲突保护:
#   以 .change-workflow.manifest 记录的**基线哈希**判定目标文件是否被本地修改。
#   - 未修改（current == baseline）→ 安全覆盖（先备份）
#   - 已修改（current != baseline）→ 写 <file>.new 旁路文件并报告，**不覆盖**
#   - 目标不存在（新增文件）        → 直接安装
#
# 退出码: 0 无冲突；1 存在冲突或错误（便于 CI/脚本判断）
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/render.sh
source "$SCRIPT_DIR/lib/render.sh"

TARGET="$(pwd)"
CHECK_ONLY=0
DRY_RUN=0
FORCE=0
ADOPT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)  TARGET="$2"; shift 2 ;;
    --check)   CHECK_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force)   FORCE=1; shift ;;
    --adopt)   ADOPT=1; shift ;;
    --help|-h) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

log()  { echo "==> $*"; }
warn() { echo "⚠️  $*" >&2; }
act()  { if [[ "$DRY_RUN" == "1" ]]; then echo "    [dry-run] $*"; else "$@"; fi; }

cd "$TARGET" || { echo "❌ 目标目录不存在: $TARGET" >&2; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "❌ $TARGET 不是 git 仓库" >&2; exit 1; }
TARGET_ROOT="$(git rev-parse --show-toplevel)"
TARGET_REPO="$(git config --get remote.origin.url 2>/dev/null || echo '(无 origin)')"
log "目标仓库：$TARGET_ROOT  ←  $TARGET_REPO"
log "本次只改动该仓库内的受管文件；请确认上面路径正确（错误 cwd 会改错仓库）"

CONF=".change-workflow.conf"
[[ -f "$CONF" ]] || { echo "❌ 未找到 $CONF —— 请先运行 setup.sh 安装" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONF"

MANIFEST=".change-workflow.manifest"
NEW_VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
OLD_VERSION="${TOOLKIT_VERSION:-（未知，视为 1.0.0）}"

log "工具包版本：${OLD_VERSION} → ${NEW_VERSION}"
if [[ "$OLD_VERSION" == "$NEW_VERSION" ]]; then
  log "已是最新版本，无需更新"
  [[ "$CHECK_ONLY" == "1" ]] && exit 0
fi

if [[ "$CHECK_ONLY" == "1" ]]; then
  [[ "$OLD_VERSION" == "$NEW_VERSION" ]] || log "有新版本可用：运行 ./update.sh 进行更新"
  exit 0
fi

# --- 引导（adopt）：针对 1.0.0 时代安装的仓库 ---------------------------------
# 那时的 setup.sh 不写 manifest，因此无法区分「文件未改」与「被本地改过」。
# 此时不静默覆盖：逐个比对当前文件与新版模板，一致则接管，不同则写 .new 供人工核对，
# 并把**当前内容**记为新基线（接管），使后续升级恢复正常语义。
# 通用：判断值是否在给定列表中。**不用 nameref（local -n）** ——
# macOS 自带 /bin/bash 是 3.2，不支持 nameref（4.3+ 才有），会导致函数静默失效。
# 定义须在首次调用之前（接管块会用到）。
is_in_list() {
  local needle="$1"; shift
  local item
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

needs_bootstrap() {
  [[ "$ADOPT" == "1" ]] && return 0
  [[ -s "$MANIFEST" ]] && return 1
  local tpl_rel dst_rel dst
  while IFS='|' read -r tpl_rel dst_rel; do
    [[ -n "$tpl_rel" ]] || continue
    dst="${dst_rel/__SKILLS_DIR__/$SKILLS_DIR}"
    dst="${dst/__DOCS_DIR__/$DOCS_DIR}"
    [[ -f "${dst}" ]] && return 0
  done < <(cw_list_files)
  return 1
}

# 引导所需的替换值（与正常路径共用）
REPO_ROOT="$(git rev-parse --show-toplevel)"
EFFECTIVE_DATE="${EFFECTIVE_DATE:-$(date +%F)}"
OWNER="${REPO%%/*}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
SKILLS_DIR="${SKILLS_DIR:-.opencode/skills}"
DOCS_DIR="${DOCS_DIR:-docs/agents}"

if needs_bootstrap; then
  log "检测到无基线记录的既有安装（1.0.0 时代）→ 进入接管模式"
  log "不会静默覆盖：逐个比对当前文件与 ${NEW_VERSION} 模板"
  B_SAME=0; B_DIFF=0; B_NEW=0; B_LIST=()
  while IFS='|' read -r tpl_rel dst_rel; do
    [[ -n "$tpl_rel" ]] || continue
    dst="${dst_rel/__SKILLS_DIR__/$SKILLS_DIR}"
    dst="${dst/__DOCS_DIR__/$DOCS_DIR}"
    tpl="$SCRIPT_DIR/$tpl_rel"
    [[ -f "$tpl" ]] || continue
    TMP="$(mktemp)"; cw_render "$tpl" "$TMP"
    if [[ ! -f "${dst}" ]]; then
      log "  新增：${dst}"
      [[ "$DRY_RUN" != "1" ]] && { mkdir -p "$(dirname "${dst}")"; cp "$TMP" "${dst}"; }
      B_NEW=$((B_NEW + 1))
    elif [[ "$(cw_sha "${dst}")" == "$(cw_sha "$TMP")" ]]; then
      log "  一致：${dst}"
      B_SAME=$((B_SAME + 1))
    else
      warn "  不同：${dst}（新版本写入 ${dst}.new；**不写基线**，将持续标记直到你解决）"
      [[ "$DRY_RUN" != "1" ]] && cp "$TMP" "${dst}.new"
      B_DIFF=$((B_DIFF + 1)); B_LIST+=("${dst}")
    fi
    rm -f "$TMP"
  done < <(cw_list_files)

  if [[ "$DRY_RUN" != "1" ]]; then
    [[ -f scripts/pr-automation.sh ]] && chmod +x scripts/pr-automation.sh 2>/dev/null || true
    : > "$MANIFEST"
    while IFS='|' read -r tpl_rel dst_rel; do
      [[ -n "$tpl_rel" ]] || continue
      dst="${dst_rel/__SKILLS_DIR__/$SKILLS_DIR}"
      dst="${dst/__DOCS_DIR__/$DOCS_DIR}"
      [[ -f "${dst}" ]] || continue
      # 「不同」的文件**不写基线**：它们可能是本地定制。若把当前内容记为基线，
      # 下次更新会因 current==baseline 判为「未修改」而**静默覆盖**它 ——
      # 用户的 .new 尚未处理就被冲掉。不写基线 → 持续标记为冲突，直到人工解决。
      if is_in_list "$dst" "${B_LIST[@]:-}"; then continue; fi
      printf '%s  %s\n' "$(cw_sha "${dst}")" "${dst}" >> "$MANIFEST"
    done < <(cw_list_files)
    if grep -q '^TOOLKIT_VERSION=' "$CONF"; then
      sed -i.cw-tmp "s|^TOOLKIT_VERSION=.*|TOOLKIT_VERSION=\"$NEW_VERSION\"|" "$CONF" && rm -f "$CONF.cw-tmp"
    else
      printf '\nTOOLKIT_VERSION="%s"\nEFFECTIVE_DATE="%s"\nREPO_ROOT="%s"\n' \
        "$NEW_VERSION" "$EFFECTIVE_DATE" "$REPO_ROOT" >> "$CONF"
    fi
  fi

  echo
  log "接管完成：一致 ${B_SAME} · 不同 ${B_DIFF} · 新增 ${B_NEW}"
  if [[ "$B_DIFF" -gt 0 ]]; then
    cat >&2 <<EOF

以下文件与 ${NEW_VERSION} 模板不同（可能是本地定制，也可能是 1.0.0→${NEW_VERSION} 的正常演进）。
新版本已写入同名 .new 旁路文件。

**这些文件未写基线** —— 在你解决之前，每次升级都会继续报告它们（不会被静默覆盖）。

$(printf '  - %s.new\n' "${B_LIST[@]}")

处理方式（每个文件任选其一）：
  1. 保留本地：rm <file>.new        （基线仍未写；确认无需再跟踪该文件时可直接删）
  2. 采用新版：mv <file>.new <file> （下次升级会自动写入基线）
  3. 人工合并：diff <file> <file>.new → 合并 → rm <file>.new
  4. 全部采用新版：./update.sh --force

全部解决后再次运行 ./update.sh 即归一（退出码 0）。
EOF
    exit 1
  fi
  cat <<EOF

后续：git diff → git add -A && git commit -m "chore(change-workflow): 升级到 ${NEW_VERSION}"
EOF
  exit 0
fi

# 更新时的替换值：REPO_ROOT 取当前仓库真实根；EFFECTIVE_DATE 沿用首次安装的日期（不重戳，避免无谓 churn）
REPO_ROOT="$(git rev-parse --show-toplevel)"
EFFECTIVE_DATE="${EFFECTIVE_DATE:-$(date +%F)}"
OWNER="${REPO%%/*}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
SKILLS_DIR="${SKILLS_DIR:-.opencode/skills}"
DOCS_DIR="${DOCS_DIR:-docs/agents}"

baseline_of() {
  [[ -f "$MANIFEST" ]] || return 0
  awk -v p="$1" '$2 == p { print $1; exit }' "$MANIFEST"
}

UPDATED=0; ADDED=0; CURRENT=0; CONFLICTED=0
CONFLICT_LIST=()

while IFS='|' read -r tpl_rel dst_rel; do
  [[ -n "$tpl_rel" ]] || continue
  dst="${dst_rel/__SKILLS_DIR__/$SKILLS_DIR}"
  dst="${dst/__DOCS_DIR__/$DOCS_DIR}"
  tpl="$SCRIPT_DIR/$tpl_rel"

  if [[ ! -f "$tpl" ]]; then
    warn "模板缺失，跳过：$tpl_rel"
    continue
  fi

  TMP="$(mktemp)"
  cw_render "$tpl" "$TMP"

  if [[ ! -f "${dst}" ]]; then
    log "新增：${dst}"
    if [[ "$DRY_RUN" != "1" ]]; then mkdir -p "$(dirname "${dst}")"; cp "$TMP" "${dst}"; fi
    ADDED=$((ADDED + 1))
    rm -f "$TMP"; continue
  fi

  current_sha="$(cw_sha "${dst}")"
  new_sha="$(cw_sha "$TMP")"
  baseline="$(baseline_of "${dst}")"

  if [[ "$current_sha" == "$new_sha" ]]; then
    CURRENT=$((CURRENT + 1)); rm -f "$TMP"; continue
  fi

  if [[ "$FORCE" == "1" ]]; then
    log "强制覆盖：${dst}（备份 .bak）"
    if [[ "$DRY_RUN" != "1" ]]; then cp "${dst}" "${dst}.bak"; cp "$TMP" "${dst}"; fi
    UPDATED=$((UPDATED + 1)); rm -f "$TMP"; continue
  fi

  if [[ -z "$baseline" ]]; then
    warn "无基线记录，保守跳过（人工核对后可删除该文件或加 --force）：${dst}"
    if [[ "$DRY_RUN" != "1" ]]; then cp "$TMP" "${dst}.new"; fi
    CONFLICTED=$((CONFLICTED + 1)); CONFLICT_LIST+=("${dst}"); rm -f "$TMP"; continue
  fi

  if [[ "$current_sha" == "$baseline" ]]; then
    log "更新：${dst}"
    if [[ "$DRY_RUN" != "1" ]]; then cp "${dst}" "${dst}.bak"; cp "$TMP" "${dst}"; fi
    UPDATED=$((UPDATED + 1)); rm -f "$TMP"; continue
  fi

  warn "本地已修改，写旁路文件（不覆盖）：${dst}.new"
  if [[ "$DRY_RUN" != "1" ]]; then cp "$TMP" "${dst}.new"; fi
  CONFLICTED=$((CONFLICTED + 1)); CONFLICT_LIST+=("${dst}"); rm -f "$TMP"
done < <(cw_list_files)

# 重写 manifest（新版本 + 新基线）。**冲突文件保留旧基线**，使其下次仍被识别为「本地已修改」——
# 否则本地版会被静默接受为正典，此后模板更新将无提示地覆盖它。
is_conflicted() {
  local p="$1" c
  for c in "${CONFLICT_LIST[@]:-}"; do [[ "$c" == "$p" ]] && return 0; done
  return 1
}

if [[ "$DRY_RUN" != "1" ]]; then
  [[ -f scripts/pr-automation.sh ]] && chmod +x scripts/pr-automation.sh 2>/dev/null || true
  OLD_BASELINES="$(mktemp)"
  [[ -f "$MANIFEST" ]] && cp "$MANIFEST" "$OLD_BASELINES"
  : > "$MANIFEST"
  while IFS='|' read -r tpl_rel dst_rel; do
    [[ -n "$tpl_rel" ]] || continue
    dst="${dst_rel/__SKILLS_DIR__/$SKILLS_DIR}"
    dst="${dst/__DOCS_DIR__/$DOCS_DIR}"
    [[ -f "${dst}" ]] || continue
    if is_conflicted "${dst}"; then
      prev="$(awk -v p="${dst}" '$2 == p { print $1; exit }' "$OLD_BASELINES")"
      [[ -n "$prev" ]] && printf '%s  %s\n' "$prev" "${dst}" >> "$MANIFEST"
      continue
    fi
    printf '%s  %s\n' "$(cw_sha "${dst}")" "${dst}" >> "$MANIFEST"
  done < <(cw_list_files)
  rm -f "$OLD_BASELINES"

  if grep -q '^TOOLKIT_VERSION=' "$CONF"; then
    sed -i.cw-tmp "s|^TOOLKIT_VERSION=.*|TOOLKIT_VERSION=\"$NEW_VERSION\"|" "$CONF" && rm -f "$CONF.cw-tmp"
  else
    printf '\nTOOLKIT_VERSION="%s"\nEFFECTIVE_DATE="%s"\nREPO_ROOT="%s"\n' \
      "$NEW_VERSION" "$EFFECTIVE_DATE" "$REPO_ROOT" >> "$CONF"
  fi
fi

echo
log "更新完成：更新 ${UPDATED} · 新增 ${ADDED} · 已最新 ${CURRENT} · 冲突 ${CONFLICTED}"
if [[ "$CONFLICTED" -gt 0 ]]; then
  cat >&2 <<EOF

以下文件**本地已修改**，未覆盖；新版本内容已写入同名 .new 旁路文件：
$(printf '  - %s.new\n' "${CONFLICT_LIST[@]}")

处理方式（任选）：
  1. 人工 diff 合并：diff <file> <file>.new → 合并后删除 .new
  2. 放弃本地改动：mv <file>.new <file>
  3. 强制覆盖：./update.sh --force（覆盖前会备份 .bak）
EOF
  exit 1
fi

cat <<EOF

后续：
  1. 检查变更：git diff
  2. 提交：git add -A && git commit -m "chore(change-workflow): 升级到 ${NEW_VERSION}"
  3. 开 PR 合并
EOF
