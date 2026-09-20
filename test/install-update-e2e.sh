#!/usr/bin/env bash
# =============================================================================
# change-workflow 安装/升级 端到端测试
#
# 全程在临时目录中用**本地 git 仓库**演练，不需要 GitHub 凭证、不联网、不改动任何真实仓库。
# 覆盖：首装 / 幂等 / 本地冲突 / 冲突持续 / 模板演进 / --force / --check / --dry-run /
#       --adopt 接管（模拟 1.0.0 时代安装）/ 一致性（模板头、占位符、仓库特有值残留）
#
# 用法: ./test/install-update-e2e.sh
# 退出码: 0 全过；1 有失败
# =============================================================================
set -euo pipefail

CW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
FAILED_NAMES=()

# 每个用例独立临时根，退出时清理
sanitize() { rm -rf "$1" 2>/dev/null || true; }

ok() {
  local name="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✅ $name: $actual"; PASS=$((PASS + 1))
  else
    echo "  ❌ $name: 实际=$actual 期望=$expected"; FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
  fi
}

new_repo() {
  local dir="$1"
  mkdir -p "$dir" || return 1
  cd "$dir" || return 1
  git init -q
  # 用 -c 传身份而非依赖全局配置：CI runner 无 git identity，
  # 裸 `git commit` 会以 "empty ident name" 失败（本机有全局配置时不会暴露）。
  git -c user.name="change-workflow-test" -c user.email="test@example.invalid" \
      commit -q --allow-empty -m init
}

write_conf() {
  local version="$1"
  cat > .change-workflow.conf <<EOF
TOOLKIT_VERSION="$version"
EFFECTIVE_DATE="2026-01-01"
REPO="acme/demo"
OWNER="acme"
DEFAULT_BRANCH="main"
PROJECT_ID="PVT_demo"
STATUS_FIELD_ID="PVTSSF_demo"
OPT_BACKLOG="b1" OPT_READY="r1" OPT_IN_PROGRESS="p1" OPT_DONE="d1"
SKILLS_DIR=".opencode/skills"
DOCS_DIR="docs/agents"
EOF
}

# 把目标仓库的版本回退，以便重复触发 update 流程（幂等/演进/冲突等用例需要）
set_version() {
  local tmp; tmp="$(mktemp)"
  sed "s|^TOOLKIT_VERSION=.*|TOOLKIT_VERSION=\"$1\"|" .change-workflow.conf > "$tmp"
  mv "$tmp" .change-workflow.conf
}

echo "=============================================="
echo " change-workflow 安装/升级 端到端测试"
echo " 工具包: $CW_ROOT ($(tr -d '[:space:]' < "$CW_ROOT/VERSION"))"
echo "=============================================="

# ── 用例 1：首装 ─────────────────────────────────────────────────────────────
echo ""
echo "[1] 首装"
B1="$(mktemp -d)"; new_repo "$B1/repo" || { echo "无法建立测试仓库"; exit 1; }
write_conf "1.0.0"; touch .change-workflow.manifest
"$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1; ok "退出码" "$?" "0"
ok "docs/agents 文件数" "$(ls docs/agents/*.md 2>/dev/null | wc -l | tr -d ' ')" "9"
ok "SKILL 已安装" "$([[ -f .opencode/skills/change-workflow/SKILL.md ]] && echo y)" "y"
ok "pr-automation 可执行" "$([[ -x scripts/pr-automation.sh ]] && echo y)" "y"
ok "manifest 行数" "$(wc -l < .change-workflow.manifest | tr -d ' ')" "12"
ok "conf 版本已更新" "$(grep -o "$(tr -d '[:space:]' < "$CW_ROOT/VERSION")" .change-workflow.conf | head -1)" "$(tr -d '[:space:]' < "$CW_ROOT/VERSION")"
ok "无残留占位符" "$(grep -rho '{{[A-Z_]*}}' docs/agents/ .opencode/skills/ 2>/dev/null | sort -u | wc -l | tr -d ' ')" "0"

# ── 用例 2：幂等 ─────────────────────────────────────────────────────────────
echo ""
echo "[2] 幂等（版本回退后重跑）"
set_version "1.0.0"
# 不可用 `cmd | grep -q`：grep -q 命中即关管道 → 上游收 SIGPIPE(141) → pipefail 判失败 → set -e 终止。
out2="$("$CW_ROOT/update.sh" --target "$PWD" 2>&1 || true)"
case "$out2" in *"已最新 12"*) r2=0 ;; *) r2=1 ;; esac
ok "无变更" "$r2" "0"

