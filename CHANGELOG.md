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
