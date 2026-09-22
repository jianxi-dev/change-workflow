#!/usr/bin/env bash
# =============================================================================
# cw-greploop.sh — Greptile 审查闭环包装器（由工具包安装到 scripts/cw-greploop.sh）
#
# 用法:
#   ./scripts/cw-greploop.sh --pr 42                     # 打印 PR #42 的闭环协议
#   ./scripts/cw-greploop.sh --pr 42 --max-iterations 5  # 收紧迭代上限（默认 10）
#   ./scripts/cw-greploop.sh --pr 42 --vcs github        # 平台覆盖（缺省本地探测）
#   ./scripts/cw-greploop.sh --pr 42 --dry-run           # 只打印将执行的循环与退出条件
#   ./scripts/cw-greploop.sh --help                      # 本用法（退出码 0）
#
# 定位: G2（PR 创建后 → risk-medium/high 合并确认前）的审查闭环。
#   本脚本只做「能力检测 + 协议打印」，不复制 greploop skill 的 API/GraphQL 细节，
#   也不触发 Greptile 审查；真正的循环由 agent 依据 greploop skill 执行。
#
# 为什么退出条件必须是「满分（5/5）且零未解决评论」:
#   评分一旦允许「4/5 也算过」，agent 就会在临界分上停手；「差不多就行」
#   会沉淀成技术债并污染后续 PR 的审查基线。满分与零评论是合取条件，
#   同时堵住「评分满分但评论仍挂着」的假闭环。
#
# 为什么无 Greptile 时降级而不是硬失败:
#   本工具包对所有外部依赖（gh / openspec / skills）的姿态都是「缺失降级」。
#   审查的价值来自独立第二意见，Greptile 只是其中一种实现；缺失时硬失败
#   只会逼 agent 绕过整个审查环节。降级 = 本地审查闭环（code-review / review
#   + 人工清单），并在 PR 上显式标注「审查闭环降级为人工」。
#   评分绝不伪造: 没有评分来源就如实报告没有。
#
# 退出码: 0 = 已打印协议或降级指引；1 = 参数错误 / 缺少无法自动检测的前提。
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# --- 载入项目配置（可选）-----------------------------------------------------
# 目标项目根放置 .change-workflow.conf（由 setup.sh 生成）；本脚本只取 SKILLS_DIR
# 等目录约定。cd 在 source 之前完成，避免被 conf 里的 REPO_ROOT 带偏。
CONF="$REPO_ROOT/.change-workflow.conf"
if [[ -f "$CONF" ]]; then
  # shellcheck disable=SC1090
  source "$CONF"
fi
SKILLS_DIR="${SKILLS_DIR:-.opencode/skills}"

MAX_ITERATIONS="10"
PR=""
VCS=""
DRY_RUN=false

usage() {
  sed -n '3,/^# ===/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
  exit 0
}

die() {
  echo "❌ $1" >&2
  exit 1
}

# --- 参数解析（bash 3.2 兼容: 手写 while + case，不用 getopt）----------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      [[ $# -ge 2 ]] || die "--pr 缺少参数值"
      PR="$2"
      shift 2
      ;;
    --max-iterations)
      [[ $# -ge 2 ]] || die "--max-iterations 缺少参数值"
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --vcs)
      [[ $# -ge 2 ]] || die "--vcs 缺少参数值"
      VCS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      die "未知参数: ${1}（--help 查看用法）"
      ;;
  esac
done

# --- 参数校验 ----------------------------------------------------------------
if [[ -n "$PR" ]]; then
  case "$PR" in
    *[!0-9]*) die "--pr 必须是数字: ${PR}" ;;
  esac
fi
case "$MAX_ITERATIONS" in
  ''|*[!0-9]*) die "--max-iterations 必须是正整数: ${MAX_ITERATIONS}" ;;
esac
if [[ "$MAX_ITERATIONS" -lt 1 ]]; then
  die "--max-iterations 必须大于 0: ${MAX_ITERATIONS}"
fi
if [[ -n "$VCS" ]]; then
  case "$VCS" in
    github|gitlab|perforce) : ;;
    *) die "--vcs 只支持 github|gitlab|perforce: ${VCS}" ;;
  esac