# ── 用例 3：本地修改 → 冲突 ──────────────────────────────────────────────────
echo ""
echo "[3] 本地修改 → 冲突"
echo "## 本地定制" >> docs/agents/triage-labels.md
set_version "1.0.0"
# 期望非 0 退出码：必须显式捕获，否则 `cmd; ok "$?"` 会被 set -e 在 ok 之前中止
rc3=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc3=$?
ok "退出码" "$rc3" "1"
ok ".new 旁路生成" "$([[ -f docs/agents/triage-labels.md.new ]] && echo y)" "y"
ok "本地内容未被覆盖" "$(grep -c '## 本地定制' docs/agents/triage-labels.md)" "1"
ok ".new 为新版本内容" "$(grep -c '## 本地定制' docs/agents/triage-labels.md.new)" "0"

# ── 用例 4：冲突持续（基线未更新）────────────────────────────────────────────
echo ""
echo "[4] 冲突持续报告（基线不被静默接受）"
set_version "1.0.0"
rc4=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc4=$?
ok "再次仍报冲突" "$rc4" "1"

# ── 用例 5：模板演进（未修改文件自动同步）────────────────────────────────────
echo ""
echo "[5] 模板演进"
cp -R "$CW_ROOT" "$B1/tk2"
echo "" >> "$B1/tk2/docs/agents/domain.md"
echo "## vNEXT 演进测试" >> "$B1/tk2/docs/agents/domain.md"
set_version "1.0.0"
"$B1/tk2/update.sh" --target "$PWD" >/dev/null 2>&1 || true
ok "未修改文件已同步" "$(grep -c 'vNEXT 演进测试' docs/agents/domain.md)" "1"
ok "冲突文件仍未覆盖" "$(grep -c '## 本地定制' docs/agents/triage-labels.md)" "1"

# ── 用例 6：--force 解决冲突 ─────────────────────────────────────────────────
echo ""
echo "[6] --force"
set_version "1.0.0"
"$B1/tk2/update.sh" --target "$PWD" --force >/dev/null 2>&1; ok "退出码" "$?" "0"
ok "已覆盖" "$(grep -c '## 本地定制' docs/agents/triage-labels.md)" "0"
ok "备份含本地内容" "$(grep -c '## 本地定制' docs/agents/triage-labels.md.bak)" "1"
set_version "1.0.0"
"$B1/tk2/update.sh" --target "$PWD" >/dev/null 2>&1; ok "冲突解决后归一" "$?" "0"
sanitize "$B1"

# ── 用例 7：--check / --dry-run 不落盘 ───────────────────────────────────────
echo ""
echo "[7] --check / --dry-run"
B2="$(mktemp -d)"; new_repo "$B2/repo" || exit 1
write_conf "1.0.0"; touch .change-workflow.manifest
out7="$("$CW_ROOT/update.sh" --target "$PWD" --check 2>&1 || true)"
case "$out7" in *"有新版本可用"*) r7=0 ;; *) r7=1 ;; esac
ok "--check 报告新版本" "$r7" "0"
ok "--check 未落盘" "$(grep -o '1\.0\.0' .change-workflow.conf | head -1)" "1.0.0"
"$CW_ROOT/update.sh" --target "$PWD" --dry-run >/dev/null 2>&1
ok "--dry-run 未落盘" "$(grep -o '1\.0\.0' .change-workflow.conf | head -1)" "1.0.0"
ok "--dry-run 未装文件" "$([[ -d docs/agents ]] && echo y || echo n)" "n"
sanitize "$B2"

# ── 用例 8：--adopt 接管（模拟 1.0.0 时代安装：无 manifest、无版本）──────────
echo ""
echo "[8] --adopt 接管模式"
B3="$(mktemp -d)"; new_repo "$B3/repo" || exit 1
mkdir -p .opencode/skills/change-workflow docs/agents
cp "$CW_ROOT/docs/agents/defect-workflow.md" docs/agents/
cp "$CW_ROOT/docs/agents/triage-labels.md" docs/agents/
cp "$CW_ROOT/skills/change-workflow/SKILL.md" .opencode/skills/change-workflow/
echo "## 本地定制" >> docs/agents/triage-labels.md
write_conf "1.0.0"
sed -i.cw 's|^TOOLKIT_VERSION=.*||' .change-workflow.conf && rm -f .change-workflow.conf.cw
rc8=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc8=$?
ok "退出码（有差异→1）" "$rc8" "1"
# 3 个文件与模板不同（未剥头的原始模板 ≠ 渲染结果）→ 不写基线 → manifest = 12 - 3 = 9
ok "manifest 条目数" "$(wc -l < .change-workflow.manifest | tr -d ' ')" "9"
ok "不同文件不写基线" "$(grep -c 'defect-workflow.md\|triage-labels.md\|change-workflow/SKILL.md' .change-workflow.manifest)" "0"
ok "版本已写入" "$(grep -c '^TOOLKIT_VERSION=' .change-workflow.conf)" "1"
ok "本地内容保留" "$(grep -c '## 本地定制' docs/agents/triage-labels.md)" "1"
ok "旁路文件为新版本" "$(grep -c '## 本地定制' docs/agents/triage-labels.md.new)" "0"
# 修复后的语义：未写基线的「不同」文件**持续被标记**，直到人工解决 —— 不会再被静默覆盖
set_version "0.9.0"
rc8b=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc8b=$?
ok "未解决前持续报冲突" "$rc8b" "1"
ok "定制仍未被覆盖" "$(grep -c '## 本地定制' docs/agents/triage-labels.md)" "1"
# 用户采纳后应能归一（须解决**全部** 3 个不同文件，只解一个仍会报冲突）
mv docs/agents/triage-labels.md.new docs/agents/triage-labels.md
mv docs/agents/defect-workflow.md.new docs/agents/defect-workflow.md
mv .opencode/skills/change-workflow/SKILL.md.new .opencode/skills/change-workflow/SKILL.md
set_version "0.9.0"
rc8c=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc8c=$?
ok "全部采纳后归一" "$rc8c" "0"
sanitize "$B3"

