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
# A5（R1）模式保持回归锁：mktemp 恒 0600 曾随 mv 带进受管文件（首装 docs=600、脚本=711）。
# 新建 → 0644；脚本 = 0644 + cw_chmod_scripts 的 +x → 755；manifest 新建 → 644。
ok "docs 模式 644" "$(fmode docs/agents/domain.md)" "644"
ok "脚本模式 755" "$(fmode scripts/cw-evidence.sh)" "755"
ok "manifest 模式 644" "$(fmode .change-workflow.manifest)" "644"
ok "manifest 行数" "$(wc -l < .change-workflow.manifest | tr -d ' ')" "18"
ok "conf 版本已更新" "$(grep -o "$(tr -d '[:space:]' < "$CW_ROOT/VERSION")" .change-workflow.conf | head -1)" "$(tr -d '[:space:]' < "$CW_ROOT/VERSION")"
ok "无残留占位符" "$(grep -rho '{{[A-Z_]*}}' docs/agents/ .opencode/skills/ 2>/dev/null | sort -u | wc -l | tr -d ' ')" "0"

# ── 用例 2：幂等 ─────────────────────────────────────────────────────────────
echo ""
echo "[2] 幂等（版本回退后重跑）"
set_version "1.0.0"
# 不可用 `cmd | grep -q`：grep -q 命中即关管道 → 上游收 SIGPIPE(141) → pipefail 判失败 → set -e 终止。
out2="$("$CW_ROOT/update.sh" --target "$PWD" 2>&1 || true)"
case "$out2" in *"已最新 18"*) r2=0 ;; *) r2=1 ;; esac
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
# A5（R1）覆盖更新保持目标模式（曾 644→600），新建 .bak → 644（曾 600）
ok "覆盖后模式保持 644" "$(fmode docs/agents/domain.md)" "644"
ok ".bak 模式 644" "$(fmode docs/agents/domain.md.bak)" "644"

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
# 受管脚本必须可执行（cw_chmod_scripts 从受管清单派生，1.2.0/1.3.0 两次同因缺陷）
ok "pr-automation 可执行" "$([[ -x scripts/pr-automation.sh ]] && echo y)" "y"
ok "cw-evidence 可执行" "$([[ -x scripts/cw-evidence.sh ]] && echo y)" "y"
ok "cw-greploop 可执行" "$([[ -x scripts/cw-greploop.sh ]] && echo y)" "y"
# 3 个文件与模板不同（未剥头的原始模板 ≠ 渲染结果）→ 不写基线 → manifest = 18 - 3 = 15
ok "manifest 条目数" "$(wc -l < .change-workflow.manifest | tr -d ' ')" "15"
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
ok "仓库特有值残留" "$(grep -rl 'jianxi-dev/md-bundle\|jianxi-dev/mdpkg\|jianxi-dev/clairis\|/Users/mason\|PVT_kwDO\|PVTSSF_' \
  "$CW_ROOT/docs/agents" "$CW_ROOT/skills" "$CW_ROOT/scripts" "$CW_ROOT/workflows" 2>/dev/null \
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
ok "干净仓受管文件数" "$(wc -l < .change-workflow.manifest | tr -d ' ')" "18"

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
sanitize "$B9"

# ── 用例 16：符号链接拒绝（C2 边界）──────────────────────────────────────────
# 受管文件被换成符号链接时，重定向/覆盖会写穿到链接指向处 —— cw_refuse_symlink
# 必须在任何写入前退 1（lib/render.sh:62-68；update.sh:171/234-235/378-379）。
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
# 链接改到目标权限位（lib/render.sh:154）。把已安装的 cw-evidence.sh 换成指向
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