fi

# --- 平台探测（缺省本地探测，不发网络请求）-----------------------------------
# 上游 greploop 的检测顺序是 p4 → gitlab → github；p4 探测（p4 info）会连服务端，
# 本脚本改为本地 git remote 探测: 含 gitlab → gitlab，否则 github。
# Perforce 无法本地静默判定，需显式 --vcs perforce。
detect_vcs() {
  local url url_lc
  url="$(git remote get-url origin 2>/dev/null || true)"
  url_lc="$(printf '%s' "$url" | tr '[:upper:]' '[:lower:]')"
  case "$url_lc" in
    *gitlab*) echo "gitlab" ;;
    *) echo "github" ;;
  esac
}

VCS_SOURCE="--vcs 显式指定"
if [[ -z "$VCS" ]]; then
  VCS="$(detect_vcs)"
  VCS_SOURCE="本地探测（git remote origin）"
fi

# --- 能力检测 ----------------------------------------------------------------
# 候选路径: 项目 SKILLS_DIR（conf，默认 .opencode/skills）→ 项目常见 agent 目录
# → 用户级目录。只探测含 greploop/SKILL.md 的目录，不猜能力、不伪造可用。
detect_greploop_skill() {
  local d
  for d in "$@"; do
    if [[ -n "$d" && -f "$d/greploop/SKILL.md" ]]; then
      printf '%s\n' "$d/greploop"
      return 0
    fi
  done
  return 1
}

GREPLOOP_SKILL="$(detect_greploop_skill "$SKILLS_DIR" ".opencode/skills" ".claude/skills" ".agents/skills" \
  "$HOME/.config/opencode/skills" "$HOME/.claude/skills" "$HOME/.agents/skills")" || GREPLOOP_SKILL=""

# 展示用候选清单: SKILLS_DIR 与固定项重复时不重复列出（默认值即 .opencode/skills）
SKILL_CANDIDATES=".opencode/skills / .claude/skills / .agents/skills / 用户级 skills 目录"
case "$SKILLS_DIR" in
  .opencode/skills|.claude/skills|.agents/skills) : ;;
  *) SKILL_CANDIDATES="${SKILLS_DIR} / ${SKILL_CANDIDATES}" ;;
esac

# gh 认证探测（只读检查；轮询与 resolve 依赖它）。未认证不报错，走降级。
GH_OK=false
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    GH_OK=true
  fi
fi

# --- PR 目标 ----------------------------------------------------------------
PR_LABEL=""
PR_NOTE=""
if [[ -n "$PR" ]]; then
  PR_LABEL="#${PR}"
elif [[ "$GH_OK" = true ]]; then
  PR_LABEL="（未指定，执行时自动检测当前分支）"
  PR_NOTE="gh pr view --json number -q .number"
else
  PR_LABEL="（未指定）"
fi

# --- 打印函数 ----------------------------------------------------------------
print_loop_protocol() {
  echo "    1. 触发    push 最新提交后触发 Greptile 审查（GitHub 由 Greptile App 触发；其它平台按 greploop skill）"
  echo "    2. 轮询    轮询评审 check-run，直到本轮评审完成"
  echo "    3. 抓取    读取评分（x/5）与全部未解决评论"
  echo "    4. 修复    逐条修复可行动评论（不做「差不多就行」的取舍）"
  echo "    5. 收敛    resolve 已处理的 review thread"
  echo "    6. 重触发  提交并 push → 回到第 1 步"
}

print_exit_conditions() {
  echo "    - 评分 = 5/5 且 未解决评论 = 0 → 闭环成功"
  echo "    - 或 已达 --max-iterations 上限（本次: ${MAX_ITERATIONS}）→ 停止并报告当前状态（不得视为通过）"
}

