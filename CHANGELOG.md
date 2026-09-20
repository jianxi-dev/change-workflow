## 1.1.4 — 2026-09-20

### 修复：接管模式输出文案与 1.1.3 的新语义不符

1.1.3 改为「不同文件不写基线」，但输出仍称「当前内容已被接管为基线」——
**文案与实际行为矛盾**，会误导用户以为 `.new` 可以放着不管。

改为准确描述，并给出**逐个文件**的处理方式：

```
以下文件与 X.Y.Z 模板不同…
**这些文件未写基线** —— 在你解决之前，每次升级都会继续报告它们（不会被静默覆盖）。

处理方式（每个文件任选其一）：
  1. 保留本地：rm <file>.new
  2. 采用新版：mv <file>.new <file>   （下次升级会自动写入基线）
  3. 人工合并：diff <file> <file>.new → 合并 → rm <file>.new
  4. 全部采用新版：./update.sh --force

全部解决后再次运行 ./update.sh 即归一（退出码 0）。
```

> 教训：**改了行为必须同步改文案** —— 否则「不静默覆盖」的保障会被错误的提示语抵消。

---

## 1.1.3 — 2026-09-20

### 修复（严重）：接管模式会静默覆盖本地定制

**症状**：`--adopt` 接管后，若用户尚未处理 `.new` 旁路文件就再次运行 `update.sh`，
本地定制文件会被**静默覆盖**。

**根因**：接管模式把**当前内容**（含本地定制）记为基线。下次更新时
`current == baseline` 被判为「未修改」→ 安全覆盖 → 定制丢失。

**实际损害**：clairis 升级时 `domain.md` / `issue-tracker.md` / `triage-labels.md`
被覆盖（已从 `.bak` + git 恢复，零损失）。

**修复**：接管模式下**与模板不同的文件不写基线** → 持续被标记为冲突，
直到用户显式解决（`mv .new → file` 或 `--force`）。

### 修复：`is_in_list` 使用了 bash 4+ 特性

`local -n`（nameref）需 bash 4.3+，而 macOS 自带 `/bin/bash` 是 **3.2** →
函数静默失效（`local: -n: invalid option`）→ 修复逻辑完全没生效。

改为可移植写法（`shift` + `"$@"` 遍历），并把定义移到首次调用之前。

### 新增防线

- **CI**：bash 3.2 兼容性静态检查（排除注释）。CI runner 是 bash 5，
  这类缺陷在 CI 上**永远绿**，只在 macOS 暴露 —— 属「CI 绿、本机红」的反向形态。
- **e2e 用例 10**：接管 → 再次更新，定制不得被覆盖（回归锁）。

### 验证

```
$ ./test/install-update-e2e.sh
 通过 43 · 失败 0
 全部通过 ✅
```

---

## 1.1.2 — 2026-09-20

### 修复

- **`scripts/pr-automation.sh`：`--refs-only` 时 commit message 使用 `refs #N`**
  此前 commit message 恒为 `fixes #$ISSUE`，**无视 `--refs-only`**。
  该 flag 用于 parent/spec issue 的 PR（防止合并时提前关闭其生命周期），
  PR body 已正确使用 `Refs #N`，但 **commit message 仍写 `fixes #N`** ——
  而 GitHub 对两者**都会**触发自动关闭，故 `--refs-only` 实际被**部分破坏**。
  来源：clairis 的修复（其 HEAD commit），此前**从未回灌上游**。

### 说明

这是升级 mdpkg / clairis 时通过 `.new` 旁路暴露的**第三个上游缺口**：

| # | 缺口 | 来源仓库 | 版本 |
|---|---|---|---|
| 1 | `git add -f` 回退（.gitignore 匹配路径） | mdpkg PR #24 | 1.1.1 |
| 2 | 看板常量改为从 conf 读取（+ option ID 泄漏） | mdpkg 升级暴露 | 1.1.1 |
| 3 | `--refs-only` 的 commit message | clairis HEAD commit | 1.1.2 |

**三个都印证了接管模式「不静默覆盖」的价值** —— 若直接 `--force`，这些下游改进会被静默丢弃。

---

## 1.1.1 — 2026-09-20

### 修复

- **`scripts/pr-automation.sh`：补 `git add -f` 回退**
  白名单路径若被 `.gitignore` 匹配（如 force-tracked 的 `.omo/notepads/**`），`git add` 会失败。
  现在自动 fallback 到 `git add -f`（路径已由 `--files` 显式限定，故安全）。
  来源：mdpkg PR #24 的成果，此前**从未回灌上游**。

