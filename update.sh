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
#   --force     强制覆盖（含 --accept-local 保留的文件；覆盖前一律备份 .bak）
#   --adopt     强制进入接管模式（用于 1.0.0 时代无基线记录的既有安装）
#   --accept-local <path>  接受某文件的本地版本（记为新基线，此后不再报告冲突）；
#                          可重复传入多个路径
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
ACCEPT_LOCAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)  TARGET="$2"; shift 2 ;;
    --check)   CHECK_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force)   FORCE=1; shift ;;
    --adopt)   ADOPT=1; shift ;;
    --accept-local) ACCEPT_LOCAL+=("$2"); shift 2 ;;
    --help|-h) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

log()  { echo "==> $*"; }
warn() { echo "⚠️  $*" >&2; }
act()  { if [[ "$DRY_RUN" == "1" ]]; then echo "    [dry-run] $*"; else "$@"; fi; }

# 校验安装目录是仓库内相对路径（不含 ..）：SKILLS_DIR/DOCS_DIR 会拼进受管文件目标路径，
# 若被填成绝对路径或带 .. 的路径，会把文件装到仓库外（B1）。
cw_check_rel_dir() {
  case "$1" in
    /*|*..*) echo "❌ $2 必须是仓库内相对路径且不含 ..: $1" >&2; exit 1 ;;
  esac
}

cd "$TARGET" || { echo "❌ 目标目录不存在: $TARGET" >&2; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "❌ $TARGET 不是 git 仓库" >&2; exit 1; }
# 锁目录放 .git 内（并发升级互斥，C3）。不能用 GIT_DIR 这个名字 —— 它是 git 保留环境变量，
# 赋值后会让后续 `git -C "$SCRIPT_DIR"`（toolkit_source）误以为仓库在别处。
CW_GIT_DIR="$(git rev-parse --git-dir)"
TARGET_ROOT="$(git rev-parse --show-toplevel)"
TARGET_REPO="$(git config --get remote.origin.url 2>/dev/null || echo '(无 origin)')"
log "目标仓库：$TARGET_ROOT  ←  $TARGET_REPO"
log "本次只改动该仓库内的受管文件；请确认上面路径正确（错误 cwd 会改错仓库）"
if cw_is_self_target "$TARGET_ROOT"; then
  echo "❌ 拒绝：目标是工具包源自身（${TARGET_ROOT}）" >&2
  echo "   升级会把模板源当成受管文件写基线，此后每次改模板都会报冲突；本仓不是自己的消费者。" >&2
  exit 1
fi

CONF=".change-workflow.conf"
[[ -f "$CONF" ]] || { echo "❌ 未找到 $CONF —— 请先运行 setup.sh 安装" >&2; exit 1; }
# 从 conf 读取键值（B1）：不用 `source "$CONF"` —— conf 是仓库内文件，值可被任意改动，
# source 会把 `TOOLKIT_SOURCE="$(touch /tmp/pwned; echo x)"` 这类值当命令执行。
# 只读白名单内的 14 个键，其余键（TOOLKIT_SOURCE/CHANGE_WORKFLOW_HOME/LABEL_* 等）不读不写。
for _cw_key in TOOLKIT_VERSION EFFECTIVE_DATE REPO_ROOT REPO OWNER DEFAULT_BRANCH \
               SKILLS_DIR DOCS_DIR PROJECT_ID STATUS_FIELD_ID \
               OPT_BACKLOG OPT_READY OPT_IN_PROGRESS OPT_DONE; do
  _cw_val="$(cw_conf_get "$CONF" "$_cw_key")" || _cw_val=""
  printf -v "$_cw_key" '%s' "$_cw_val"
done
unset _cw_key _cw_val

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

# 并发互斥锁（C3）：两个升级进程同时跑会互相覆盖 .bak/.new/manifest，产生半成品。
# 锁放 .git 内（CW_GIT_DIR），不污染工作区；--check 已提前退出、--dry-run 不取锁。
LOCK_DIR="$CW_GIT_DIR/.change-workflow.lock"
if [[ "$DRY_RUN" != "1" ]]; then
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "❌ 已有另一个升级/安装进程在运行（锁目录存在：${LOCK_DIR}）" >&2
    echo "   若确认没有其他进程，请手动删除该目录后重试。" >&2
    exit 1
  fi
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
fi

# --- 解决冲突：接受本地版本 ---------------------------------------------------
# 用于「已人工审阅、确认保留本地」的文件：记为**哨兵基线 LOCAL**，此后该文件
# 被永久跳过（不更新、不报冲突）。
#
# 注意：**不能**把当前内容哈希记为基线 —— 那表示「自基线以来未改动，可安全更新」，
# 下次更新会据此覆盖它，与「保留本地」的意图正好相反（这是真实踩过的坑）。
if [[ "${#ACCEPT_LOCAL[@]}" -gt 0 ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] 将接受本地版本（记为 LOCAL，此后永久跳过）："
    printf '    %s\n' "${ACCEPT_LOCAL[@]}"
    exit 0
  fi
  accepted=0
  for p in "${ACCEPT_LOCAL[@]}"; do
    if [[ ! -f "$p" ]]; then warn "跳过（文件不存在）：${p}"; continue; fi
    if [[ -f "${p}.new" ]]; then
      warn "注意：${p} 仍有未处理的 ${p}.new —— 接受本地后将不再提示，请确认不再需要它"
    fi
    tmp_manifest="$(mktemp)"
    if [[ -f "$MANIFEST" ]]; then awk -v p="$p" '$2 != p' "$MANIFEST" > "$tmp_manifest"; fi
    printf 'LOCAL  %s\n' "$p" >> "$tmp_manifest"
    mv "$tmp_manifest" "$MANIFEST"
    log "已接受本地版本（此后永久跳过）：${p}"
    accepted=$((accepted + 1))
  done
  log "完成：接受 ${accepted} 个文件；再次运行 ./update.sh 应归一（退出码 0）"
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

# 工具包自身来源：优先取 clone 的 origin remote；无则用默认仓库。
# 写入项目 conf 的 TOOLKIT_SOURCE，供 scripts/cw-update.sh 自升级时定位工具包。
toolkit_source() {
  local url
  url="$(git -C "$SCRIPT_DIR" config --get remote.origin.url 2>/dev/null || true)"
  echo "${url:-https://github.com/jianxi-dev/change-workflow.git}"
}

# 向 .change-workflow.conf upsert 一个键值：存在则替换，不存在则追加。
# 模式保持（R1）：sed > tmp; mv 的 tmp 是 mktemp（恒 0600），mv 会把 conf 从 644 拉成 600
# （红证：update 一次后 conf 644→600），故 mv 前经 cw_tmp_mode_for 调回 conf 应有模式。
# 另：下方 TOOLKIT_VERSION 的 `sed -i.cw-tmp` 路径实测（macOS BSD sed 与 GNU sed 语义一致）
# 保留原文件模式（600→600、644→644），无需额外处理。
upsert_conf() {
  local key="$1" val="$2" tmp
  cw_refuse_symlink "$CONF" "配置文件"
  tmp="$(mktemp)"
  if grep -q "^${key}=" "$CONF" 2>/dev/null; then
    sed "s|^${key}=.*|${key}=\"${val}\"|" "$CONF" > "$tmp"
    cw_tmp_mode_for "$tmp" "$CONF"
    mv "$tmp" "$CONF"
  else
    printf '\n%s="%s"\n' "$key" "$val" >> "$CONF"
    rm -f "$tmp"
  fi
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
# 接管路径与正常路径的默认值一致，这里校验一次即可覆盖两条路径（B1）
cw_check_rel_dir "$SKILLS_DIR" "SKILLS_DIR"
cw_check_rel_dir "$DOCS_DIR" "DOCS_DIR"

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
      [[ "$DRY_RUN" != "1" ]] && cw_atomic_cp "$TMP" "${dst}"
      B_NEW=$((B_NEW + 1))
    elif [[ "$(cw_sha "${dst}")" == "$(cw_sha "$TMP")" ]]; then
      log "  一致：${dst}"
      B_SAME=$((B_SAME + 1))
    else
      warn "  不同：${dst}（新版本写入 ${dst}.new；**不写基线**，将持续标记直到你解决）"
      [[ "$DRY_RUN" != "1" ]] && cw_atomic_cp "$TMP" "${dst}.new"
      B_DIFF=$((B_DIFF + 1)); B_LIST+=("${dst}")
    fi
    rm -f "$TMP"
  done < <(cw_list_files)

  if [[ "$DRY_RUN" != "1" ]]; then
    # 受管文件若被换成符号链接，重定向/覆盖会写穿到链接指向处（C2）—— 写 manifest/conf 前先拒绝
    cw_refuse_symlink "$MANIFEST" "基线清单"
    cw_refuse_symlink "$CONF" "配置文件"
    # 受管脚本必须可执行：cw_render 用重定向写文件，不保留执行位。
    # 名单由受管清单（cw_list_files）派生，不再硬编码：新增脚本自动获得执行位，避免漏加
    # 导致消费仓 `./scripts/<name>.sh` 报 Permission denied（1.2.0 / 1.3.0 两次同因缺陷）。
    # chmod 失败不再被 `|| true` 吞掉（F1）。
    cw_chmod_scripts
    # manifest 先写临时文件再整体 mv：中途失败不留半截清单（C3）
    _mft_tmp="$(mktemp)"
    while IFS='|' read -r tpl_rel dst_rel; do
      [[ -n "$tpl_rel" ]] || continue
      dst="${dst_rel/__SKILLS_DIR__/$SKILLS_DIR}"
      dst="${dst/__DOCS_DIR__/$DOCS_DIR}"
      [[ -f "${dst}" ]] || continue
      # 「不同」的文件**不写基线**：它们可能是本地定制。若把当前内容记为基线，
      # 下次更新会因 current==baseline 判为「未修改」而**静默覆盖**它 ——
      # 用户的 .new 尚未处理就被冲掉。不写基线 → 持续标记为冲突，直到人工解决。
      if is_in_list "$dst" "${B_LIST[@]:-}"; then continue; fi
      printf '%s  %s\n' "$(cw_sha "${dst}")" "${dst}" >> "$_mft_tmp"
    done < <(cw_list_files)
    # 模式保持（R1）：mktemp 恒 0600，mv 前调成 manifest 应有模式（已存在→沿用；新建→644）
    cw_tmp_mode_for "$_mft_tmp" "$MANIFEST"
    mv "$_mft_tmp" "$MANIFEST"
    if grep -q '^TOOLKIT_VERSION=' "$CONF"; then
      sed -i.cw-tmp "s|^TOOLKIT_VERSION=.*|TOOLKIT_VERSION=\"$NEW_VERSION\"|" "$CONF" && rm -f "$CONF.cw-tmp"
    else
      printf '\nTOOLKIT_VERSION="%s"\nEFFECTIVE_DATE="%s"\nREPO_ROOT="%s"\n' \
        "$NEW_VERSION" "$EFFECTIVE_DATE" "$REPO_ROOT" >> "$CONF"
    fi
    upsert_conf TOOLKIT_SOURCE "$(toolkit_source)"
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
  1. 保留本地：./update.sh --accept-local <file>   （记为新基线，此后不再报告）
  2. 采用新版：mv <file>.new <file>                （下次升级自动写基线）
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

UPDATED=0; ADDED=0; CURRENT=0; CONFLICTED=0; LOCAL_KEPT=0
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
    if [[ "$DRY_RUN" != "1" ]]; then cw_atomic_cp "$TMP" "${dst}"; fi
    ADDED=$((ADDED + 1))
    rm -f "$TMP"; continue
  fi

  current_sha="$(cw_sha "${dst}")"
  new_sha="$(cw_sha "$TMP")"
  baseline="$(baseline_of "${dst}")"

  if [[ "$current_sha" == "$new_sha" ]]; then
    CURRENT=$((CURRENT + 1)); rm -f "$TMP"; continue
  fi

  # --force 优先于 LOCAL 哨兵：用户显式要求覆盖（含 --accept-local 保留的文件）。
  # 必须放在 LOCAL 判断之前，否则 --force 对已接受本地的文件无效（C4）。
  if [[ "$FORCE" == "1" ]]; then
    log "强制覆盖：${dst}（备份 .bak）"
    if [[ "$DRY_RUN" != "1" ]]; then cw_atomic_cp "${dst}" "${dst}.bak"; cw_atomic_cp "$TMP" "${dst}"; fi
    UPDATED=$((UPDATED + 1)); rm -f "$TMP"; continue
  fi

  # 哨兵基线 LOCAL：用户显式选择「保留本地」（--accept-local）→ 永久跳过，不更新也不报冲突
  if [[ "$baseline" == "LOCAL" ]]; then
    LOCAL_KEPT=$((LOCAL_KEPT + 1)); rm -f "$TMP"; continue
  fi

  if [[ -z "$baseline" ]]; then
    warn "无基线记录，保守跳过（人工核对后可删除该文件或加 --force）：${dst}"
    if [[ "$DRY_RUN" != "1" ]]; then cw_atomic_cp "$TMP" "${dst}.new"; fi
    CONFLICTED=$((CONFLICTED + 1)); CONFLICT_LIST+=("${dst}"); rm -f "$TMP"; continue
  fi

  if [[ "$current_sha" == "$baseline" ]]; then
    log "更新：${dst}"
    if [[ "$DRY_RUN" != "1" ]]; then cw_atomic_cp "${dst}" "${dst}.bak"; cw_atomic_cp "$TMP" "${dst}"; fi
    UPDATED=$((UPDATED + 1)); rm -f "$TMP"; continue
  fi

  warn "本地已修改，写旁路文件（不覆盖）：${dst}.new"
  if [[ "$DRY_RUN" != "1" ]]; then cw_atomic_cp "$TMP" "${dst}.new"; fi
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
  # 受管文件若被换成符号链接，重定向/覆盖会写穿到链接指向处（C2）—— 写 manifest/conf 前先拒绝
  cw_refuse_symlink "$MANIFEST" "基线清单"
  cw_refuse_symlink "$CONF" "配置文件"
  # 受管脚本必须可执行：cw_render 用重定向写文件，不保留执行位。
  # 名单由受管清单（cw_list_files）派生，不再硬编码：新增脚本自动获得执行位，避免漏加
  # 导致消费仓 `./scripts/<name>.sh` 报 Permission denied（1.2.0 / 1.3.0 两次同因缺陷）。
  # chmod 失败不再被 `|| true` 吞掉（F1）。
  cw_chmod_scripts
  OLD_BASELINES="$(mktemp)"
  [[ -f "$MANIFEST" ]] && cp "$MANIFEST" "$OLD_BASELINES"
  # manifest 先写临时文件再整体 mv：中途失败不留半截清单（C3）
  _mft_tmp="$(mktemp)"
  while IFS='|' read -r tpl_rel dst_rel; do
    [[ -n "$tpl_rel" ]] || continue
    dst="${dst_rel/__SKILLS_DIR__/$SKILLS_DIR}"
    dst="${dst/__DOCS_DIR__/$DOCS_DIR}"
    [[ -f "${dst}" ]] || continue
    if is_conflicted "${dst}"; then
      prev="$(awk -v p="${dst}" '$2 == p { print $1; exit }' "$OLD_BASELINES")"
      [[ -n "$prev" ]] && printf '%s  %s\n' "$prev" "${dst}" >> "$_mft_tmp"
      continue
    fi
    # 保留 LOCAL 哨兵（--accept-local 的选择），勿覆盖回真实哈希
    prev="$(awk -v p="${dst}" '$2 == p { print $1; exit }' "$OLD_BASELINES")"
    if [[ "$prev" == "LOCAL" ]]; then
      printf 'LOCAL  %s\n' "${dst}" >> "$_mft_tmp"
      continue
    fi
    printf '%s  %s\n' "$(cw_sha "${dst}")" "${dst}" >> "$_mft_tmp"
  done < <(cw_list_files)
  # 模式保持（R1）：同接管路径，mv 前调模式（R1 红证：升级后 manifest 恒 600）
  cw_tmp_mode_for "$_mft_tmp" "$MANIFEST"
  mv "$_mft_tmp" "$MANIFEST"
  rm -f "$OLD_BASELINES"

  if grep -q '^TOOLKIT_VERSION=' "$CONF"; then
    sed -i.cw-tmp "s|^TOOLKIT_VERSION=.*|TOOLKIT_VERSION=\"$NEW_VERSION\"|" "$CONF" && rm -f "$CONF.cw-tmp"
  else
    printf '\nTOOLKIT_VERSION="%s"\nEFFECTIVE_DATE="%s"\nREPO_ROOT="%s"\n' \
      "$NEW_VERSION" "$EFFECTIVE_DATE" "$REPO_ROOT" >> "$CONF"
  fi
  upsert_conf TOOLKIT_SOURCE "$(toolkit_source)"
fi

echo
log "更新完成：更新 ${UPDATED} · 新增 ${ADDED} · 已最新 ${CURRENT} · 冲突 ${CONFLICTED} · 本地保留 ${LOCAL_KEPT}"
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
