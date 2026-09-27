## Why

`skills/change-workflow/SKILL.md` 已膨胀至 266 行且持续增长（G8 process rot 风险）。agent 日常执行时不需要每次读完 266 行——他们需要一张「四拍速查卡」快速定位当前阶段的关键动作与出口条件，细节再回 SKILL.md 查阅。软件工厂用单文件 `AGENTS.md`（Isolate → Build → Prove → Ship）证明：把纪律压成一张纸，轻量、易读、易移植，直接对抗膨胀。

## What Changes

- 新增 `skills/change-workflow/agents-quick-reference.md`（四拍速查卡，目标 ≤ 80 行）：
  - **G0 规一**：spec 归一化 → 拆票 → 分支创建（含 DQ-1 检查）
  - **G1 实施**：每票实现 → QG-5 探针 → 先红后绿（DQ-2/DQ-3）
  - **G2 提交**：PR body 逐条写 `QG-x: 具体决策`（G2 引用纪律）
  - **G3/G4 收尾**：frontier 推进 → 归档 → 减法审计
  - 每拍附「质量门禁一句话索引」（QG-1..7 / DQ-1..8 各一行）
- `SKILL.md` 顶部加一段「日常照速查卡跑、细节回本文」的指引（≤ 5 行）
- 不删除 SKILL.md 任何内容——速查卡是**入口**，SKILL.md 仍是**完整参考**

## Capabilities

### New Capabilities
- `agents-quick-reference`: 四拍速查卡的内容结构、与 SKILL.md 的引用关系、质量门禁索引格式

### Modified Capabilities
<!-- 无现有 spec 的需求变更 -->

## Impact

- **新增文件**：`skills/change-workflow/agents-quick-reference.md`（受管文件，需加入 `lib/render.sh` 的 `cw_list_files`）
- **修改文件**：`skills/change-workflow/SKILL.md`（顶部加指引段）
- **连带影响**：`test/install-update-e2e.sh` 断言数 +1（20 → 21 受管文件）；`ci.yml` 无需改（glob 自动纳入）
- **消费仓影响**：md-bundle / mdpkg / clairis 下次升级自动获得速查卡
