# agents-quick-reference Specification

## Purpose
TBD - created by archiving change e5-four-beat-quick-reference. Update Purpose after archive.
## Requirements
### Requirement: 四拍速查卡文件存在且可独立阅读

系统 SHALL 在 `skills/change-workflow/agents-quick-reference.md` 提供一份独立于 SKILL.md 的四拍速查卡，agent 无需读取 SKILL.md 全文即可据此完成日常变更流程。

#### Scenario: agent 仅凭速查卡完成 G0-G4 流程

- **WHEN** agent 接到一个新 change 任务
- **THEN** 仅阅读 `agents-quick-reference.md` 即可知道 G0 规一、G1 实施、G2 提交、G3/G4 收尾各阶段的关键动作与出口条件

#### Scenario: 速查卡行数上限

- **WHEN** 检查速查卡文件行数
- **THEN** 文件总行数 MUST ≤ 80 行（含标题与分隔符）

### Requirement: 四拍结构与质量门禁索引

速查卡 SHALL 按四拍组织内容，每拍包含关键动作与出口条件，并附质量门禁一句话索引。

#### Scenario: 四拍完整覆盖

- **WHEN** 检查速查卡结构
- **THEN** MUST 包含以下四拍：
  - G0 规一：spec 归一化 → 拆票 → 分支创建（含 DQ-1 检查）
  - G1 实施：每票实现 → QG-5 探针 → 先红后绿（DQ-2/DQ-3）
  - G2 提交：PR body 逐条写 `QG-x: 具体决策`（G2 引用纪律）
  - G3/G4 收尾：frontier 推进 → 归档 → 减法审计

#### Scenario: 质量门禁索引格式

- **WHEN** 检查速查卡的质量门禁索引段
- **THEN** QG-1..7 与 DQ-1..8 各有一行，格式为 `QG-x / DQ-x: <一句话描述>`

### Requirement: 速查卡与 SKILL.md 的双向引用

SKILL.md 顶部 SHALL 加入指引段，告知 agent 日常照速查卡跑、细节回 SKILL.md。速查卡每拍 SHALL 标注「详见 SKILL.md §<段名>」的引用。

#### Scenario: SKILL.md 顶部指引

- **WHEN** 阅读 SKILL.md 前 10 行
- **THEN** 可见「日常执行照 `agents-quick-reference.md` 四拍跑，细节回本文对应段」的指引

#### Scenario: 速查卡引用 SKILL.md

- **WHEN** 阅读速查卡任意一拍
- **THEN** 该拍末尾有「详见 SKILL.md §<段名>」的引用标注

### Requirement: 速查卡纳入受管文件清单

`agents-quick-reference.md` SHALL 被加入 `lib/render.sh` 的 `cw_list_files` 受管文件清单，确保安装/升级时自动部署到消费仓。

#### Scenario: 受管文件计数更新

- **WHEN** 检查 `lib/render.sh` 的 `cw_list_files` 函数
- **THEN** 受管文件数从 20 增至 21，包含 `agents-quick-reference.md`

#### Scenario: e2e 测试断言更新

- **WHEN** 运行 `test/install-update-e2e.sh`
- **THEN** 受管文件计数断言从 20 更新为 21，全部用例通过

