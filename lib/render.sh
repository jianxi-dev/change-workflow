#!/usr/bin/env bash
# =============================================================================
# change-workflow 共享渲染库
#
# 占位符替换与模板头剥离的**唯一实现** —— 供 setup.sh（首装）与 update.sh（升级）共用，
# 避免两处逻辑漂移（历史教训：同一替换逻辑写两遍，升级路径与安装路径产出不一致）。
#
# 用法：
#   source lib/render.sh
#   cw_list_files                 # 列出所有受管文件（相对路径）
#   cw_render <模板> <输出>        # 剥离模板头 + 替换占位符
#   cw_sha <文件>                  # 输出 sha256
#
# 依赖环境变量（通常 source .change-workflow.conf 后可用）：
#   REPO OWNER DEFAULT_BRANCH PROJECT_ID STATUS_FIELD_ID
#   OPT_BACKLOG OPT_READY OPT_IN_PROGRESS OPT_DONE REPO_ROOT EFFECTIVE_DATE
# =============================================================================

# 工具包根目录（本文件所在目录的上级）。所有模板路径以此为基准，不依赖调用方的 CWD。
CW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 占位符替换表。新增占位符时**只改这里**。
cw_substitute() {
  sed \
    -e "s|{{REPO}}|${REPO:-}|g" \
    -e "s|{{OWNER}}|${OWNER:-}|g" \
    -e "s|{{DEFAULT_BRANCH}}|${DEFAULT_BRANCH:-main}|g" \
    -e "s|{{REPO_ROOT}}|${REPO_ROOT:-}|g" \
    -e "s|{{EFFECTIVE_DATE}}|${EFFECTIVE_DATE:-}|g" \
    -e "s|{{PROJECT_ID}}|${PROJECT_ID:-}|g" \
    -e "s|{{STATUS_FIELD_ID}}|${STATUS_FIELD_ID:-}|g" \
    -e "s|{{OPT_BACKLOG}}|${OPT_BACKLOG:-}|g" \
    -e "s|{{OPT_READY}}|${OPT_READY:-}|g" \
    -e "s|{{OPT_IN_PROGRESS}}|${OPT_IN_PROGRESS:-}|g" \
    -e "s|{{OPT_DONE}}|${OPT_DONE:-}|g"
}

# 剥离模板头（面向模板读者的 HTML 注释），并去掉其后的前导空行。
# 模板头仅存在于工具包模板中，安装到目标仓库后不应出现。
cw_strip_header() {
  awk '
    /^<!-- change-workflow 工具包模板/ { in_hdr = 1; next }
    in_hdr && /-->/                     { in_hdr = 0; next }
    in_hdr                              { next }
    { print }
  ' | awk 'NF == 0 && !body { next } { body = 1; print }'
}

# 渲染：模板 → 目标文件（剥头 + 替换占位符）
cw_render() {
  local src="$1" dst="$2"
  if [[ ! -f "$src" ]]; then
    echo "❌ 模板不存在: $src" >&2
    return 1
  fi
  mkdir -p "$(dirname "$dst")"
  cw_strip_header < "$src" | cw_substitute > "$dst"
}

cw_sha() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

# 受管文件清单：所有会从工具包安装/更新的目标文件（相对仓库根）。
# 格式：<模板相对 CW_ROOT 的路径>|<目标相对仓库根的路径>
# 目录类占位符（__SKILLS_DIR__ / __DOCS_DIR__）由调用方按 conf 替换。
cw_list_files() {
  echo "skills/change-workflow/SKILL.md|__SKILLS_DIR__/change-workflow/SKILL.md"
  echo "scripts/pr-automation.sh|scripts/pr-automation.sh"
  echo "scripts/cw-update.sh|scripts/cw-update.sh"
  echo "workflows/change-closure-signal.yml|.github/workflows/change-closure-signal.yml"
  local f base
  for f in "$CW_ROOT"/docs/agents/*.md; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    echo "docs/agents/$base|__DOCS_DIR__/$base"
  done
}
