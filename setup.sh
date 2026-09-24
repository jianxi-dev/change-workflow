#!/usr/bin/env bash
# =============================================================================
# change-workflow 安装向导
#
# 用法:
#   ./setup.sh [--target <项目目录>] [--yes] [--dry-run]
#
# 步骤:
#   1 前置检查（gh/git）→ 2 检测仓库 → 3 发现看板字段 ID
#   4 创建标签 → 5 询问质量门禁命令 → 6 写 .change-workflow.conf
#   7 拷贝 skill/脚本/workflow/规范模板（替换占位符）→ 8 更新 AGENTS.md 索引
#
# 幂等：可重复运行（标签 --force；文件已存在则跳过并提示）。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/render.sh
source "$SCRIPT_DIR/lib/render.sh"

TARGET="$(pwd)"
ASSUME_YES=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)   TARGET="$2"; shift 2 ;;
    --yes|-y)   ASSUME_YES=1; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --help|-h)  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

log() { echo "==> $*"; }
act() { if [[ "$DRY_RUN" == "1" ]]; then echo "    [dry-run] $*"; else "$@"; fi; }
ask() {
  local __var="$1" prompt="$2" default="$3" ans=""
  if [[ "$ASSUME_YES" == "1" ]]; then eval "$__var=\"\$default\""; return; fi
  # shellcheck disable=SC2034  # ans 经下方 eval 间接赋给调用方指定变量，shellcheck 无法穿透
  read -r -p "$prompt [$default]: " ans || true
  eval "$__var=\"\${ans:-\$default}\""
}