- **`skills/change-workflow/SKILL.md`：看板常量改为从 conf 读取**
  模板原本**烘焙字面量 option ID**（`a50766ca` / `4cbd348f` / `8c7f2979` / `a7011ca0`），
  把安装源仓库的值泄漏给所有消费者；且与 `DESIGN.md` 矛盾 ——
  DESIGN 明确「脚本 `source` 该文件；**skill 读取它取看板常量**」。
  改为读取 `.change-workflow.conf`，与设计一致、无漂移、无泄漏。

### 说明

两项均通过 **mdpkg 升级时的 `.new` 旁路**暴露 —— 这正是接管模式「不静默覆盖、交回人工核对」的价值：
若当初直接 `--force` 覆盖，mdpkg 的 `git add -f` 修复会被**静默丢弃**。

---

# CHANGELOG

本工具包遵循语义化版本。安装后可用 `./update.sh --check` 查看是否有新版本。

## 1.1.0 — 2026-09-20

### 新增：开发与测试质量门禁（QG / DQ）

来源：一次真实交付失败的复盘 —— 某 change 的 9 个 PR 中 8 个对应用层与 e2e **双双零改动**，12 张票全打勾、CI 全绿，而用户打开页面**看不到任何变化**；随后的缺陷修复期又抓出 4 个「自测全绿但实际无效」的假修复（4/4 由独立探针推翻）。

- **新增规范** `docs/agents/quality-gates.md`：QG-1..QG-7（变更开发侧）+ DQ-1..DQ-8（缺陷处理侧），每条含「规则 / 理由 / 实证案例 / 如何验证」四小节
- **`docs/agents/task-tracking.md`**：§3 票内容加 QG-1/QG-3 与禁入信号；§7 加 QG-2/QG-4/QG-5/QG-6 硬门禁
- **`docs/agents/defect-workflow.md`**：新增「修复质量门禁」章节（DQ-1..DQ-8）
- **`skills/change-workflow/SKILL.md`**：G0 切片约束加 QG-7/QG-3；G1 加第 0.5 步 QG 前置校验、QG-2 e2e 硬门禁、QG-6 集成 checkpoint；G1 出口加 QG-5 独立验证；缺陷处理机制章节每环节标注 DQ 编号
- **`setup.sh` 的 AGENTS.md 索引段**：补 Quality gates 段（QG/DQ 核心条目）

### 新增：更新机制

此前 `setup.sh` 只能首装（已存在文件一律跳过），无任何升级路径。

- **`VERSION`**：工具包版本号；安装时写入目标仓库 `.change-workflow.conf` 的 `TOOLKIT_VERSION`
- **`update.sh`**：增量更新已安装仓库
  - `--check` 仅比对版本、不落盘
  - `--dry-run` 打印将执行的动作
  - `--force` 忽略本地改动强制覆盖（先备份）
  - **冲突保护**：以安装/上次更新时记录的基线哈希判断文件是否被本地修改；未修改 → 安全覆盖；已修改 → 写 `<file>.new` 旁路文件并报告，不覆盖
  - 覆盖前一律写 `.bak`
- **`.change-workflow.manifest`**：记录每个受管文件安装时的基线 sha256，供 update 判定本地改动
- **`lib/render.sh`**：抽取共享的占位符替换逻辑，供 setup/update 共用（防两处逻辑漂移）
- **新增占位符**：`{{REPO_ROOT}}`（目标仓库根绝对路径）、`{{EFFECTIVE_DATE}}`（安装日期）

### 修复：模板硬编码其它仓库的路径

`docs/agents/*.md` 模板中残留 `cd /Users/mason/ToHighs/md-bundle` 等硬编码路径，安装到其它仓库后会指向错误目录。已改为 `{{REPO_ROOT}}` 占位符，由安装/更新时替换为目标仓库真实根路径。

> **已安装仓库注意**：若你的仓库此前安装过 1.0.0，其中的 `cd <其它仓库路径>` 是错的；升级到 1.1.0 会自动修正。

---

## 1.0.0 — 初始版本

- `skills/change-workflow/SKILL.md`：G0-G4 五 gate + fix-first 自愈回路 + 缺陷机制
- `scripts/pr-automation.sh`：issue 驱动分支/PR 自动化
- `workflows/change-closure-signal.yml`：CI 合并信号
- `docs/agents/*.md`：7 份规范模板（task-tracking / issue-tracker / project-board / triage-labels / defect-workflow / domain / incident-*）
- `setup.sh`：安装向导
