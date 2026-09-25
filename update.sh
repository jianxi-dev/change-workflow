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
#   - 未修改（current == baseline）→ 安全覆盖（备份 .bak；收尾清理冗余副本）
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
  # 符号链接闸（S2）：与接管路径、正常路径收尾的 manifest 写前 cw_refuse_symlink 同一
  # C2 边界。红证：manifest 为符号链接时本路径原本 rc=0 放行 —— 同卷 mv 以 rename 替换
  # 链接（链接被销毁），跨卷 mv 退化为复制+删除则直接经链接写穿仓外目标。
  cw_refuse_symlink "$MANIFEST" "基线清单"
  accepted=0
  for p in "${ACCEPT_LOCAL[@]}"; do
    # 路径归一：剥「./」前缀（与 pr-automation.sh 的 in_files 同款）。manifest 键与受管清单
    # 目标均为无前缀相对路径；红证：`--accept-local ./docs/...` 过滤不命中旧行 → 旧行 +
    # `LOCAL  ./…` 并存，哨兵成死行，下次 update 仍 rc=1 报同一文件（谎报成功后永不归一）。
    p="${p#./}"
    if [[ ! -f "$p" ]]; then warn "跳过（文件不存在）：${p}"; continue; fi
    if [[ -f "${p}.new" ]]; then
      warn "注意：${p} 仍有未处理的 ${p}.new —— 接受本地后将不再提示，请确认不再需要它"
    fi
    tmp_manifest="$(mktemp)"
    # 过滤同按「剩余整串」比较（R3）：旧 `$2 != p` 对空格路径永不命中 → 旧行残留、LOCAL 不生效
    # 对抗轮4 Gap B：比较前剥行尾 \r（CRLF 清单曾让全部基线失配 → 误报无基线 + 重写丢
    # LOCAL 哨兵）；路径经 ENVIRON 传入而非 -v（-v 做反斜杠转义，含 \ 的路径永不命中，
    # 与 upsert_conf 同因）。写侧不动：非命中行原样保留（含其行尾风格）。
    if [[ -f "$MANIFEST" ]]; then CW_P="$p" awk '{ rest=$0; sub(/\r$/, "", rest); sub(/^[^[:space:]]+[[:space:]]+/, "", rest); if (rest != ENVIRON["CW_P"]) print }' "$MANIFEST" > "$tmp_manifest"; fi
    printf 'LOCAL  %s\n' "$p" >> "$tmp_manifest"
    # 模式保持（R1 收尾）：mktemp 恒 0600，mv 前调回 manifest 应有模式 —— 与接管/正常路径
    # 的 manifest 写同构；红证：accept-local 一次后 manifest 644→600（rc=0 静默）。
    cw_tmp_mode_for "$tmp_manifest" "$MANIFEST"
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
# 模式保持（R1）：> tmp; mv 的 tmp 是 mktemp（恒 0600），mv 会把 conf 从 644 拉成 600
# （红证：update 一次后 conf 644→600），故 mv 前经 cw_tmp_mode_for 调回 conf 应有模式。
# 另：下方 TOOLKIT_VERSION 的 `sed -i.cw-tmp` 路径实测（macOS BSD sed 与 GNU sed 语义一致）
# 保留原文件模式（600→600、644→644），无需额外处理。
# 为什么用 awk 而非 sed：sed 替换值是个微型语言（& = 整个匹配、\ = 转义、| = 分隔符）。
# 红证：toolkit origin=https://example.com/a&b.git 时，旧 sed 把 & 展开为整行匹配 →
# conf 出现 TOOLKIT_SOURCE="https://example.com/aTOOLKIT_SOURCE="…旧值…"b.git" 损坏值。
# 值经 ENVIRON 传入（不走 -v，-v 也做反斜杠转义），awk 输出为纯字面量，& 与 \ 均安全。
upsert_conf() {
  local key="$1" val="$2" tmp
  cw_refuse_symlink "$CONF" "配置文件"
  tmp="$(mktemp)"
  if grep -q "^${key}=" "$CONF" 2>/dev/null; then
    V="$val" awk -v k="$key" 'BEGIN { pat = "^" k "=" } $0 ~ pat { print k "=\"" ENVIRON["V"] "\""; next } { print }' "$CONF" > "$tmp"
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

后续：git diff → 只显式添加升级触碰的受管文件与 .change-workflow.conf/.manifest 后提交
（禁止 git add -A —— 白名单提交约定，防把未完成 WIP 卷进升级提交）
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

# manifest 行格式「<sha>  <path>」，path 可含空格（SKILLS_DIR="My Skills" 等，R3）。
# 读取端一律按「行首哈希 + 剩余整串」比较，绝不用 $2 —— awk 默认按空白拆列，
# $2 只拿到路径第一段，空格路径永远匹配不上：baseline_of 误报「无基线记录」→ .new + rc=1，
# 且重写时旧行被丢弃（红证：accept-local 后 manifest 中该文件 0 行，永不归一）。
# 写法：sha=$1 后 sub 掉「首个非空格 token + 其后空格」，rest 即完整路径。
# 写入端（printf '%s  %s\n'）不变 —— 只有读取端需要容错。
baseline_of() {
  [[ -f "$MANIFEST" ]] || return 0
  # 对抗轮4 Gap B：剥行尾 \r + 路径经 ENVIRON（理由见 accept-local 过滤处注释）。
  CW_P="$1" awk '{ sha=$1; rest=$0; sub(/\r$/, "", rest); sub(/^[^[:space:]]+[[:space:]]+/, "", rest); if (rest == ENVIRON["CW_P"]) { print sha; exit } }' "$MANIFEST"
}

UPDATED=0; ADDED=0; CURRENT=0; CONFLICTED=0; LOCAL_KEPT=0; BAK_CLEANED=0
CONFLICT_LIST=()
# --force 覆盖过的文件清单：force = 用户显式采用上游，基线必须归一为当前内容哈希。
# 红证：LOCAL 文件被 --force 覆盖后 manifest 仍是 LOCAL，下次模板演进时该文件被
# 「本地保留」静默跳过 —— 用户已放弃本地版，哨兵却永久生效（内容与基线双双失真）。
FORCED_LIST=()
# 1.4.1：安全覆盖（current == baseline）覆盖过的文件清单。其 .bak 内容 == 基线，可由 git
# 追溯，故收尾清理 —— 否则消费仓每次升级都累积 untracked 噪音。
# --force 覆盖的本地定制是唯一副本，不入此列（其 .bak 必须保留）。
BAK_SAFE=()

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
    # 三桶唯一性（对抗轮6）：基线 LOCAL = 用户 --accept-local 的显式保留决定，文件缺失
    # 不撤销它 —— 下方 manifest 重写仍会原样保留哨兵（LOCAL 保留分支）。若此处计 ADDED，
    # 汇总「本地保留」与 ^LOCAL 行数背离 → rollout-check 的 kept==grep -c '^LOCAL'
    # 发布契约在该状态（accept-local → rm）下必然误报不可发布。
    # 红证：accept-local → rm 文件 → update：新增 1 · 本地保留 0，而 grep -c '^LOCAL' 为 1。
    # 重装仍执行（缺失文件恢复上游内容），仅计数改道；dry-run 与真实同路径，计数一致。
    # 对抗轮7：--force 优先于 LOCAL 哨兵（同 :411-417 既有分支）。缺失文件被 --force
    # 重装 = 用户显式采用上游 → 必须记 FORCED_LIST，使 manifest 重写把哨兵归一为当前哈希；
    # 否则哨兵永久存活，下次模板演进该文件被「本地保留」静默跳过（内容与基线双双失真）。
    if [[ "$FORCE" == "1" ]]; then
      log "新增（强制覆盖）：${dst}"
      ADDED=$((ADDED + 1)); FORCED_LIST+=("${dst}")
    elif [[ "$(baseline_of "${dst}")" == "LOCAL" ]]; then
      log "新增（本地保留）：${dst}"
      LOCAL_KEPT=$((LOCAL_KEPT + 1))
    else
      log "新增：${dst}"
      ADDED=$((ADDED + 1))
    fi
    if [[ "$DRY_RUN" != "1" ]]; then cw_atomic_cp "$TMP" "${dst}"; fi
    rm -f "$TMP"; continue
  fi

  current_sha="$(cw_sha "${dst}")"
  new_sha="$(cw_sha "$TMP")"
  baseline="$(baseline_of "${dst}")"

  if [[ "$current_sha" == "$new_sha" ]]; then
    # 对抗轮4 Gap A：--force 时等值路径也必须记 FORCED_LIST。旧写法在 current==new 时
    # 提前 continue，先于下方 --force 分支触发 → 等值文件不进名单 → manifest 重写走
    # LOCAL 保留分支（:486 一带）→ 陈旧 LOCAL 在 --force 后仍存活，文件被「本地保留」
    # 永久跳过（红证：accept-local → mv .new → --force 后哨兵仍 LOCAL、演进不跟进）。
    # force = 显式采用上游：基线必须归一；内容已一致，故不补写文件、不备份。
    # 对抗轮5 MAJOR：等值路径必须按基线分流计数，不能一律「已最新」。为什么：LOCAL
    # 哨兵 + 内容已等值是可达成状态（accept-local → mv .new），一律计 CURRENT 会让
    # 汇总「本地保留」与 manifest 的 LOCAL 行数背离 → rollout-check 的
    # kept==grep -c '^LOCAL' 发布契约（AGENTS.md「LOCAL 哨兵完整」）误报不可发布。
    # force 时哨兵即将被归一清除（FORCED_LIST → manifest 重写走哈希），不算「保留」；
    # LOCAL 时哨兵由重写路径原样保留，文件确被「本地保留」，计 LOCAL_KEPT。
    if [[ "$FORCE" == "1" ]]; then
      FORCED_LIST+=("${dst}"); CURRENT=$((CURRENT + 1))
    elif [[ "$baseline" == "LOCAL" ]]; then
      LOCAL_KEPT=$((LOCAL_KEPT + 1))
    else
      CURRENT=$((CURRENT + 1))
    fi
    rm -f "$TMP"; continue
  fi

  # --force 优先于 LOCAL 哨兵：用户显式要求覆盖（含 --accept-local 保留的文件）。
  # 必须放在 LOCAL 判断之前，否则 --force 对已接受本地的文件无效（C4）。
  if [[ "$FORCE" == "1" ]]; then
    log "强制覆盖：${dst}（备份 .bak）"
    if [[ "$DRY_RUN" != "1" ]]; then cw_atomic_cp "${dst}" "${dst}.bak"; cw_atomic_cp "$TMP" "${dst}"; fi
    UPDATED=$((UPDATED + 1)); FORCED_LIST+=("${dst}"); rm -f "$TMP"; continue
  fi

  # 哨兵基线 LOCAL：用户显式选择「保留本地」（--accept-local）→ 永久跳过，不更新也不报冲突。
  # 例外：--force 显式采用上游时哨兵会被归一清除（见 FORCED_LIST），本地版即被放弃。
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
    BAK_SAFE+=("${dst}")
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

is_forced() {
  local p="$1" c
  for c in "${FORCED_LIST[@]:-}"; do [[ "$c" == "$p" ]] && return 0; done
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
    # --force 覆盖过的文件：最先处理（先于 conflicted/LOCAL 判断），基线归一为当前哈希。
    # force = 显式采用上游，旧 LOCAL 哨兵必须清除，否则后续演进被「本地保留」静默跳过。
    if is_forced "${dst}"; then
      printf '%s  %s\n' "$(cw_sha "${dst}")" "${dst}" >> "$_mft_tmp"
      continue
    fi
    if is_conflicted "${dst}"; then
      # 对抗轮4 Gap B：剥 \r + ENVIRON（同 accept-local / baseline_of 处注释）
      prev="$(CW_P="${dst}" awk '{ sha=$1; rest=$0; sub(/\r$/, "", rest); sub(/^[^[:space:]]+[[:space:]]+/, "", rest); if (rest == ENVIRON["CW_P"]) { print sha; exit } }' "$OLD_BASELINES")"
      [[ -n "$prev" ]] && printf '%s  %s\n' "$prev" "${dst}" >> "$_mft_tmp"
      continue
    fi
    # 保留 LOCAL 哨兵（--accept-local 的选择），勿覆盖回真实哈希
    # 对抗轮4 Gap B：剥 \r + ENVIRON —— 不剥则 CRLF 清单下 prev 取不到 "LOCAL"，
    # 哨兵在此被静默改写回哈希，本地保留保护无声解除。
    prev="$(CW_P="${dst}" awk '{ sha=$1; rest=$0; sub(/\r$/, "", rest); sub(/^[^[:space:]]+[[:space:]]+/, "", rest); if (rest == ENVIRON["CW_P"]) { print sha; exit } }' "$OLD_BASELINES")"
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

  # 1.4.1：安全覆盖的 .bak 是冗余备份（内容即基线，可由 git 追溯），留着只是消费仓每次
  # 升级累积的 untracked 噪音。与其它文件是否冲突无关 —— 每条 .bak 都对应一个已成功
  # 安全覆盖的文件。只清 BAK_SAFE：--force 的 .bak 是本地定制唯一副本，必须保留。
  for _cw_bak in "${BAK_SAFE[@]:-}"; do
    [[ -n "$_cw_bak" ]] || continue
    [[ -f "${_cw_bak}.bak" ]] || continue
    rm -f "${_cw_bak}.bak"; BAK_CLEANED=$((BAK_CLEANED + 1))
  done
fi

echo
if [[ "$BAK_CLEANED" -gt 0 ]]; then
  log "已清理冗余备份 ${BAK_CLEANED} 个（安全覆盖的 .bak，内容可由 git 追溯）"
fi
log "更新完成：更新 ${UPDATED} · 新增 ${ADDED} · 已最新 ${CURRENT} · 冲突 ${CONFLICTED} · 本地保留 ${LOCAL_KEPT}"
if [[ "$CONFLICTED" -gt 0 ]]; then
  cat >&2 <<EOF

以下文件**本地已修改**，未覆盖；新版本内容已写入同名 .new 旁路文件：
$(printf '  - %s.new\n' "${CONFLICT_LIST[@]}")

处理方式（任选）：
  1. 人工 diff 合并：diff <file> <file>.new → 合并后删除 .new
  2. 放弃本地改动：mv <file>.new <file>
  3. 强制覆盖：./update.sh --force（覆盖前会备份 .bak；注意也会覆盖
     --accept-local 保留的文件并清除其 LOCAL 哨兵 —— 哨兵归一是有意语义）
EOF
  exit 1
fi

cat <<EOF

后续：
  1. 检查变更：git diff
  2. 提交：只显式添加本次升级触碰的文件（受管文件 + .change-workflow.conf +
     .change-workflow.manifest）。**禁止 git add -A** —— 白名单提交是仓库约定，
     防止把你未完成的 WIP 一并卷进升级提交。
  3. 开 PR 合并
EOF