# 校验安装目录是仓库内相对路径（不含 ..）：SKILLS_DIR/DOCS_DIR 会拼进受管文件目标路径，
# 若被填成绝对路径或带 .. 的路径，会把文件装到仓库外（B1）。
cw_check_rel_dir() {
  case "$1" in
    /*|*..*) echo "❌ $2 必须是仓库内相对路径且不含 ..: $1" >&2; exit 1 ;;
  esac
}

command -v gh  >/dev/null || { echo "❌ 需要 gh CLI（brew install gh）" >&2; exit 1; }
command -v git >/dev/null || { echo "❌ 需要 git" >&2; exit 1; }
cd "$TARGET"
git rev-parse --git-dir >/dev/null 2>&1 || { echo "❌ $TARGET 不是 git 仓库" >&2; exit 1; }
# 锁目录放 .git 内部：并发安装/升级互斥（C3）。不用 GIT_DIR 变量名 —— 它是 git 保留环境变量，
# 赋值会静默改变后续 `git -C "$SCRIPT_DIR"` 的仓库解析（update.sh 的 toolkit_source 同因）。
CW_GIT_DIR="$(git rev-parse --git-dir)"
if cw_is_self_target "$(git rev-parse --show-toplevel)"; then
  echo "❌ 拒绝：目标是工具包源自身（$(git rev-parse --show-toplevel)）" >&2
  echo "   受管文件里 16 个的模板源与安装目标同路径，安装会把它们清空；本仓不是自己的消费者。" >&2
  echo "   流程依据直接读 docs/agents/ 与 skills/change-workflow/SKILL.md 即可。" >&2
  exit 1
fi
# 并发互斥锁：mkdir 原子性保证同一时刻只有一个安装/升级进程持有锁（C3）。
# --dry-run 不取锁（预演不落盘），但绝不能因此去删别人的锁 —— 故 trap 必须
# 与取锁同在「非 dry-run」分支内（update.sh:108-115 同构，1.3.1 QA ISSUE-001）。
LOCK_DIR="$CW_GIT_DIR/.change-workflow.lock"
if [[ "$DRY_RUN" != "1" ]]; then
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "❌ 已有另一个升级/安装进程在运行（锁目录存在：${LOCK_DIR}）" >&2
    echo "   确认无其他进程后手动删除该目录再重试。" >&2
    exit 1
  fi
  # trap 只在真正持有锁时设置：dry-run 不取锁，也绝不能碰他人的锁
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
fi

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
[[ -z "$REPO" ]] && { echo "❌ 无法识别 GitHub 仓库（需 gh auth login + origin remote）" >&2; exit 1; }
OWNER="${REPO%%/*}"
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo main)"
# EFFECTIVE_DATE / REPO_ROOT 必须在渲染前作为 shell 变量存在：conf heredoc 里算出的值不会进入
# 当前 shell，install_rendered 的 cw_render 会拿空值替换 {{EFFECTIVE_DATE}}/{{REPO_ROOT}}，导致
# 首装文件缺日期/仓库根路径，且 manifest 基线记的是空值 sha —— 首次 update 因 source conf 拿到
# 真值而重渲染，4 个含这两个占位符的文档全部翻新（1.3.0 实测：code-structure/evidence-capture/
# pr-writing 的生效日期为空、defect-workflow 的 REPO_ROOT 为空）。
EFFECTIVE_DATE="$(date +%F)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
log "仓库: ${REPO}（默认分支 ${DEFAULT_BRANCH}）"

PROJECT_ID="" STATUS_FIELD_ID="" OPT_BACKLOG="" OPT_READY="" OPT_IN_PROGRESS="" OPT_DONE=""
PROJ_ID="$(gh project list --owner "$OWNER" --format json 2>/dev/null \
  | python3 -c 'import json,sys; p=json.load(sys.stdin).get("projects",[]); print(p[0]["id"] if p else "")' 2>/dev/null || true)"
if [[ -n "$PROJ_ID" ]]; then
  PROJECT_ID="$PROJ_ID"
  log "发现 Project 看板: $PROJECT_ID"
  FIELDS="$(gh api graphql -f query="query { node(id: \"$PROJECT_ID\") { ... on ProjectV2 { fields(first:20){ nodes { ... on ProjectV2SingleSelectField { name id options { id name } } } } } } }" 2>/dev/null || true)"
  read -r STATUS_FIELD_ID OPT_BACKLOG OPT_READY OPT_IN_PROGRESS OPT_DONE < <(printf '%s' "$FIELDS" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for f in d["data"]["node"]["fields"]["nodes"]:
    if f and f.get("name")=="Status":
        o={x["name"].lower():x["id"] for x in f.get("options",[])}
        print(f["id"], o.get("backlog",""), o.get("ready",""), o.get("in progress",""), o.get("done",""))
        break
' 2>/dev/null || true)
  [[ -n "$STATUS_FIELD_ID" ]] && log "Status 字段: ${STATUS_FIELD_ID}（Ready=${OPT_READY} Done=${OPT_DONE}）"
else
  log "⚠️  未发现 Project 看板——可稍后手动填 .change-workflow.conf，或先 gh project create"
fi

log "创建标签（幂等）"
mk_label() { act gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force; }
mk_label ready-for-agent       "0E8A16" "已充分定义，可交给 agent 执行"
mk_label needs-triage          "BFDADC" "维护者需先评估"
mk_label needs-info            "D4C5F9" "等待报告者补充信息"
mk_label ready-for-human       "FBCA04" "需要人类决策或实现"
mk_label wontfix               "FFFFFF" "不会修复"
mk_label risk-low              "C2E0C6" "CI 绿自动合并"
mk_label risk-medium           "FEF2C0" "人工确认"
mk_label risk-high             "F9D0C4" "强制人工评审"
mk_label ai-generated          "EDEDED" "AI 生成"
mk_label change-close-pending  "FBCA04" "待 change-workflow 会话启动消费（G4 收尾）"

ask MODULE_LABELS "缺陷票模块标签（逗号分隔）" "module-a,module-b"
IFS=',' read -r -a _mods <<< "$MODULE_LABELS"
for m in "${_mods[@]}"; do m="$(echo "$m" | tr -d ' ')"; [[ -n "$m" ]] && mk_label "$m" "1D76DB" "模块：$m"; done

ask CMD_TYPECHECK "typecheck 命令（留空跳过）" "pnpm -r typecheck"
ask CMD_LINT      "lint 命令（留空跳过）"      "pnpm -r lint"
ask CMD_TEST      "test 命令（留空跳过）"      "pnpm -r test"
ask CMD_E2E       "e2e 命令（可空）"           ""
ask SKILLS_DIR    "skill 安装目录"             ".opencode/skills"
ask DOCS_DIR      "规范文档目录"               "docs/agents"
cw_check_rel_dir "$SKILLS_DIR" "SKILLS_DIR"
cw_check_rel_dir "$DOCS_DIR" "DOCS_DIR"

log "写入 .change-workflow.conf"
if [[ -f .change-workflow.conf ]]; then
  log "⚠️  .change-workflow.conf 已存在——跳过写入（如需重置请先删除）"
elif [[ "$DRY_RUN" == "1" ]]; then
  echo "    [dry-run] 写 .change-workflow.conf"
else
  cw_refuse_symlink ".change-workflow.conf" "配置文件"
  cat > .change-workflow.conf <<EOF
# change-workflow 配置（由 setup.sh 生成于 $(date +%F)）
# 升级工具包：在目标仓库运行 <工具包路径>/update.sh（本文件由 setup/update 共同维护）
TOOLKIT_VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION")"
EFFECTIVE_DATE="$(date +%F)"
REPO="$REPO"
OWNER="$OWNER"
REPO_ROOT="$(git rev-parse --show-toplevel)"
DEFAULT_BRANCH="$DEFAULT_BRANCH"
PROJECT_ID="$PROJECT_ID"
STATUS_FIELD_ID="$STATUS_FIELD_ID"
OPT_BACKLOG="$OPT_BACKLOG"
OPT_READY="$OPT_READY"
OPT_IN_PROGRESS="$OPT_IN_PROGRESS"
OPT_DONE="$OPT_DONE"
LABEL_READY="ready-for-agent"
LABEL_NEEDS_TRIAGE="needs-triage"
LABEL_NEEDS_INFO="needs-info"
LABEL_READY_HUMAN="ready-for-human"
LABEL_WONTFIX="wontfix"
LABEL_RISK_LOW="risk-low"
LABEL_RISK_MEDIUM="risk-medium"
LABEL_RISK_HIGH="risk-high"
LABEL_SOURCE="ai-generated"
LABEL_CLOSURE_PENDING="change-close-pending"
MODULE_LABELS="$MODULE_LABELS"
CMD_TYPECHECK="$CMD_TYPECHECK"
CMD_LINT="$CMD_LINT"
CMD_TEST="$CMD_TEST"
CMD_E2E="$CMD_E2E"
SKILLS_DIR="$SKILLS_DIR"
DOCS_DIR="$DOCS_DIR"
OPENSPEC_ENABLED="$(command -v openspec >/dev/null && echo true || echo false)"
EOF
fi

log "安装文件"
install_rendered() {
  local tpl_rel="$1" dst_rel="$2"
  local dst="${dst_rel/__SKILLS_DIR__/$SKILLS_DIR}"
  dst="${dst/__DOCS_DIR__/$DOCS_DIR}"
  if [[ -e "$dst" ]]; then
    log "⚠️  已存在，跳过: ${dst}（升级已有安装请用 update.sh）"
    return 0
  fi
  act mkdir -p "$(dirname "$dst")"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    [dry-run] 渲染安装 $dst"
  else
    cw_render "$SCRIPT_DIR/$tpl_rel" "$dst"
    _written+=("$dst")
  fi
}

# 本次安装实际写入的文件（install_rendered 对已存在文件会跳过，不记入）。
# 供 manifest 基线区分「本次写入」与「已存在」：只对写入的文件记基线（C1）。
_written=()

while IFS='|' read -r tpl_rel dst_rel; do
  [[ -n "$tpl_rel" ]] || continue
  install_rendered "$tpl_rel" "$dst_rel"
done < <(cw_list_files)

# 受管脚本必须可执行：cw_render 用重定向写文件，不保留执行位。
# 名单由受管清单（cw_list_files）派生，不再硬编码：新增脚本自动获得执行位，避免漏加
# 导致消费仓 `./scripts/<name>.sh` 报 Permission denied（1.2.0 / 1.3.0 两次同因缺陷）。
# chmod 失败不再被 `|| true` 吞掉（F1）；act 包装保证 dry-run 只打印不执行。
cw_chmod_scripts act

# 基线 manifest：记录安装后各受管文件的 sha256，供 update.sh 判定「是否被本地修改」。
# 只对「本次写入」或「与模板字节一致」的文件记基线；已存在且与模板不同的文件**不写基线**
# （可能是本地定制）——否则下次升级会因 current==baseline 判为「未修改」而静默覆盖它（C1，
# 与 update.sh 接管模式同一语义）。
if [[ "$DRY_RUN" != "1" ]]; then
  cw_refuse_symlink ".change-workflow.manifest" "基线清单"
  # manifest 先写临时文件再整体 mv：中途失败不留半截清单（C3）
  _mft_tmp="$(mktemp)"
  while IFS='|' read -r tpl_rel dst_rel; do
    [[ -n "$tpl_rel" ]] || continue
    dst="${dst_rel/__SKILLS_DIR__/$SKILLS_DIR}"
    dst="${dst/__DOCS_DIR__/$DOCS_DIR}"
    [[ -f "$dst" ]] || continue
    # 本次安装写入的文件 → 记基线
    written=0
    for w in "${_written[@]:-}"; do
      if [[ "$w" == "$dst" ]]; then written=1; break; fi
    done
    if [[ "$written" == "1" ]]; then
      printf '%s  %s\n' "$(cw_sha "$dst")" "$dst" >> "$_mft_tmp"
      continue
    fi
    # 已存在：与模板字节一致 → 幂等重装，记基线；不同 → 本地定制，不写基线
    tmp="$(mktemp)"
    cw_render "$SCRIPT_DIR/$tpl_rel" "$tmp"
    if cmp -s "$tmp" "$dst"; then
      printf '%s  %s\n' "$(cw_sha "$dst")" "$dst" >> "$_mft_tmp"
    else
      log "⚠️  已存在且与模板不同，不写基线: ${dst}（本地定制；升级时 update.sh 会按冲突处理）"
    fi
    rm -f "$tmp"
  done < <(cw_list_files)
  mv "$_mft_tmp" .change-workflow.manifest
fi

if [[ -f AGENTS.md ]] && ! grep -q "change-workflow" AGENTS.md; then
  log "更新 AGENTS.md 索引"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    [dry-run] 追加 change-workflow 索引段到 AGENTS.md"
  else
    cat >> AGENTS.md <<'EOF'

### Change workflow（变更流程 gate）

启动新 change、接手进行中 change、拆票、提交/PR、收尾与归档，一律经 `.opencode/skills/change-workflow/`（G0-G4 五 gate + fix-first 自愈回路）。拆票/commit/闭环规范见 `docs/agents/task-tracking.md`（1 task = 1 ticket，1 issue = 1 PR）；看板入列 API 见 `docs/agents/project-board.md`。缺陷流程见 `docs/agents/defect-workflow.md`。

> 配置：`.change-workflow.conf`（看板 ID / 标签 / 门禁命令 / 目录约定）；升级工具包：`<工具包路径>/update.sh`。

### Quality gates（质量门禁）

任何 change / 缺陷修复的**票内容与完成判据**必须满足 `docs/agents/quality-gates.md`：**QG-1..QG-7**（变更开发侧）+ **DQ-1..DQ-8**（缺陷处理侧）。

**变更侧核心三条**：

- **QG-1 用户层 AC**：面向用户的票，AC 必须含浏览器可观测陈述；AC 能在不改应用层的前提下被满足 → 票切错了
- **QG-2 e2e 绑定**：用户可见变更必须新增/扩展 e2e 规格，否则票上须标 `no-ui-impact`
- **QG-5 独立验证**：完成声明必须附**验证者自己探针的原始输出**；「测试通过」是结论不是证据，不予采信

**缺陷侧核心三条**：

- **DQ-1 triage 不可跳过**：开工前三条件齐备（移除 `needs-triage` + 加 `ready-for-agent` + 票上有 triage brief 评论），缺一禁止开工
- **DQ-2 根因独立确认**：票面的「修复方向」是**假设不是结论**；与实测不符须在票上更正
- **DQ-3 先红后绿**：修复前必须有可复现的失败证据并粘贴到票上；未附「红」不予合并

> 由来：一次真实交付失败的复盘 —— 9 个 PR 中 8 个对应用层与 e2e 双双零改动，12 张票全打勾、CI 全绿，而用户打开页面看不到任何变化；缺陷侧随后暴露 4 个「自测全绿但实际无效」的假修复（4/4 由独立探针推翻）。完整条目见 `docs/agents/quality-gates.md`。
EOF
  fi
elif [[ ! -f AGENTS.md ]]; then
  log "⚠️  无 AGENTS.md——建议创建并在其中索引 change-workflow"
fi

log "安装完成 ✅"
cat <<EOF

后续步骤：
  1. 检查 .change-workflow.conf（尤其 PROJECT_ID/OPT_* 若为空需手动补）
  2. 提交：git add -A && git commit -m "chore: adopt change-workflow"
  3. 开 PR 合并（首个子票即可验证全流程）
  4. 可选：CI 需开启 workflow 写权限（Settings → Actions → Workflow permissions: Read and write）

依赖：gh CLI、git、python3（看板字段发现）；openspec CLI（可选，OPENSPEC_ENABLED=false 时降级）
EOF
