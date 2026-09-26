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
OPT_BACKLOG="b1"
OPT_READY="r1"
OPT_IN_PROGRESS="p1"
OPT_DONE="d1"
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

# 读八进制权限位（python3 两平台皆有；A5 模式保持断言用）
fmode() { python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$1"; }

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
ok "docs/agents 文件数" "$(ls docs/agents/*.md 2>/dev/null | wc -l | tr -d ' ')" "12"
ok "SKILL 已安装" "$([[ -f .opencode/skills/change-workflow/SKILL.md ]] && echo y)" "y"
ok "pr-automation 可执行" "$([[ -x scripts/pr-automation.sh ]] && echo y)" "y"
ok "cw-update 可执行" "$([[ -x scripts/cw-update.sh ]] && echo y)" "y"
# 回归锁（1.3.0 驳回缺陷）：新增受管脚本漏加 chmod 名单 → 消费仓 Permission denied(126)。
# 断言直接查 x 位，而不是脚本内部变量，确保「清单派生」这个修复真的落地。
ok "cw-evidence 可执行" "$([[ -x scripts/cw-evidence.sh ]] && echo y)" "y"
ok "cw-greploop 可执行" "$([[ -x scripts/cw-greploop.sh ]] && echo y)" "y"
ok "cw-tickets-check 可执行" "$([[ -x scripts/cw-tickets-check.sh ]] && echo y)" "y"
# A5（R1）模式保持回归锁：mktemp 恒 0600 曾随 mv 带进受管文件（首装 docs=600、脚本=711）。
# 新建 → 0644；脚本 = 0644 + cw_chmod_scripts 的 +x → 755；manifest 新建 → 644。
ok "docs 模式 644" "$(fmode docs/agents/domain.md)" "644"
ok "脚本模式 755" "$(fmode scripts/cw-evidence.sh)" "755"
ok "manifest 模式 644" "$(fmode .change-workflow.manifest)" "644"
ok "manifest 行数" "$(wc -l < .change-workflow.manifest | tr -d ' ')" "19"
ok "conf 版本已更新" "$(grep -o "$(tr -d '[:space:]' < "$CW_ROOT/VERSION")" .change-workflow.conf | head -1)" "$(tr -d '[:space:]' < "$CW_ROOT/VERSION")"
ok "无残留占位符" "$(grep -rho '{{[A-Z_]*}}' docs/agents/ .opencode/skills/ 2>/dev/null | sort -u | wc -l | tr -d ' ')" "0"

# ── 用例 2：幂等 ─────────────────────────────────────────────────────────────
echo ""
echo "[2] 幂等（版本回退后重跑）"
set_version "1.0.0"
# 不可用 `cmd | grep -q`：grep -q 命中即关管道 → 上游收 SIGPIPE(141) → pipefail 判失败 → set -e 终止。
out2="$("$CW_ROOT/update.sh" --target "$PWD" 2>&1 || true)"
case "$out2" in *"已最新 19"*) r2=0 ;; *) r2=1 ;; esac
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
# A5（R1）覆盖更新保持目标模式（曾 644→600）
ok "覆盖后模式保持 644" "$(fmode docs/agents/domain.md)" "644"
# 1.4.1：安全覆盖（current == baseline）不留 .bak —— 收尾一律清理（与其它文件是否冲突无关）。
# 该 .bak 内容即基线，可由 git 追溯；留着只是消费仓每次升级累积的 untracked 噪音。
# 仅 --force 覆盖的本地定制需要备份（唯一副本），见用例 6（含其模式回归锁）。
ok "安全覆盖不留 .bak（已清理）" "$([[ ! -e docs/agents/domain.md.bak ]] && echo y)" "y"

# ── 用例 6：--force 解决冲突 ─────────────────────────────────────────────────
echo ""
echo "[6] --force"
set_version "1.0.0"
"$B1/tk2/update.sh" --target "$PWD" --force >/dev/null 2>&1; ok "退出码" "$?" "0"
ok "已覆盖" "$(grep -c '## 本地定制' docs/agents/triage-labels.md)" "0"
ok "备份含本地内容" "$(grep -c '## 本地定制' docs/agents/triage-labels.md.bak)" "1"
# 承接 A5（R1）模式锁：.bak 改由 --force 路径产生，模式要求不变（曾 600）
ok "force .bak 模式 644" "$(fmode docs/agents/triage-labels.md.bak)" "644"
ok "force 备份不被清理" "$([[ -e docs/agents/triage-labels.md.bak ]] && echo y)" "y"
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
# 受管脚本必须可执行（cw_chmod_scripts 从受管清单派生，1.2.0/1.3.0 两次同因缺陷）
ok "pr-automation 可执行" "$([[ -x scripts/pr-automation.sh ]] && echo y)" "y"
ok "cw-evidence 可执行" "$([[ -x scripts/cw-evidence.sh ]] && echo y)" "y"
ok "cw-greploop 可执行" "$([[ -x scripts/cw-greploop.sh ]] && echo y)" "y"
ok "cw-tickets-check 可执行" "$([[ -x scripts/cw-tickets-check.sh ]] && echo y)" "y"
# 3 个文件与模板不同（未剥头的原始模板 ≠ 渲染结果）→ 不写基线 → manifest = 19 - 3 = 16
ok "manifest 条目数" "$(wc -l < .change-workflow.manifest | tr -d ' ')" "16"
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
ok "模板头覆盖" "$hdr" "13"
# 排除 AGENTS.md：目录级知识库本就需要指名这些禁串（它是规则文本，不会被安装到消费仓）
ok "仓库特有值残留" "$(grep -rl 'jianxi-dev/md-bundle\|jianxi-dev/mdpkg\|jianxi-dev/clairis\|/Users/mason\|PVT_kwDO\|PVTSSF_\|apps/web\|packages/editor\|packages/renderer\|pnpm\|@md-bundle' \
  "$CW_ROOT/docs/agents" "$CW_ROOT/skills" "$CW_ROOT/scripts" "$CW_ROOT/workflows" "$CW_ROOT/setup.sh" "$CW_ROOT/config.example.conf" 2>/dev/null \
  | grep -v 'AGENTS\.md$' | wc -l | tr -d ' ')" "0"