print_apps_note() {
  echo "    由 greploop skill 文档化引用，本脚本不单列；要点:"
  echo "    - 普通触发被告知「文件数超限」→ 换触发身份重新触发"
  echo "    - check-run 不出现 → 改为轮询被编辑的 summary 评论"
}

print_degrade() {
  echo ""
  echo "==> 降级: 审查闭环转为本地人工（不伪造评分，不阻塞交付）"
  if [[ -z "$GREPLOOP_SKILL" ]]; then
    echo "    原因: 未找到 greploop skill"
  fi
  if [[ "$GH_OK" != true ]]; then
    echo "    原因: gh 未认证（轮询与 resolve 不可用）"
  fi
  echo "    本地审查闭环:"
  echo "      1. code-review（Standards + Spec 双轴自审）"
  echo "      2. review（pre-landing 结构审查）"
  echo "      3. 人工清单: 逐条走查 PR diff，记录未解决项并在 PR 中回复"
  echo ""
  echo "==> 硬性要求: 在 PR 上显式标注「审查闭环降级为人工」，再进入合并流程。"
  echo "==> risk-medium/high 的合并仍需人工确认；无 Greptile 不阻塞交付。"
}

# --- 输出 --------------------------------------------------------------------
echo "==> cw-greploop: Greptile 审查闭环包装器（G2 审查阶段）"
echo "==> 目标 PR: ${PR_LABEL}"
if [[ -n "$PR_NOTE" ]]; then
  echo "    自动检测命令: ${PR_NOTE}"
fi
if [[ -z "$PR" && "$GH_OK" != true ]]; then
  echo "⚠️  未提供 --pr 且 gh 不可用（无法自动检测）—— 执行前必须显式提供 --pr <N>"
fi
echo "==> 平台: ${VCS}（${VCS_SOURCE}）"
echo "==> 迭代上限: ${MAX_ITERATIONS}"
echo "==> 能力检测:"
if [[ -n "$GREPLOOP_SKILL" ]]; then
  echo "    ✅ greploop skill: 找到（${GREPLOOP_SKILL}）"
else
  echo "    ⚠️  greploop skill: 未找到（候选: ${SKILL_CANDIDATES}）"
fi
if [[ "$GH_OK" = true ]]; then
  echo "    ✅ gh 认证: 通过"
else
  echo "    ⚠️  gh 认证: 未通过（轮询与 resolve 不可用）"
fi

if [[ "$DRY_RUN" = true ]]; then
  echo ""
  echo "[dry-run] 未执行任何动作；以下为将执行的循环协议与退出条件"
  echo ""
  echo "==> 循环协议（由 agent 依据 greploop skill 执行；本脚本不复制其逻辑）:"
  print_loop_protocol
  echo ""
  echo "==> 退出条件:"
  print_exit_conditions
  echo ""
  echo "==> greploop-apps（超大 PR 变体）:"
  print_apps_note
  echo ""
  if [[ -n "$GREPLOOP_SKILL" && "$GH_OK" = true ]]; then
    echo "[dry-run] 能力检测通过 → 实际执行走 greploop skill 循环"
  else
    echo "[dry-run] 能力检测未通过 → 实际执行将走降级路径:"
    print_degrade
  fi
  exit 0
fi

if [[ -n "$GREPLOOP_SKILL" && "$GH_OK" = true ]]; then
  echo ""
  echo "==> 循环协议（由 agent 依据 greploop skill 执行；本脚本不复制其逻辑）:"
  print_loop_protocol
  echo ""
  echo "==> 退出条件:"
  print_exit_conditions
  echo ""
  echo "==> greploop-apps（超大 PR 变体）:"
  print_apps_note
  echo ""
  echo "==> 下一步: agent 依据 greploop skill 执行上述循环，直到退出条件满足。"
else
  print_degrade
fi
