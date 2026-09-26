## Why

拆票（G0-POST）环节目前依赖外部 `to-tickets` skill 的「Quiz the user」人工确认（原文：「Iterate until the user approves the breakdown」）。该确认既非本流程设计的 gate——与本仓三处「唯一人工介入 = risk-medium/high PR 合并确认」声明（`SKILL.md:195` / `task-tracking.md:215` / `DESIGN.md:112`）自相矛盾——其判据又大部分已可由本仓既有门禁机检。同时，现行粒度规则执行空心：QG-7 是 7 条 QG 中唯一「如何验证」没有可执行命令的，「过细」在全仓无操作化定义，票内容机检为零。现在具备条件用「机检 + 声明制 + 逃逸闭环」退役该人工确认，使拆票质量可判定、可审计、可演进。

## What Changes

- 新增 `scripts/cw-tickets-check.sh`：拆票自检脚本（C1-C8 检查集），在 G0-POST `gh issue create` 之前运行，退出码 0/1，输出即证据（沿用 QG-5 证据纪律）。
- `skills/change-workflow/SKILL.md`：**BREAKING** 拆票环节不再包含 quiz 人工确认——`:140` 改为「自检协议」（跑脚本 → 三项书面自答 → 全绿自动发布）；`:102` 表格与 `:151` 对账同步。
- `docs/agents/quality-gates.md`：QG-7「如何验证」补可执行命令（补上 7 条 QG 中唯一的执行空缺）；§四反向验收判据呼应。
- `docs/agents/task-tracking.md`：§2 增加「过粗/过细」声明制定义；§4 模板补回缺失的「接线归属」「标签」字段（修复既有漂移）。
- 受管面与验证联动：`lib/render.sh` 受管清单注册新脚本；e2e 断言先行（先红后绿）；CI 脚本清单同步。

## Capabilities

### New Capabilities
- `ticket-split-self-check`: 拆票发布前自检——机检检查集（对账双射 / 六字段 / 纵向切片形态 / 禁入信号 / Blocked by 结构 / 豁免显式 / 规模钩子 / 粒度声明与重叠检测）、quiz 语义退役与自动发布、三项不可机检判断的声明制留痕、逃逸捕获与规则演进。

### Modified Capabilities
（无：`openspec/specs/` 当前为空，无既有 capability 可改）

## Impact

- 受管文件（消费仓侧）：新增 1 脚本 + 修改 3 份模板（`SKILL.md` / `quality-gates.md` / `task-tracking.md`）；md-bundle 的 `quality-gates.md` 为 LOCAL 哨兵，升级时会出 `.new` + 退 1，需一次手动合并（预期内）。
- 验证面：`test/install-update-e2e.sh` 断言（先红后绿）、`.github/workflows/ci.yml` 脚本清单、`test/rollout-check.sh` 三仓预演。
- 流程面：落地后 `SKILL.md:195` / `task-tracking.md:215` / `DESIGN.md:112` 三处「唯一人工介入」声明复真。
- 依赖：无新增（bash 3.2 + `gh` + `git` + `python3` 既有栈）。