syntax_fail=0
for s in "$CW_ROOT"/setup.sh "$CW_ROOT"/update.sh "$CW_ROOT"/lib/render.sh "$CW_ROOT"/scripts/*.sh "$CW_ROOT"/test/rollout-check.sh; do
  bash -n "$s" 2>/dev/null || syntax_fail=$((syntax_fail + 1))
done
ok "脚本语法错误数" "$syntax_fail" "0"
ok "裸 \$VAR 紧邻非 ASCII" "$(python3 - "$CW_ROOT" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]); n = 0
for f in ['update.sh','setup.sh','lib/render.sh','test/rollout-check.sh'] + [str(p.relative_to(root)) for p in sorted(root.glob('scripts/*.sh'))]:
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

# ── 用例 11：--accept-local 解决冲突（保留本地并停止报告）─────────────────────
echo ""
echo "[11] --accept-local 保留本地并停止报告"
B5="$(mktemp -d)"; new_repo "$B5/repo" || exit 1
mkdir -p docs/agents
cp "$CW_ROOT/docs/agents/domain.md" docs/agents/
echo "## 有意保留的本地文档" >> docs/agents/domain.md
write_conf "1.0.0"
sed -i.cw 's|^TOOLKIT_VERSION=.*||' .change-workflow.conf && rm -f .change-workflow.conf.cw
rc11a=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc11a=$?
ok "接管报冲突" "$rc11a" "1"
rc11b=0; "$CW_ROOT/update.sh" --target "$PWD" --accept-local docs/agents/domain.md >/dev/null 2>&1 || rc11b=$?
ok "accept-local 退出码" "$rc11b" "0"
ok "记为 LOCAL 哨兵" "$(awk '$2=="docs/agents/domain.md"{print $1}' .change-workflow.manifest)" "LOCAL"
ok "本地内容保留" "$(grep -c '## 有意保留的本地文档' docs/agents/domain.md)" "1"
# 此后应归一，且**再多次更新都不得覆盖它**（这是 --accept-local 的核心保证）
set_version "0.9.0"
rc11c=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc11c=$?
ok "此后归一（不再报冲突）" "$rc11c" "0"
ok "内容仍未被覆盖" "$(grep -c '## 有意保留的本地文档' docs/agents/domain.md)" "1"
ok "LOCAL 哨兵未被重写" "$(awk '$2=="docs/agents/domain.md"{print $1}' .change-workflow.manifest)" "LOCAL"
set_version "0.9.0"
"$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || true
ok "多次更新后仍保留" "$(grep -c '## 有意保留的本地文档' docs/agents/domain.md)" "1"
# 路径归一回归锁：`./` 前缀曾绕过旧行过滤 → 旧行 + `LOCAL  ./…` 并存（哨兵死行），
# 谎报成功后下次 update 仍 rc=1。现循环内剥「./」：manifest 恰好 1 行且归一。
echo "## 本地定制二" >> docs/agents/quality-gates.md
set_version "0.9.0"
"$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || true
rc11d=0; "$CW_ROOT/update.sh" --target "$PWD" --accept-local ./docs/agents/quality-gates.md >/dev/null 2>&1 || rc11d=$?
ok "./前缀 accept-local 退 0" "$rc11d" "0"
ok "./前缀归一后 manifest 恰 1 行" "$(awk '{ rest=$0; sub(/^[^[:space:]]+[[:space:]]+/, "", rest); if (rest=="docs/agents/quality-gates.md" || rest=="./docs/agents/quality-gates.md") c++ } END {print c+0}' .change-workflow.manifest)" "1"
set_version "0.8.0"
rc11e=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc11e=$?
ok "./前缀接受后 update 归一" "$rc11e" "0"
# --force 清 LOCAL 哨兵回归锁：force = 显式采用上游 → 基线必须归一（红证：force 后
# manifest 仍 LOCAL，模板演进被「本地保留」静默跳过，文件永远停在旧版）
"$CW_ROOT/update.sh" --target "$PWD" --force >/dev/null 2>&1 || true
ok "force 后 LOCAL 哨兵已清除" "$(awk '{ rest=$0; sub(/^[^[:space:]]+[[:space:]]+/, "", rest); if (rest=="docs/agents/domain.md" && $1=="LOCAL") c++ } END {print c+0}' .change-workflow.manifest)" "0"
cp -R "$CW_ROOT" "$B5/tk2"
echo "## v2 演进内容" >> "$B5/tk2/docs/agents/domain.md"
set_version "0.7.0"
rc11f=0; "$B5/tk2/update.sh" --target "$PWD" >/dev/null 2>&1 || rc11f=$?
ok "force 后演进归一退 0" "$rc11f" "0"
ok "演进内容已跟进" "$(grep -c 'v2 演进内容' docs/agents/domain.md)" "1"
# 对抗轮4 Gap A 回归锁：内容已等于上游、却带陈旧 LOCAL 哨兵的文件，--force 必须归一。
# 旧缺陷：current==new 的提前 continue 先于 --force 分支触发 → 该文件不记 FORCED_LIST →
# manifest 重写走 LOCAL 保留分支 → force 后仍 LOCAL，此后模板演进被「本地保留」永久
# 跳过（红证：accept-local → mv .new → --force 后哨兵仍在、演进不跟进）。
echo "## 定制三" >> docs/agents/evidence-capture.md
set_version "0.6.0"
"$B5/tk2/update.sh" --target "$PWD" >/dev/null 2>&1 || true
"$B5/tk2/update.sh" --target "$PWD" --accept-local docs/agents/evidence-capture.md >/dev/null 2>&1 || true
mv docs/agents/evidence-capture.md.new docs/agents/evidence-capture.md
"$B5/tk2/update.sh" --target "$PWD" --force >/dev/null 2>&1 || true
ok "force 归一等值文件的 LOCAL 哨兵" "$(awk '{ rest=$0; sub(/^[^[:space:]]+[[:space:]]+/, "", rest); if (rest=="docs/agents/evidence-capture.md" && $1=="LOCAL") c++ } END {print c+0}' .change-workflow.manifest)" "0"
echo "## v3 等值演进" >> "$B5/tk2/docs/agents/evidence-capture.md"
set_version "0.5.0"
rc11g=0; "$B5/tk2/update.sh" --target "$PWD" >/dev/null 2>&1 || rc11g=$?
ok "等值 force 后演进归一退 0" "$rc11g" "0"
ok "等值 force 后演进已跟进" "$(grep -c 'v3 等值演进' docs/agents/evidence-capture.md)" "1"
# 对抗轮5 MAJOR 回归锁：LOCAL 哨兵 + 内容已等值时，普通 update 必须计「本地保留」
# 而非「已最新」。旧缺陷：current==new 的提前 continue 先于 LOCAL 分支触发 → 一律计
# CURRENT，而 manifest 仍保留 LOCAL 行 → rollout-check 的 kept==grep -c '^LOCAL' 发布
# 契约（AGENTS.md「LOCAL 哨兵完整」）在该可达状态（accept-local → mv .new）下必然
# 误报「不可发布」。dry-run 计数必须与真实一致 —— rollout-check 跑的就是 --dry-run。
echo "## 定制四" >> docs/agents/pr-writing.md
set_version "0.4.0"
"$B5/tk2/update.sh" --target "$PWD" >/dev/null 2>&1 || true
"$B5/tk2/update.sh" --target "$PWD" --accept-local docs/agents/pr-writing.md >/dev/null 2>&1 || true
mv docs/agents/pr-writing.md.new docs/agents/pr-writing.md
rc11h=0; out11h="$("$B5/tk2/update.sh" --target "$PWD" 2>&1)" || rc11h=$?
ok "LOCAL+等值 普通更新退 0" "$rc11h" "0"
case "$out11h" in *"本地保留 1"*) r11h=0 ;; *) r11h=1 ;; esac
ok "LOCAL+等值 计为本地保留" "$r11h" "0"
ok "LOCAL+等值 哨兵仍保留" "$(awk '{ rest=$0; sub(/^[^[:space:]]+[[:space:]]+/, "", rest); if (rest=="docs/agents/pr-writing.md" && $1=="LOCAL") c++ } END {print c+0}' .change-workflow.manifest)" "1"
out11j="$("$B5/tk2/update.sh" --target "$PWD" --dry-run 2>&1 || true)"
case "$out11j" in *"本地保留 1"*) r11j=0 ;; *) r11j=1 ;; esac
ok "dry-run 本地保留计数一致" "$r11j" "0"
# 对抗轮6 回归锁（三桶唯一性）：accept-local 后**文件被删除** —— LOCAL 是用户显式保留
# 决定，缺失不撤销它；manifest 重写仍原样保留哨兵。旧缺陷把重装计为 ADDED → 汇总
# 「本地保留 0」而 ^LOCAL=1 → rollout-check 的 kept==grep -c '^LOCAL' 发布契约必然误报
# （红证：accept-local → rm → update：新增 1 · 本地保留 0，grep -c '^LOCAL' 为 1）。
rm docs/agents/pr-writing.md
out11k="$("$B5/tk2/update.sh" --target "$PWD" --dry-run 2>&1 || true)"
ok "缺失+LOCAL dry-run 计本地保留" "$(printf '%s' "$out11k" | sed -n 's/.*本地保留 \([0-9][0-9]*\).*/\1/p' | head -1)" "1"
rc11l=0; out11l="$("$B5/tk2/update.sh" --target "$PWD" 2>&1)" || rc11l=$?
ok "缺失+LOCAL 真实更新退 0" "$rc11l" "0"
ok "缺失+LOCAL 文件已重装" "$([[ -f docs/agents/pr-writing.md ]] && echo y)" "y"
ok "缺失+LOCAL 真实更新计本地保留" "$(printf '%s' "$out11l" | sed -n 's/.*本地保留 \([0-9][0-9]*\).*/\1/p' | head -1)" "1"
ok "缺失+LOCAL kept==^LOCAL" "$(printf '%s' "$out11l" | sed -n 's/.*本地保留 \([0-9][0-9]*\).*/\1/p' | head -1)" "$(grep -c '^LOCAL' .change-workflow.manifest)"
m11l="$(printf '%s' "$out11l" | sed -n 's/.*更新 \([0-9][0-9]*\) · 新增 \([0-9][0-9]*\) · 已最新 \([0-9][0-9]*\) · 冲突 \([0-9][0-9]*\) · 本地保留 \([0-9][0-9]*\).*/\1+\2+\3+\4+\5/p' | head -1)"
ok "缺失+LOCAL 五桶和==19" "$(( ${m11l:-0} ))" "19"
# 对抗轮7 回归锁：缺失 + LOCAL 哨兵 + --force —— force 优先于 LOCAL 哨兵（与等值/差异路径
# 同原则），缺失分支必须归一：计 ADDED + 记 FORCED_LIST → manifest 重写走哈希归一分支。
# 旧缺陷：缺失分支无 force 分流 → --force 仍走 LOCAL 保留分支 → 文件被「本地保留」永久
# 冻结，模板演进永不跟进（红证：accept-local → rm → --force：本地保留 1 · 哨兵仍在）。
rm docs/agents/pr-writing.md
out11m="$("$B5/tk2/update.sh" --target "$PWD" --dry-run --force 2>&1 || true)"
ok "缺失+LOCAL force dry-run 计新增非保留" "$(printf '%s' "$out11m" | sed -n 's/.*本地保留 \([0-9][0-9]*\).*/\1/p' | head -1)" "0"
rc11n=0; out11n="$("$B5/tk2/update.sh" --target "$PWD" --force 2>&1)" || rc11n=$?
ok "缺失+LOCAL force 真实更新退 0" "$rc11n" "0"
ok "缺失+LOCAL force 文件已重装" "$([[ -f docs/agents/pr-writing.md ]] && echo y)" "y"
ok "缺失+LOCAL force 哨兵归一" "$(awk '{ rest=$0; sub(/^[^[:space:]]+[[:space:]]+/, "", rest); if (rest=="docs/agents/pr-writing.md" && $1=="LOCAL") c++ } END {print c+0}' .change-workflow.manifest)" "0"
ok "缺失+LOCAL force kept==^LOCAL" "$(printf '%s' "$out11n" | sed -n 's/.*本地保留 \([0-9][0-9]*\).*/\1/p' | head -1)" "$(grep -c '^LOCAL' .change-workflow.manifest)"
m11n="$(printf '%s' "$out11n" | sed -n 's/.*更新 \([0-9][0-9]*\) · 新增 \([0-9][0-9]*\) · 已最新 \([0-9][0-9]*\) · 冲突 \([0-9][0-9]*\) · 本地保留 \([0-9][0-9]*\).*/\1+\2+\3+\4+\5/p' | head -1)"
ok "缺失+LOCAL force 五桶和==19" "$(( ${m11n:-0} ))" "19"
sanitize "$B5"

