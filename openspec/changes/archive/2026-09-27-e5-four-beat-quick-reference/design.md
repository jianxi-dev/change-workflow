## Context

`skills/change-workflow/SKILL.md` 当前 266 行，包含 G0-G4 完整编排、frontier 循环、质量门禁引用纪律、决策日志、验证时效、减法审计等内容。agent 每次启动 change 流程时需要读完或搜索全文才能定位当前阶段动作。

软件工厂的 `AGENTS.md` 用四拍（Isolate → Build → Prove → Ship）把整个纪律压进一张纸，证明「轻量入口 + 详细参考」的双层结构可行。本设计将同样的模式应用到 change-workflow。

**约束**：
- 速查卡是**入口**，不替代 SKILL.md——SKILL.md 仍是完整参考
- 受管文件变更需同步 `lib/render.sh` + `test/install-update-e2e.sh` 断言
- 模板头规范：首行 `<!-- change-workflow 工具包模板`，安装时剥除

## Goals / Non-Goals

**Goals:**
- 新增 ≤ 80 行的四拍速查卡，覆盖 G0-G4 关键动作与出口条件
- 质量门禁 QG-1..7 / DQ-1..8 各一句话索引
- SKILL.md 顶部加 ≤ 5 行指引，建立双向引用
- 纳入受管文件清单，消费仓升级自动获得

**Non-Goals:**
- 不删除或重写 SKILL.md 任何内容
- 不改变 G0-G4 流程语义（纯呈现层重组）
- 不引入新脚本或新依赖

## Decisions

### 决策 1：速查卡放 `skills/change-workflow/` 而非根级 `AGENTS.md`

**选择**：放在 `skills/change-workflow/agents-quick-reference.md`，与 SKILL.md 同目录。

**理由**：
- 作为受管文件，安装时自动部署到消费仓的 `.opencode/skills/change-workflow/` 目录
- 与 SKILL.md 同目录便于互相引用
- 根级 `AGENTS.md` 是消费仓的编排入口，放那里会混淆「工具包源」与「消费仓产物」

**备选**：根级 `AGENTS.md` — 拒绝，因为它是消费仓编排文件，不是工具包受管文件。

### 决策 2：四拍映射 G0-G4 而非重新划分阶段

**选择**：G0 规一 → G1 实施 → G2 提交 → G3/G4 收尾。

**理由**：
- 与现有 SKILL.md 的 G0-G4 编号一一对应，零学习成本
- 软件工厂的四拍（Isolate/Build/Prove/Ship）是通用模式，映射到 CW 的 G0-G4 即可

### 决策 3：质量门禁索引用表格而非列表

**选择**：QG-1..7 和 DQ-1..8 用两列表格（编号 | 一句话描述）。

**理由**：
- 表格在 80 行限制内信息密度最高
- agent 扫一眼即可定位需要的门禁

## Risks / Trade-offs

- **[速查卡与 SKILL.md 内容漂移]** → 速查卡只写关键动作与出口条件，不复制详细规则；详细规则只在 SKILL.md 维护，速查卡通过「详见 SKILL.md §」引用
- **[80 行限制导致信息不足]** → 用表格压缩门禁索引；每拍只写 3-5 个关键动作 + 出口条件
- **[受管文件计数变更影响 e2e]** → 先改 `lib/render.sh` + 断言，再改速查卡内容，确保 e2e 先红后绿

## Migration Plan

1. 在 `lib/render.sh` 的 `cw_list_files` 加入 `agents-quick-reference.md`
2. 更新 `test/install-update-e2e.sh` 受管文件计数断言 20 → 21
3. 创建 `skills/change-workflow/agents-quick-reference.md` 模板
4. 修改 `skills/change-workflow/SKILL.md` 顶部加指引段
5. 运行 e2e 确认全绿
6. 发布时 VERSION + CHANGELOG 同步

**回滚**：从 `cw_list_files` 移除新文件 + 恢复断言数 + 删除模板文件 + 还原 SKILL.md 顶部。
