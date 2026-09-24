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
# 为什么弃用 sed：sed 替换值是个微型语言（`&` = 整个匹配、`|` = 分隔符、`\` = 转义），
# 合法目录名 `REPO_ROOT=/tmp/a&b` 会被静默渲染成 `/tmp/a{{REPO_ROOT}}b`（& 展开成占位符本身），
# `REPO_ROOT=/tmp/a|b` 则直接摧毁 sed 命令（bad flag in substitute command）—— 两者都是合法路径，
# 曾使渲染产物与预期逐字节不符且难以察觉。bash 参数展开做的是**纯字面量**替换，无此微型语言。
# 注意：花括号必须写成 `\{\{REPO\}\}` 转义形态 —— bash 先做 brace expansion，
# 未转义的 `${out//{{REPO}}/x}` 会被展开成垃圾（本机 bash 3.2 实测），不要"简化"掉反斜杠。
cw_substitute() {
  local line out
  while IFS= read -r line || [[ -n "$line" ]]; do
    out="$line"
    out="${out//\{\{REPO\}\}/${REPO:-}}"
    out="${out//\{\{OWNER\}\}/${OWNER:-}}"
    out="${out//\{\{DEFAULT_BRANCH\}\}/${DEFAULT_BRANCH:-main}}"
    out="${out//\{\{REPO_ROOT\}\}/${REPO_ROOT:-}}"
    out="${out//\{\{EFFECTIVE_DATE\}\}/${EFFECTIVE_DATE:-}}"
    out="${out//\{\{PROJECT_ID\}\}/${PROJECT_ID:-}}"
    out="${out//\{\{STATUS_FIELD_ID\}\}/${STATUS_FIELD_ID:-}}"
    out="${out//\{\{OPT_BACKLOG\}\}/${OPT_BACKLOG:-}}"
    out="${out//\{\{OPT_READY\}\}/${OPT_READY:-}}"
    out="${out//\{\{OPT_IN_PROGRESS\}\}/${OPT_IN_PROGRESS:-}}"
    out="${out//\{\{OPT_DONE\}\}/${OPT_DONE:-}}"
    printf '%s\n' "$out"
  done
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

# 拒绝写入符号链接：受管文件若被替换成符号链接（指向仓库外或 .git 内），重定向/覆盖会
# 穿透链接写穿到链接指向处，绕过「只改受管文件」的边界（C2）。所有受管写入面
# （cw_render 重定向、cp 安装、manifest/conf 重写）必须先过这道闸。
cw_refuse_symlink() {
  local path="$1" desc="$2" d
  # leaf 检查（原有）：文件本身是符号链接 → 拒绝
  if [[ -L "$path" ]]; then
    echo "❌ 拒绝写入符号链接：${desc}（${path}）" >&2
    echo "   受管文件必须是普通文件；请先删除该符号链接或改回真实文件。" >&2
    exit 1
  fi
  # 相对路径逐级组件检查（C2 补强）：父目录被换成符号链接时，mkdir -p 与重定向会
  # 穿透链接写穿到链接指向处（红证：rm -rf scripts; ln -s ../outside scripts → 仓外落地 4 个脚本）。
  # 绝对路径（如 mktemp 的 /var/folders 源）只查 leaf：系统目录本身就有符号链接
  # （/var → /private/var），逐级检查会误伤。
  case "$path" in
    /*) return 0 ;;
  esac
  d="$(dirname "$path")"
  while [[ "$d" != "." && "$d" != "/" && -n "$d" ]]; do
    if [[ -L "$d" ]]; then
      echo "❌ 拒绝写入符号链接：${desc} 的父目录组件（${d}）" >&2
      echo "   受管文件必须是普通文件；请先删除该符号链接或改回真实目录。" >&2
      exit 1
    fi
    d="$(dirname "$d")"
  done
  return 0
}

# 渲染：模板 → 目标文件（剥头 + 替换占位符）
cw_render() {
  local src="$1" dst="$2"
  if [[ ! -f "$src" ]]; then
    echo "❌ 模板不存在: $src" >&2
    return 1
  fi
  # 源与目标同一文件时禁止：下方 `> "$dst"` 会先截断文件，左管道再读就只剩空 → 模板被清空归零。
  # 触发场景：把工具包自身当安装目标（模板源与安装目标同路径）。
  if [[ -e "$dst" && "$src" -ef "$dst" ]]; then
    echo "❌ 拒绝把模板渲染到自身（会清空文件）: $src" >&2
    return 1
  fi
  # 符号链接目标同样会穿透重定向写穿到链接指向处（C2）
  cw_refuse_symlink "$dst" "渲染目标"
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

# 读文件权限位（八进制，如 644）。双实现（与 cw_sha 同构）：
# macOS/BSD stat 用 -f %Lp；Linux/GNU stat 用 -c %a，输出同为 octal mode。
cw_file_mode() {
  case "$(uname -s)" in
    Darwin) stat -f %Lp "$1" ;;
    *)      stat -c %a "$1" ;;
  esac
}

# 把「即将 mv 覆盖到 dst 的临时文件」调成 dst 应有的模式（R1 模式保持，唯一策略实现）。
# 为什么必须显式调：mktemp 建出的文件恒为 0600，mv 会把这个 0600 原样带进目标 ——
# 首装 docs 变 600、脚本经 chmod +x 变 711；覆盖安装还会把原本 644 的文件（含 conf、
# manifest）悄悄改成 600（红证：update 一次后 .change-workflow.conf 644→600）。
# 规则：dst 已存在 → 沿用其现有模式（尊重用户设定，不擅自放宽也不收紧）；
#       dst 新建   → 0644（受管脚本随后由 cw_chmod_scripts 补 +x → 755）。
# stat 失败兜底 644：宁按默认模式写，也不写 600（600 会让消费仓其他用户/CI 读不到）。
cw_tmp_mode_for() {
  local tmp="$1" dst="$2" mode=""
  if [[ -e "$dst" ]]; then
    mode="$(cw_file_mode "$dst" 2>/dev/null)" || mode=""
  fi
  chmod "${mode:-0644}" "$tmp"
}

# 目标仓是否为工具包源自身（自我安装）。工具包里 18 个受管文件有 16 个的模板源与安装目标
# 同路径（docs/agents/*.md、scripts/*.sh），自我安装会清空模板，并把模板记成受管基线
# （此后每次改模板都报冲突）。故 setup/update 在动任何东西之前一律拒绝。
cw_is_self_target() {
  local a b
  a="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  b="$(cd "$CW_ROOT" 2>/dev/null && pwd -P)" || return 1
  [[ "$a" == "$b" ]]
}

# 受管文件清单：所有会从工具包安装/更新的目标文件（相对仓库根）。
# 格式：<模板相对 CW_ROOT 的路径>|<目标相对仓库根的路径>
# 目录类占位符（__SKILLS_DIR__ / __DOCS_DIR__）由调用方按 conf 替换。
cw_list_files() {
  echo "skills/change-workflow/SKILL.md|__SKILLS_DIR__/change-workflow/SKILL.md"
  echo "scripts/pr-automation.sh|scripts/pr-automation.sh"
  echo "scripts/cw-update.sh|scripts/cw-update.sh"
  echo "workflows/change-closure-signal.yml|.github/workflows/change-closure-signal.yml"
  echo "scripts/cw-evidence.sh|scripts/cw-evidence.sh"
  echo "scripts/cw-greploop.sh|scripts/cw-greploop.sh"
  local f base
  for f in "$CW_ROOT"/docs/agents/*.md; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    # AGENTS.md 是目录级知识库（给 agent 读的规则文本），不是规范模板 → 不装进消费仓
    [[ "$base" == "AGENTS.md" ]] && continue
    echo "docs/agents/$base|__DOCS_DIR__/$base"
  done
}

# 原子复制：先写同目录临时文件再 mv，避免中途失败留下半截文件（C3）。
# 源与目标都拒绝符号链接（C2）：源若是链接说明受管文件被替换过，目标若是链接会写穿。
# setup.sh 无 cp 安装面，此函数供 update.sh 的 7 处受管写入用。
cw_atomic_cp() {
  local src="$1" dst="$2" tmp
  cw_refuse_symlink "$src" "复制源"
  cw_refuse_symlink "$dst" "复制目标"
  mkdir -p "$(dirname "$dst")"
  tmp="$(mktemp "$(dirname "$dst")/.cw-tmp.XXXXXX")"
  if ! cp "$src" "$tmp"; then
    rm -f "$tmp"
    echo "❌ 复制失败：$src → $dst" >&2
    return 1
  fi
  # 模式保持（R1）：见 cw_tmp_mode_for 的根因注释。
  # 失败路径清理（F9）：chmod/mv 失败在 set -e 下会直接中止调用方，旧写法把 .cw-tmp.*
  # 永久遗留在受管目录（红证：故障注入假 mv → dst 目录残留 .cw-tmp.XXXX）。
  # 显式捕获 → 删临时文件 → return 1，让「原子写」名副其实（失败不留半成品）。
  cw_tmp_mode_for "$tmp" "$dst" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$dst" || { rm -f "$tmp"; return 1; }
}

# 给受管脚本补执行位（cw_render 用重定向写文件，不保留执行位）。
# 名单由受管清单（cw_list_files）派生，不再硬编码：新增脚本自动获得执行位，避免漏加
# 导致消费仓 `./scripts/<name>.sh` 报 Permission denied（1.2.0 / 1.3.0 两次同因缺陷）。
# 可选 wrapper（如 setup.sh 的 act）用于 dry-run 打印；chmod 失败不再被 `|| true` 吞掉（F1）。
cw_chmod_scripts() {
  local wrapper="${1:-}" _tpl dst_rel
  while IFS='|' read -r _tpl dst_rel; do
    case "$dst_rel" in
      scripts/*.sh)
        cw_refuse_symlink "$dst_rel" "受管脚本"
        [[ -f "$dst_rel" ]] || continue
        if [[ -n "$wrapper" ]]; then
          "$wrapper" chmod +x "$dst_rel" || { echo "❌ chmod +x 失败：$dst_rel" >&2; return 1; }
        else
          chmod +x "$dst_rel" || { echo "❌ chmod +x 失败：$dst_rel" >&2; return 1; }
        fi
        ;;
    esac
  done < <(cw_list_files)
}

# 从 conf 读取键值（B1：替代 `source "$CONF"`，杜绝值内命令注入）。
# 统一规范（F6+F8）：本实现与三份独立副本（scripts/cw-update.sh、scripts/pr-automation.sh、
# scripts/cw-greploop.sh 的 conf_get）**逐字同语义**，改一处必同步四处，漏一处即漂移
# （红证：副本先剥 # 后剥引号 → `"https://host/r#frag"` 返回悬空引号 `"https://host/r`；
# lib 不剥行内注释 → `SKILLS_DIR=.opencode/skills # 注释` 会把文件装进垃圾目录；
# lib 不剥 \r → CRLF conf 取值带回车）。回归锁在 test/install-update-e2e.sh 用例 22。
# 规范：1) `#` 开头的整行注释跳过；2) 原始值 = 首个 `=` 之后的全部文本；3) 去尾部 \r；
#       4) 值被**成对**的 " 或 ' 包裹（首尾同引号且长度≥2）→ 剥掉这对引号，内部 # 原样保留；
#          否则仅在「空白 + #」处截断行内注释（`x # c` → `x`；无空白的 `r#frag` 保留）；
#       5) 去尾部空白；6) 输出。键不存在返回 1（调用方置空）。
# 注意：不能截断空格 —— `SKILLS_DIR="My Skills"` 这类含空格的值必须原样保留。
cw_conf_get() {
  local file="$1" key="$2" line v
  [[ -f "$file" ]] || return 1
  # 末行无换行守卫（S1）：conf 若以无结尾换行的行收尾（编辑器截断 / printf 漏 \n），
  # 裸 read 对末行返回非 0 → 旧循环直接丢弃该行 → 末行键取值失败（红证：rc=1/空）。
  # 与孪生副本（cw-greploop.sh / cw-update.sh 的 conf_get）一致；漏一处即行为漂移。
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      \#*) continue ;;
    esac
    # 锚定行首（1.3.1 QA ISSUE-002）：子串匹配 *"$key="* 会被诱饵行误命中
    # （如 OLD_REPO= 在 REPO= 之前先子串命中 REPO=），故键必须位于行首。
    case "$line" in
      "$key"=*) v="${line#*=}" ;;
      *) continue ;;
    esac
    v="${v%$'\r'}"
    if [[ ${#v} -ge 2 && ${v:0:1} == '"' && ${v: -1} == '"' ]]; then
      v="${v:1:${#v}-2}"
    elif [[ ${#v} -ge 2 && ${v:0:1} == "'" && ${v: -1} == "'" ]]; then
      v="${v:1:${#v}-2}"
    else
      v="${v%%[[:space:]]#*}"
    fi
    v="${v%"${v##*[![:space:]]}"}"
    printf '%s\n' "$v"
    return 0
  done < "$file"
  return 1
}
