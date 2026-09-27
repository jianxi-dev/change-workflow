## Why

`verify-<app>` 静态验证技能方案（pstack G1 反哺）经 md-bundle 试点后结论：**不成立，撤销**。三条依据：

1. **静态文档装不下高频变化的知识**：特性地图与选择器几天到几周过期；腐烂的文档比没有文档更糟（agent 会信任它、被误导），而「每票随手写」是 fail-safe 的。
2. **pstack 自身触发条件不满足**：该技能的适用场景是「a project has **no scripted way** to prove UI/CLI/service behavior」；而工具包的消费仓**均有 UI 且均已有 e2e 基建**——scripted 验证路径本来就存在。
3. **平行结构必然漂移**：QG-2 已要求用户可见变更必须新增/扩展 e2e 用例（活代码、CI 强制、随代码维护）。在其之上再叠一份静态技能副本，两边都要维护但只有活代码一边被约束。

替代方案：把稳定部分（探针形态约定）落进既有规范——**活代码（e2e 用例）优先，轻量探针降级，禁止静态技能副本**。

## What Changes

- **撤销**：删除消费仓的 `verify-md-bundle` 技能（SKILL.md + 5 个特性文件 + 特性地图索引）与试点产物（自证截图、临时脚本）
- **SKILL.md**：G1 出口 3.5 条款从「调用 `verify-md-bundle` 技能」重写为「探针形态（活代码优先）」
- **evidence-capture.md**：新增「三、探针形态（活代码优先）」节（四段式：规则/理由/实证案例/如何验证）；后续节号顺延（§三→§四、§五→§六 等 2 处跨节引用同步）
- **e2e**：新增用例 27（3 断言）守约定存在与零残留

## Capabilities

### New Capabilities
- `qg5-probe-convention`: QG-5 探针形态约定——活代码（e2e 用例）优先 / 轻量探针降级 / 禁止静态技能副本

### Modified Capabilities
<!-- 无现有 spec 的需求变更 -->

## Impact

- **消费仓（md-bundle）**：删除 7 个技能文件与试点产物
- **本仓**：`skills/change-workflow/SKILL.md`、`docs/agents/evidence-capture.md`、`test/install-update-e2e.sh`（+3 断言）、`VERSION`/`CHANGELOG.md`/`config.example.conf`
- **消费仓升级**：SKILL.md 与 evidence-capture.md 为受管文件，升级后旧 verify 引用消失、探针形态约定生效