# ── 用例 9：一致性（模板头 / 仓库特有值残留 / 语法）──────────────────────────
echo ""
echo "[9] 一致性"
hdr=0
for f in "$CW_ROOT"/docs/agents/*.md "$CW_ROOT"/skills/change-workflow/SKILL.md; do
  if head -1 "$f" | grep -q "工具包模板"; then hdr=$((hdr + 1)); fi
done
ok "模板头覆盖" "$hdr" "10"
ok "仓库特有值残留" "$(grep -rl 'jianxi-dev\|/Users/mason\|PVT_kwDO\|PVTSSF_' \
  "$CW_ROOT/docs/agents" "$CW_ROOT/skills" "$CW_ROOT/scripts" "$CW_ROOT/workflows" 2>/dev/null | wc -l | tr -d ' ')" "0"
syntax_fail=0
for s in "$CW_ROOT"/setup.sh "$CW_ROOT"/update.sh "$CW_ROOT"/lib/render.sh "$CW_ROOT"/scripts/pr-automation.sh; do
  bash -n "$s" 2>/dev/null || syntax_fail=$((syntax_fail + 1))
done
ok "脚本语法错误数" "$syntax_fail" "0"
ok "裸 \$VAR 紧邻非 ASCII" "$(python3 - "$CW_ROOT" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]); n = 0
for f in ['update.sh','setup.sh','lib/render.sh','scripts/pr-automation.sh']:
    p = root / f
    if not p.is_file(): continue
    for i, line in enumerate(p.read_text(encoding='utf-8').splitlines(), 1):
        for m in re.finditer(r'(?<!\{)\$([A-Za-z_][A-Za-z0-9_]*)', line):
            nxt = line[m.end():m.end()+1]
            if nxt and ord(nxt) > 127 and nxt != '}': n += 1
print(n)
PY
)" "0"

# ── 用例 10：接管后再更新，本地定制不得被覆盖（回归：曾静默覆盖）─────────────
echo ""
echo "[10] 接管 → 再次更新，定制不得被覆盖"
B4="$(mktemp -d)"; new_repo "$B4/repo" || exit 1
mkdir -p docs/agents
cp "$CW_ROOT/docs/agents/domain.md" docs/agents/
echo "## 本仓库专属定制" >> docs/agents/domain.md
write_conf "1.0.0"
sed -i.cw 's|^TOOLKIT_VERSION=.*||' .change-workflow.conf && rm -f .change-workflow.conf.cw
rc10a=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc10a=$?
ok "接管退出码" "$rc10a" "1"
ok "定制保留" "$(grep -c '## 本仓库专属定制' docs/agents/domain.md)" "1"
ok "定制文件不写基线" "$(grep -c 'domain.md' .change-workflow.manifest)" "0"
# 原缺陷：接管把当前内容记为基线 → 下次更新判为「未修改」→ 静默覆盖
set_version "0.9.0"
rc10b=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc10b=$?
ok "再次更新仍报冲突" "$rc10b" "1"
ok "定制未被覆盖" "$(grep -c '## 本仓库专属定制' docs/agents/domain.md)" "1"
# 用户采纳新版后应能归一
mv docs/agents/domain.md.new docs/agents/domain.md
set_version "0.9.0"
rc10c=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc10c=$?
ok "采纳后归一" "$rc10c" "0"
ok "基线已记录" "$(grep -c 'domain.md' .change-workflow.manifest)" "1"
sanitize "$B4"

# ── 汇总 ─────────────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo " 通过 $PASS · 失败 $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  echo " 失败项:"
  printf '   - %s\n' "${FAILED_NAMES[@]}"
  echo "=============================================="
  exit 1
fi
echo " 全部通过 ✅"
echo "=============================================="