# ── 用例 12：项目自升级 cw-update.sh ─────────────────────────────────────────
echo ""
echo "[12] 项目自升级（cw-update.sh）"
B6="$(mktemp -d)"
# 源仓库：一份工具包副本（本地 git repo），模拟 TOOLKIT_SOURCE
SRC="$B6/source"; mkdir -p "$SRC"
cp -R "$CW_ROOT/." "$SRC/"
rm -rf "$SRC/.git"
cd "$SRC" || exit 1
git init -q
git -c user.name=t -c user.email=t@t.invalid add -A
git -c user.name=t -c user.email=t@t.invalid commit -q -m "toolkit"
# 项目：conf 指向本地源；一份文档带本地定制
P="$B6/proj"; mkdir -p "$P/docs/agents" "$P/scripts"; cd "$P" || exit 1
git init -q && git -c user.name=t -c user.email=t@t.invalid commit -q --allow-empty -m init
cp "$CW_ROOT/docs/agents/domain.md" docs/agents/
echo "## 本地定制" >> docs/agents/domain.md
cat > .change-workflow.conf <<EOF
TOOLKIT_VERSION="1.1.6"
TOOLKIT_SOURCE="$SRC"
REPO="a/b"
OWNER="a"
DEFAULT_BRANCH="main"
SKILLS_DIR=".opencode/skills"
DOCS_DIR="docs/agents"
EOF
touch .change-workflow.manifest
cp "$CW_ROOT/scripts/cw-update.sh" scripts/cw-update.sh && chmod +x scripts/cw-update.sh
# 自升级（缓存重定向到临时目录，避免污染真实 ~/.change-workflow）
# 首次克隆：TOOLKIT_SOURCE 非默认源，须显式授权（C1 信任门）
rc12a=0; CHANGE_WORKFLOW_HOME="$B6/cache" CW_UPDATE_ALLOW_SOURCE=1 ./scripts/cw-update.sh --target "$PWD" >/dev/null 2>&1 || rc12a=$?
ok "自升级触发接管" "$rc12a" "1"
ok "版本已升级" "$(grep -o 'TOOLKIT_VERSION="[^"]*"' .change-workflow.conf | head -1)" "TOOLKIT_VERSION=\"$(tr -d '[:space:]' < "$CW_ROOT/VERSION")\""
ok "定制保留" "$(grep -c '## 本地定制' docs/agents/domain.md)" "1"
ok "缓存已建立" "$([[ -d "$B6/cache/.git" ]] && echo y)" "y"
ok "受管文件已安装" "$([[ -f .opencode/skills/change-workflow/SKILL.md ]] && echo y)" "y"
# 接受定制后应归一
CHANGE_WORKFLOW_HOME="$B6/cache" ./scripts/cw-update.sh --target "$PWD" --accept-local docs/agents/domain.md >/dev/null 2>&1 || true
rc12b=0; CHANGE_WORKFLOW_HOME="$B6/cache" ./scripts/cw-update.sh --target "$PWD" >/dev/null 2>&1 || rc12b=$?
ok "解决后归一" "$rc12b" "0"
ok "定制仍保留" "$(grep -c '## 本地定制' docs/agents/domain.md)" "1"
# C1 信任门：conf 指向攻击者源 + 无 CW_UPDATE_ALLOW_SOURCE + 无缓存 → fail-closed（RCE 红证）
ATT="$B6/attacker"; mkdir -p "$ATT"
cat > "$ATT/update.sh" <<'EOF'
#!/usr/bin/env bash
echo "ATTACKER-CODE-EXECUTED" > "$(pwd)/PWNED-MARKER"
exit 0
EOF
chmod +x "$ATT/update.sh"
git -C "$ATT" init -q
git -C "$ATT" -c user.name=t -c user.email=t@t.invalid add -A
git -C "$ATT" -c user.name=t -c user.email=t@t.invalid commit -q -m "attacker"
M="$B6/mal"; mkdir -p "$M/scripts"
git -C "$M" init -q && git -C "$M" -c user.name=t -c user.email=t@t.invalid commit -q --allow-empty -m init
cat > "$M/.change-workflow.conf" <<EOF
TOOLKIT_VERSION="1.1.6"
TOOLKIT_SOURCE="$ATT"
REPO="a/b"
OWNER="a"
DEFAULT_BRANCH="main"
SKILLS_DIR=".opencode/skills"
DOCS_DIR="docs/agents"
EOF
touch "$M/.change-workflow.manifest"
cp "$CW_ROOT/scripts/cw-update.sh" "$M/scripts/cw-update.sh" && chmod +x "$M/scripts/cw-update.sh"
cd "$M"
rc12m=0; CHANGE_WORKFLOW_HOME="$B6/mal-cache" ./scripts/cw-update.sh --target "$PWD" >/dev/null 2>&1 || rc12m=$?
ok "恶意源无授权拒绝" "$rc12m" "1"
ok "恶意源未执行" "$([[ -e "$M/PWNED-MARKER" ]] && echo y || echo n)" "n"
sanitize "$B6"

# ── 用例 13：自撞护栏（工具包自身不得作为目标）────────────────────────────────
# 破坏性路径一律在**副本**上演练：若护栏失效，被清空的是副本而不是本仓。
echo ""
echo "[13] 自撞护栏"
B7="$(mktemp -d)"
TK="$B7/tk"; mkdir -p "$TK"
cp -R "$CW_ROOT/." "$TK/"
rm -rf "$TK/.git"
cd "$TK" || exit 1
git init -q && git -c user.name=t -c user.email=t@t.invalid commit -q --allow-empty -m init

ok "识别工具包自身" "$(bash -c "source '$TK/lib/render.sh'; cw_is_self_target '$TK' && echo yes || echo no")" "yes"
ok "不误判普通目录" "$(bash -c "source '$TK/lib/render.sh'; cw_is_self_target '$B7' && echo yes || echo no")" "no"

# cw_render 同文件渲染 = 清空的根源（`> "$dst"` 先截断再读）
cp "$TK/docs/agents/domain.md" "$B7/probe.md"
size_before="$(wc -c < "$B7/probe.md" | tr -d ' ')"
rc13a=0; bash -c "source '$TK/lib/render.sh'; cw_render '$B7/probe.md' '$B7/probe.md'" >/dev/null 2>&1 || rc13a=$?
ok "cw_render 拒绝渲染到自身" "$rc13a" "1"
ok "探测文件未被清空" "$(wc -c < "$B7/probe.md" | tr -d ' ')" "$size_before"

rc13b=0; "$TK/setup.sh" --target "$TK" --yes >/dev/null 2>&1 || rc13b=$?
ok "setup.sh 拒绝自我安装" "$rc13b" "1"
rc13c=0; "$TK/update.sh" --target "$TK" >/dev/null 2>&1 || rc13c=$?
ok "update.sh 拒绝自我升级" "$rc13c" "1"
hdr13=0
for f in "$TK"/docs/agents/*.md "$TK"/skills/change-workflow/SKILL.md; do
  head -1 "$f" | grep -q "工具包模板" && hdr13=$((hdr13 + 1))
done
ok "副本模板头未被清掉" "$hdr13" "13"
ok "副本脚本非空" "$([[ -s "$TK/scripts/pr-automation.sh" ]] && echo y)" "y"
sanitize "$B7"

# ── 用例 14：滚动验证脚本（消费仓发布前门禁）──────────────────────────────────
echo ""
echo "[14] rollout-check：干净仓放行 / 有冲突仓拦截"
B8="$(mktemp -d)"
CLEAN="$B8/clean"; new_repo "$CLEAN" || exit 1
write_conf "1.0.0"
"$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || true
ok "干净仓受管文件数" "$(wc -l < .change-workflow.manifest | tr -d ' ')" "19"

rc14a=0; out14a="$("$CW_ROOT/test/rollout-check.sh" "$CLEAN" 2>&1)" || rc14a=$?
ok "干净仓退出码" "$rc14a" "0"
case "$out14a" in *"全部消费仓升级无冲突"*) r14=0 ;; *) r14=1 ;; esac
ok "干净仓报告通过" "$r14" "0"

# 有冲突仓：本地改一个受管文件（非 LOCAL）→ 必须被拦下
DIRTY="$B8/dirty"
cp -R "$CLEAN" "$DIRTY"
echo "## 本地定制" >> "$DIRTY/docs/agents/domain.md"
rc14b=0; out14b="$("$CW_ROOT/test/rollout-check.sh" "$DIRTY" 2>&1)" || rc14b=$?
ok "有冲突仓退出码" "$rc14b" "1"
case "$out14b" in *"不可发布"*) r14b=0 ;; *) r14b=1 ;; esac
ok "有冲突仓报告拦截" "$r14b" "0"
ok "只读：未留 .new" "$([[ -f "$DIRTY/docs/agents/domain.md.new" ]] && echo y || echo n)" "n"
ok "只读：干净仓未留 .new" "$(find "$CLEAN" -name '*.new' | wc -l | tr -d ' ')" "0"
sanitize "$B8"

# ── 用例 15：cw-evidence / cw-greploop 退出码契约（回归锁）────────────────────
# 契约（scripts/cw-evidence.sh、scripts/cw-greploop.sh 头部注释）：
#   0 = 成功（含 --help）；1 = 参数/子命令错误；3 = 降级（依赖缺失，须与成功可区分）
# 确定性：空 HOME + 无 GITHUB_TOKEN/GH_TOKEN + 无 CW_EVIDENCE_ALLOW_REPO
#         ⇒ 探测不到任何 skill / gh 未认证 ⇒ 降级路径必然命中；
#         参数校验先于能力探测 ⇒ 1 类退出码与探测结果无关。
echo ""
echo "[15] cw-evidence / cw-greploop 退出码契约"
B9="$(mktemp -d)"
new_repo "$B9/repo" || exit 1
mkdir -p "$B9/home"
cd "$B9/repo"

# cw-evidence.sh：8 条
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN -u CW_EVIDENCE_ALLOW_REPO "$CW_ROOT/scripts/cw-evidence.sh" doctor >/dev/null 2>&1 || rc=$?
ok "evidence doctor 退 0" "$rc" "0"
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN -u CW_EVIDENCE_ALLOW_REPO "$CW_ROOT/scripts/cw-evidence.sh" headless >/dev/null 2>&1 || rc=$?
ok "evidence headless 退 0" "$rc" "0"
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN -u CW_EVIDENCE_ALLOW_REPO "$CW_ROOT/scripts/cw-evidence.sh" --help >/dev/null 2>&1 || rc=$?
ok "evidence --help 退 0" "$rc" "0"
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN -u CW_EVIDENCE_ALLOW_REPO "$CW_ROOT/scripts/cw-evidence.sh" >/dev/null 2>&1 || rc=$?
ok "evidence 无子命令退 1" "$rc" "1"
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN -u CW_EVIDENCE_ALLOW_REPO "$CW_ROOT/scripts/cw-evidence.sh" bogus >/dev/null 2>&1 || rc=$?
ok "evidence 未知子命令退 1" "$rc" "1"
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN -u CW_EVIDENCE_ALLOW_REPO "$CW_ROOT/scripts/cw-evidence.sh" --skill-path "" doctor >/dev/null 2>&1 || rc=$?
ok "evidence --skill-path 空退 1" "$rc" "1"
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN -u CW_EVIDENCE_ALLOW_REPO "$CW_ROOT/scripts/cw-evidence.sh" start "$B9/repo" >/dev/null 2>&1 || rc=$?
ok "evidence start 降级退 3" "$rc" "3"
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN -u CW_EVIDENCE_ALLOW_REPO "$CW_ROOT/scripts/cw-evidence.sh" stop >/dev/null 2>&1 || rc=$?
ok "evidence stop 降级退 3" "$rc" "3"

# cw-greploop.sh：6 条
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN "$CW_ROOT/scripts/cw-greploop.sh" --help >/dev/null 2>&1 || rc=$?
ok "greploop --help 退 0" "$rc" "0"
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN "$CW_ROOT/scripts/cw-greploop.sh" --pr abc >/dev/null 2>&1 || rc=$?
ok "greploop --pr 非数字退 1" "$rc" "1"
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN "$CW_ROOT/scripts/cw-greploop.sh" --max-iterations 0 >/dev/null 2>&1 || rc=$?
ok "greploop --max-iterations 0 退 1" "$rc" "1"
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN "$CW_ROOT/scripts/cw-greploop.sh" --vcs svn >/dev/null 2>&1 || rc=$?
ok "greploop --vcs svn 退 1" "$rc" "1"
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN "$CW_ROOT/scripts/cw-greploop.sh" --bogus >/dev/null 2>&1 || rc=$?
ok "greploop 未知参数退 1" "$rc" "1"
rc=0; HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN "$CW_ROOT/scripts/cw-greploop.sh" >/dev/null 2>&1 || rc=$?
ok "greploop 无 --pr 降级退 3" "$rc" "3"

# A6（R2）：CW_EVIDENCE_ALLOW_REPO 必须精确 =1 才开启仓库级候选根。
# 旧「非空即开」使 =0 反而启用（红证：仓内植入 evidence.py 被 exec 落 marker）。
# 无害 marker：doctor 命中 skill 时会 `python3 evidence.py doctor`，脚本只落一个文件。
mkdir -p "$B9/repo/.opencode/skills/evidence-driven-testing/scripts"
cat > "$B9/repo/.opencode/skills/evidence-driven-testing/scripts/evidence.py" <<'PYEOF'
import pathlib
pathlib.Path("EVIDENCE-RAN-MARKER").write_text("ran")
PYEOF
out15a6="$(HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN CW_EVIDENCE_ALLOW_REPO=0 "$CW_ROOT/scripts/cw-evidence.sh" doctor 2>&1 || true)"
ok "evidence =0 不执行仓内 skill" "$([[ -e "$B9/repo/EVIDENCE-RAN-MARKER" ]] && echo y || echo n)" "n"
case "$out15a6" in *"仓库级候选根已跳过"*) r15a6=0 ;; *) r15a6=1 ;; esac
ok "evidence =0 打印跳过提示" "$r15a6" "0"
HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN CW_EVIDENCE_ALLOW_REPO=1 "$CW_ROOT/scripts/cw-evidence.sh" doctor >/dev/null 2>&1 || true
ok "evidence =1 执行仓内 skill" "$([[ -e "$B9/repo/EVIDENCE-RAN-MARKER" ]] && echo y || echo n)" "y"
rm -f "$B9/repo/EVIDENCE-RAN-MARKER"

# A8（R4）：conf SKILLS_DIR="./.." 曾绕过穿越校验（旧模式只拦 ../ 前缀与中段 ..），
# 仓外植入的 greploop/SKILL.md 被报「找到（./../greploop）」。现按「补斜杠查 /../ 段」拦截。
mkdir -p "$B9/greploop" "$B9/repo/scripts"
printf '# decoy\n' > "$B9/greploop/SKILL.md"
cp "$CW_ROOT/scripts/cw-greploop.sh" "$B9/repo/scripts/cw-greploop.sh" && chmod +x "$B9/repo/scripts/cw-greploop.sh"
printf 'SKILLS_DIR="./.."\n' > "$B9/repo/.change-workflow.conf"
out15a8="$(HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN "$B9/repo/scripts/cw-greploop.sh" 2>&1 || true)"
case "$out15a8" in *"回退 .opencode/skills"*) r15a8=0 ;; *) r15a8=1 ;; esac
ok "greploop ./.. 回退警告" "$r15a8" "0"
case "$out15a8" in *"找到（./../greploop）"*) r15a8b=1 ;; *) r15a8b=0 ;; esac
ok "greploop ./.. 不报告仓外找到" "$r15a8b" "0"
# 良性空格目录仍放行（补斜杠检查不误伤）
printf 'SKILLS_DIR="My Skills"\n' > "$B9/repo/.change-workflow.conf"
mkdir -p "$B9/repo/My Skills/greploop"
printf '# ok\n' > "$B9/repo/My Skills/greploop/SKILL.md"
out15a8c="$(HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN "$B9/repo/scripts/cw-greploop.sh" 2>&1 || true)"
case "$out15a8c" in *"找到（My Skills/greploop）"*) r15a8c=0 ;; *) r15a8c=1 ;; esac
ok "greploop 空格目录放行" "$r15a8c" "0"
# R5：符号链接根围栏。红证：`.opencode/skills -> 仓外目录`（内含攻击者 greploop/SKILL.md）
# 被报「✅ 找到」—— -f 跟随链接取真文件，探测面把仓外内容伪装成仓内能力。
# 现候选根为链接 → 跳过；随后验证直接目录（无链接）仍能找到（能力保持）。
mkdir -p "$B9/outside/greploop"
printf '# attacker\n' > "$B9/outside/greploop/SKILL.md"
rm -rf "$B9/repo/.opencode/skills"
ln -s "$B9/outside" "$B9/repo/.opencode/skills"
printf 'SKILLS_DIR=".opencode/skills"\n' > "$B9/repo/.change-workflow.conf"
out15r5="$(HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN "$B9/repo/scripts/cw-greploop.sh" 2>&1 || true)"
case "$out15r5" in *"找到（.opencode/skills/greploop）"*) r15r5=1 ;; *) r15r5=0 ;; esac
ok "greploop 符号链接根不报告找到" "$r15r5" "0"
rm "$B9/repo/.opencode/skills"
mkdir -p "$B9/repo/.opencode/skills/greploop"
printf '# real\n' > "$B9/repo/.opencode/skills/greploop/SKILL.md"
out15r5b="$(HOME="$B9/home" env -u GITHUB_TOKEN -u GH_TOKEN "$B9/repo/scripts/cw-greploop.sh" 2>&1 || true)"
case "$out15r5b" in *"找到（.opencode/skills/greploop）"*) r15r5b=0 ;; *) r15r5b=1 ;; esac
ok "greploop 直接目录仍能找到" "$r15r5b" "0"
sanitize "$B9"

# ── 用例 16：符号链接拒绝（C2 边界）──────────────────────────────────────────
# 受管文件被换成符号链接时，重定向/覆盖会写穿到链接指向处 —— cw_refuse_symlink
# 必须在任何写入前退 1（lib/render.sh:62-68；update.sh:132/194/258-259/458-459）。
echo ""
echo "[16] 符号链接拒绝"
B10="$(mktemp -d)"
new_repo "$B10/repo" || exit 1
write_conf "1.0.0"
"$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || true
set_version "0.9.0"
cp .change-workflow.conf "$B10/outside.conf"
rm -f .change-workflow.conf
ln -s "$B10/outside.conf" .change-workflow.conf
cp "$B10/outside.conf" "$B10/outside.before"
rc16=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc16=$?
ok "符号链接拒绝退出码 1" "$rc16" "1"
ok "符号链接未被替换" "$([[ -L .change-workflow.conf ]] && echo y)" "y"
ok "链接目标未被写穿" "$(cmp -s "$B10/outside.conf" "$B10/outside.before" && echo y || echo n)" "y"
sanitize "$B10"

# ── 用例 17：受管脚本符号链接拒绝（C2 边界）──────────────────────────────────
# 用例 16 只覆盖 conf；受管脚本被换成符号链接时同样会写穿——文件循环因内容与基线
# 一致判 CURRENT 跳过，真正的写穿点在收尾的 cw_chmod_scripts：chmod +x 会穿透
# 链接改到目标权限位（lib/render.sh:206）。把已安装的 cw-evidence.sh 换成指向
# 仓外文件的链接，update 必须在 chmod 前退 1，且链接目标权限位不得被改动。
echo ""
echo "[17] 受管脚本符号链接拒绝"
B11="$(mktemp -d)"
new_repo "$B11/repo" || exit 1
write_conf "1.0.0"
"$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || true
set_version "0.9.0"
cp scripts/cw-evidence.sh "$B11/outside-target"
chmod 644 "$B11/outside-target"
cp "$B11/outside-target" "$B11/outside.before"
rm -f scripts/cw-evidence.sh
ln -s "$B11/outside-target" scripts/cw-evidence.sh
rc17=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc17=$?
ok "受管脚本符号链接拒绝退出码 1" "$rc17" "1"
ok "受管脚本符号链接未被替换" "$([[ -L scripts/cw-evidence.sh ]] && echo y)" "y"
ok "受管脚本链接目标未被写穿" "$(cmp -s "$B11/outside-target" "$B11/outside.before" && echo y || echo n)" "y"
ok "受管脚本链接目标未被补执行位" "$([[ -x "$B11/outside-target" ]] && echo y || echo n)" "n"
ok "受管脚本未产生 .new/.bak" "$([[ ! -e scripts/cw-evidence.sh.new && ! -e scripts/cw-evidence.sh.bak ]] && echo y)" "y"
sanitize "$B11"

# ── 用例 18：父目录符号链接拒绝（C2 补强）────────────────────────────────────
# 用例 16/17 只查 leaf；父目录（scripts/）被换成符号链接时，mkdir -p 与重定向会
# 穿透链接写穿到链接指向处（红证：仓外落地 4 个脚本）。cw_refuse_symlink 现对
# 相对路径逐级检查组件（lib/render.sh:62-68），绝对路径只查 leaf（防系统链接误伤）。
echo ""
echo "[18] 父目录符号链接拒绝"
B12="$(mktemp -d)"
new_repo "$B12/repo" || exit 1
write_conf "1.0.0"
"$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || true
set_version "0.9.0"
OUTSIDE="$B12/outside"; mkdir -p "$OUTSIDE"
rm -rf scripts
ln -s "$OUTSIDE" scripts
rc18=0; "$CW_ROOT/update.sh" --target "$PWD" --force >/dev/null 2>&1 || rc18=$?
ok "父目录符号链接拒绝退出码 1" "$rc18" "1"
ok "仓外目录零写入" "$(ls -A "$OUTSIDE" | wc -l | tr -d ' ')" "0"
ok "父目录链接未被替换" "$([[ -L scripts ]] && echo y)" "y"
sanitize "$B12"

# ── 用例 19：空格目录 manifest 解析（R3）──────────────────────────────────────
# manifest 行「<sha>  <path>」的 path 可含空格；旧读取端用 awk $2 比较 → 空格路径
# 永远「无基线记录」→ .new + rc=1，且重写丢行、--accept-local 永不粘住（每次复发）。
echo ""
echo "[19] 空格目录 manifest 解析"
B13="$(mktemp -d)"; new_repo "$B13/repo" || exit 1
cat > .change-workflow.conf <<EOF
TOOLKIT_VERSION="1.0.0"
EFFECTIVE_DATE="2026-01-01"
REPO="acme/demo"
OWNER="acme"
DEFAULT_BRANCH="main"
PROJECT_ID="PVT_demo"
STATUS_FIELD_ID="PVTSSF_demo"
OPT_BACKLOG="b1"
OPT_READY="r1"
OPT_IN_PROGRESS="p1"
OPT_DONE="d1"
SKILLS_DIR="My Skills"
DOCS_DIR="My Docs"
EOF
touch .change-workflow.manifest
"$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || true
ok "空格目录已安装" "$([[ -f 'My Docs/domain.md' && -f 'My Skills/change-workflow/SKILL.md' ]] && echo y)" "y"
cp -R "$CW_ROOT" "$B13/tk2"
echo "## vNEXT 空格演进测试" >> "$B13/tk2/docs/agents/domain.md"
set_version "1.0.0"
rc19=0; out19="$("$B13/tk2/update.sh" --target "$PWD" 2>&1)" || rc19=$?
ok "空格路径更新退 0" "$rc19" "0"
ok "空格路径已同步" "$(grep -c 'vNEXT 空格演进测试' 'My Docs/domain.md')" "1"
case "$out19" in *"无基线记录"*) r19=1 ;; *) r19=0 ;; esac
ok "无「无基线记录」误报" "$r19" "0"
set_version "1.0.0"
out19b="$("$B13/tk2/update.sh" --target "$PWD" 2>&1 || true)"
case "$out19b" in *"已最新 19"*) r19b=0 ;; *) r19b=1 ;; esac
ok "二次运行已最新" "$r19b" "0"
# --accept-local 对空格路径生效：本地修改 → 冲突 → 接受 → 归一且哨兵粘住
echo "## 本地定制" >> "My Docs/triage-labels.md"
set_version "1.0.0"
rc19c=0; "$B13/tk2/update.sh" --target "$PWD" >/dev/null 2>&1 || rc19c=$?
ok "空格路径本地修改报冲突" "$rc19c" "1"
"$B13/tk2/update.sh" --target "$PWD" --accept-local "My Docs/triage-labels.md" >/dev/null 2>&1 || true
ok "accept-local 记 LOCAL 哨兵" "$(awk '{ rest=$0; sub(/^[^[:space:]]+[[:space:]]+/, "", rest); if (rest=="My Docs/triage-labels.md") print $1 }' .change-workflow.manifest)" "LOCAL"
set_version "0.9.0"
rc19d=0; "$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || rc19d=$?
ok "accept-local 后再更新归一" "$rc19d" "0"
ok "空格路径本地内容保留" "$(grep -c '## 本地定制' 'My Docs/triage-labels.md')" "1"
# 对抗轮4 Gap B 回归锁：manifest 读取端必须容忍 CRLF。旧缺陷：四处解析点比较裸 rest ——
# CRLF 清单每行 rest 带 \r → 全部基线失配（误报「无基线记录」+ rc=1），且重写时 LOCAL
# 哨兵匹配不上被静默丢弃（本地保留的保护无声解除）。
python3 -c "p='.change-workflow.manifest'; d=open(p,'rb').read().replace(b'\r\n',b'\n').replace(b'\n',b'\r\n'); open(p,'wb').write(d)"
set_version "0.9.0"
rc19e=0; out19e="$("$CW_ROOT/update.sh" --target "$PWD" 2>&1)" || rc19e=$?
ok "CRLF manifest 更新退 0" "$rc19e" "0"
case "$out19e" in *"无基线记录"*) r19e=1 ;; *) r19e=0 ;; esac
ok "CRLF manifest 无「无基线记录」误报" "$r19e" "0"
ok "CRLF manifest 保留 LOCAL 哨兵" "$(awk '{ rest=$0; sub(/\r$/, "", rest); sub(/^[^[:space:]]+[[:space:]]+/, "", rest); if (rest=="My Docs/triage-labels.md" && $1=="LOCAL") c++ } END {print c+0}' .change-workflow.manifest)" "1"
ok "CRLF manifest 后本地内容仍保留" "$(grep -c '## 本地定制' 'My Docs/triage-labels.md')" "1"
sanitize "$B13"

# ── 用例 20：cw_conf_get 末行无换行守卫（S1）──────────────────────────────────
# conf 以无结尾换行的行收尾时，裸 read 对末行返回非 0 → 旧循环丢弃该行（红证：rc=1/空），
# 而孪生副本（cw-greploop.sh / cw-update.sh 的 conf_get）能取到 —— 三处语义必须一致。
echo ""
echo "[20] cw_conf_get 末行无换行守卫"
B14="$(mktemp -d)"
printf 'REPO="a/b"\nDOCS_DIR="My Docs"' > "$B14/conf-nonl"   # 末行故意无 \n
ok "末行无换行仍可取值" "$(bash -c "source '$CW_ROOT/lib/render.sh'; cw_conf_get '$B14/conf-nonl' DOCS_DIR")" "My Docs"
sanitize "$B14"

# ── 用例 21：--accept-local 的 manifest 符号链接闸（S2）───────────────────────
# 接管/正常路径的 manifest 写前都有 cw_refuse_symlink，唯独 accept-local 块曾漏闸
# （红证：manifest 为链接时 rc=0 放行，链接被 mv 替换）。
echo ""
echo "[21] accept-local manifest 符号链接闸"
B15="$(mktemp -d)"; new_repo "$B15/repo" || exit 1
write_conf "1.0.0"
"$CW_ROOT/update.sh" --target "$PWD" >/dev/null 2>&1 || true
cp .change-workflow.manifest "$B15/outside.manifest"
cp "$B15/outside.manifest" "$B15/outside.before"
rm -f .change-workflow.manifest
ln -s "$B15/outside.manifest" .change-workflow.manifest
rc21=0; "$CW_ROOT/update.sh" --target "$PWD" --accept-local docs/agents/domain.md >/dev/null 2>&1 || rc21=$?
ok "accept-local 符号链接拒绝退 1" "$rc21" "1"
ok "manifest 链接未被替换" "$([[ -L .change-workflow.manifest ]] && echo y)" "y"
ok "链接目标未被写穿" "$(cmp -s "$B15/outside.manifest" "$B15/outside.before" && echo y || echo n)" "y"
# R1 收尾缺口回归锁：accept-local 路径的 tmp_manifest 曾漏 cw_tmp_mode_for
# （红证：manifest 644 → accept-local → 600，rc=0 静默）。恢复普通文件后再接受一次，断言模式保持。
rm -f .change-workflow.manifest
cp "$B15/outside.manifest" .change-workflow.manifest && chmod 644 .change-workflow.manifest
"$CW_ROOT/update.sh" --target "$PWD" --accept-local docs/agents/domain.md >/dev/null 2>&1 || true
ok "accept-local 后 manifest 模式 644" "$(fmode .change-workflow.manifest)" "644"
sanitize "$B15"

# ── 用例 22：conf 解析器语义对齐（F6+F8）──────────────────────────────────────
# 四份实现（lib/render.sh cw_conf_get + 三份消费侧副本 conf_get）必须逐字同语义。
# 红证（漂移）：副本先剥 # 后剥引号 → "…/r#frag" 返回悬空引号；lib 不剥行内注释 →
# `SKILLS_DIR=.opencode/skills # 注释` 会把文件装进垃圾目录；lib 不剥 \r → CRLF 值带回车。
# 红证（组合回归，1.3.1 统一后新发现）：`K="val" # c` 闭引号后跟行尾注释 →
# 「首尾同引号」判定失败 → 落入无引号分支 → 引号存活返回 `"val"`（旧实现返回 val）。
echo ""
echo "[22] conf 解析器语义对齐（引号优先/空白#注释/CR/引号+注释组合）"
B16="$(mktemp -d)"
# 先 cd 进本用例临时目录：上一用例的 sanitize 已删掉 shell 当时的 cwd，
# 裸 bash 启动会报 "shell-init: error retrieving current directory"（getcwd 噪声）。
cd "$B16"
{
  printf 'K_QH="a#b"\n'
  printf "K_SQ='a b'\n"
  printf 'K_HC=x # c\n'
  printf 'K_CR=unquoted\r\n'
  printf 'K_PL=normal\n'
  printf '# K_CM=ghost\n'
  printf 'K_QC="val" # c\n'
  printf 'K_QCS="a#b" # c\n'
  printf "K_QS='x # y'\n"
  printf 'K_QT="v"   \n'
} > "$B16/fixture.conf"
lib_get() { bash -c "source '$CW_ROOT/lib/render.sh'; cw_conf_get '$B16/fixture.conf' '$1'"; }
# 副本函数体抽到临时文件后 source 调用（副本读全局 $CONF；三份同名 conf_get 不可共存一 shell）
copy_get() {
  local f="$1" k="$2"
  sed -n '/^conf_get() {/,/^}/p' "$CW_ROOT/scripts/$f" > "$B16/cg_$f.sh"
  bash -c "CONF='$B16/fixture.conf'; source '$B16/cg_$f.sh'; conf_get '$k'"
}
ok "成对双引号内 # 保留" "$(lib_get K_QH)" "a#b"
ok "成对单引号内空格保留" "$(lib_get K_SQ)" "a b"
ok "空白+行内注释截断" "$(lib_get K_HC)" "x"
ok "CRLF 去尾部回车" "$(lib_get K_CR | cat -v)" "unquoted"
ok "普通值原样" "$(lib_get K_PL)" "normal"
rc22=0; lib_get K_CM >/dev/null 2>&1 || rc22=$?
ok "注释行整行跳过" "$rc22" "1"
# 引号值 + 行尾注释/尾随空白组合（闭引号后只有空白或 # 注释 → 仍须剥引号取内值）
ok "双引号+行尾注释" "$(lib_get K_QC)" "val"
ok "双引号内含#+行尾注释" "$(lib_get K_QCS)" "a#b"
ok "单引号内含#保留" "$(lib_get K_QS)" "x # y"
ok "双引号+尾随空白" "$(lib_get K_QT)" "v"
# 四实现输出完全一致（逐键比对 lib 与三份副本的原始字节）
mismatch=0
for k in K_QH K_SQ K_HC K_CR K_PL K_CM K_QC K_QCS K_QS K_QT; do
  l="$(lib_get "$k" 2>/dev/null || true)"
  for f in cw-update.sh pr-automation.sh cw-greploop.sh; do
    c="$(copy_get "$f" "$k" 2>/dev/null || true)"
    [[ "$c" == "$l" ]] || mismatch=$((mismatch + 1))
  done
done
ok "四实现输出完全一致" "$mismatch" "0"
# 对抗轮4 Gap C 回归锁：workflow 标签提取段（# cw-label-extract: begin/end 之间）必须与
# 统一 conf 语义一致。旧写法裸剥引号：`LABEL_READY="ready-for-agent"  # 注释`
# （config.example.conf 的注释风格，恰是引导用户改标签处）→ 悬空引号+注释垃圾标签；
# CRLF conf 取值带回车。按标记抽取段喂 fixture 验证（段自包含：只依赖 $CONF）。
sed -n '/# cw-label-extract: begin/,/# cw-label-extract: end/p' \
  "$CW_ROOT/workflows/change-closure-signal.yml" > "$B16/extract.sh"
ok "workflow 提取段存在（begin/end 标记）" "$([[ -s "$B16/extract.sh" ]] && echo y)" "y"
printf 'LABEL_READY="ready-for-agent"  # 注释\nLABEL_CLOSURE_PENDING=%s\r\n' "'change-close-pending'" > "$B16/labels.conf"
out22w="$(CONF="$B16/labels.conf" bash -c "source '$B16/extract.sh'; echo \"READY=[\$LABEL_READY] CLOSURE=[\$LABEL_CLOSURE_PENDING]\"")"
ok "workflow 提取：引号+尾注释/CR 值" "$out22w" "READY=[ready-for-agent] CLOSURE=[change-close-pending]"
printf 'OTHER_KEY=x\n' > "$B16/labels-none.conf"
out22d="$(CONF="$B16/labels-none.conf" bash -c "source '$B16/extract.sh'; echo \"READY=[\$LABEL_READY] CLOSURE=[\$LABEL_CLOSURE_PENDING]\"")"
ok "workflow 提取：缺键走默认" "$out22d" "READY=[ready-for-agent] CLOSURE=[change-close-pending]"
# 清理前退回仓库根：sanitize 会删掉当前 cwd，否则后续用例继承已删除的 cwd 报 getcwd 噪声
cd "$CW_ROOT"
sanitize "$B16"

# ── 用例 23：cw-tickets-check 拆票自检（G0-POST 发布前门禁）───────────────────
# 契约（scripts/cw-tickets-check.sh 头部注释）：
#   0 = 全部通过（含 --help）；1 = 违规或用法错误
# 输入：tasks.md + 票面草稿目录（每票一文件；首行标题 `[change=<名>/<task号>]`，
#       正文七字段：Parent / What to build / Acceptance criteria / Blocked by / 接线归属 / 标签 / 粒度）
# 锁定：对账不符拒收（C1）/ 禁入信号拒收（C3-C4）/ expand–contract 角色豁免放行（C8）/
#       --live 对账（gh 桩，不联网）
echo ""
echo "[23] cw-tickets-check 拆票自检"
B17="$(mktemp -d)"
new_repo "$B17/repo" || exit 1
TC_SH="$CW_ROOT/scripts/cw-tickets-check.sh"

# 契约：--help 退 0；无参数（用法错误）退 1
# 陷阱（bash 3.2 实测）：set -e 下【直调】未找到的命令 + `|| rc=$?` 会把 127 折叠为 1，
# 「脚本缺失」与「正确拒收」不可区分；故本用例断言一律用命令替换形态（保留 127）或附输出断言。
rc=0; out23h="$("$TC_SH" --help 2>&1)" || rc=$?
ok "tickets-check --help 退 0" "$rc" "0"
case "$out23h" in *"用法"*) r23=0 ;; *) r23=1 ;; esac
ok "tickets-check --help 输出用法" "$r23" "0"
rc=0; out23n="$("$TC_SH" 2>&1)" || rc=$?
ok "tickets-check 无参数退 1" "$rc" "1"
case "$out23n" in *"用法"*) r23=0 ;; *) r23=1 ;; esac
ok "tickets-check 无参数输出用法" "$r23" "0"

# 场景 A：对账不符 —— tasks 2 条、草稿仅 1 个 → C1 拒收（列出缺失编号）
mkdir -p "$B17/a/drafts"
cat > "$B17/a/tasks.md" <<'EOF'
## 1. 阶段一

- [ ] 1.1 第一条任务描述
- [ ] 1.2 第二条任务描述
EOF
cat > "$B17/a/drafts/1.1.md" <<'EOF'
[change=fixture/1.1] 第一条任务描述

**Parent**: #1
**What to build**: 在页面上可见的第一项增量
**Acceptance criteria**:
- 在 `npm run dev` 打开的页面中，操作后可见第一项结果。
**Blocked by**: None — can start immediately
**接线归属**: 无新增导出（纯页面增量）
**标签**: ready-for-agent
**粒度**: 用户可见交付物
EOF
rc=0; out23a="$("$TC_SH" --change fixture --tasks "$B17/a/tasks.md" --drafts "$B17/a/drafts" 2>&1)" || rc=$?
ok "对账不符退 1" "$rc" "1"
case "$out23a" in *"1.2"*) r23=0 ;; *) r23=1 ;; esac
ok "对账不符列出缺失编号" "$r23" "0"

# 场景 B：禁入信号 —— AC 全部为库层断言且未声明 no-ui-impact → C3/C4 拒收
mkdir -p "$B17/b/drafts"
cat > "$B17/b/tasks.md" <<'EOF'
## 1. 阶段一

- [ ] 1.1 库层任务描述
EOF
cat > "$B17/b/drafts/1.1.md" <<'EOF'
[change=fixture/1.1] 库层任务描述

**Parent**: #1
**What to build**: 重构内部数据结构
**Acceptance criteria**:
- getBlocks() 返回块数组
- 类型检查通过
**Blocked by**: None — can start immediately
**接线归属**: 不适用（无新增导出）
**标签**: ready-for-agent
**粒度**: 用户可见交付物
EOF
rc=0; out23b="$("$TC_SH" --change fixture --tasks "$B17/b/tasks.md" --drafts "$B17/b/drafts" 2>&1)" || rc=$?
ok "禁入信号退 1" "$rc" "1"
case "$out23b" in *"- [C3]"*|*"- [C4]"*) r23=0 ;; *) r23=1 ;; esac
ok "禁入信号归属 C3/C4" "$r23" "0"

# 场景 C：expand–contract 角色声明票 → 豁免通过（退 0）
mkdir -p "$B17/c/drafts"
cat > "$B17/c/tasks.md" <<'EOF'
## 1. 阶段一

- [ ] 1.1 宽重构第一步
EOF
cat > "$B17/c/drafts/1.1.md" <<'EOF'
[change=fixture/1.1] 宽重构第一步

**Parent**: #1
**What to build**: 将旧数据形态 expand 为新结构（expand–contract 序列第一步）
**Acceptance criteria**:
- 新旧结构在构建产物中并存，存量用例全部通过
**Blocked by**: None — can start immediately
**接线归属**: 不适用（无新增导出）
**标签**: ready-for-agent, no-ui-impact
**粒度**: expand
EOF
rc=0; out23c="$("$TC_SH" --change fixture --tasks "$B17/c/tasks.md" --drafts "$B17/c/drafts" 2>&1)" || rc=$?
ok "expand–contract 角色豁免退 0" "$rc" "0"
case "$out23c" in *"全部通过"*) r23=0 ;; *) r23=1 ;; esac
ok "expand–contract 角色豁免输出全过" "$r23" "0"

# 场景 D：--live 对账（gh 桩；不联网）—— 匹配退 0 / 不符退 1
mkdir -p "$B17/stub"
cat > "$B17/stub/gh" <<'STUB'
#!/usr/bin/env bash
# 测试桩：忽略参数，按 GH_STUB_TITLES 输出 gh issue list 的 JSON 数组
printf '['
first=1; n=0
while IFS= read -r t; do
  [ -z "$t" ] && continue
  n=$((n + 1))
  [ "$first" -eq 1 ] || printf ','
  first=0
  printf '{"number":%d,"title":"%s"}' "$n" "$t"
done <<< "${GH_STUB_TITLES:-}"
printf ']\n'
STUB
chmod +x "$B17/stub/gh"
rc=0; out23d="$("env" GH_STUB_TITLES='[change=fixture/1.1] 第一条任务描述' PATH="$B17/stub:$PATH" \
  "$TC_SH" --change fixture --live --tasks "$B17/c/tasks.md" 2>&1)" || rc=$?
ok "live 对账匹配退 0" "$rc" "0"
case "$out23d" in *"全部通过"*) r23=0 ;; *) r23=1 ;; esac
ok "live 对账匹配输出全过" "$r23" "0"
rc=0; out23d2="$("env" GH_STUB_TITLES='[change=fixture/9.9] 幽灵票' PATH="$B17/stub:$PATH" \
  "$TC_SH" --change fixture --live --tasks "$B17/c/tasks.md" 2>&1)" || rc=$?
ok "live 对账不符退 1" "$rc" "1"
case "$out23d2" in *"9.9"*) r23=0 ;; *) r23=1 ;; esac
ok "live 对账不符列出幽灵票" "$r23" "0"

cd "$CW_ROOT"
sanitize "$B17"

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
