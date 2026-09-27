## Why

SKILL.md:183 声称「验证者（orchestrator，非实施者）」，但单会话模型下该规则**无机制保障**——同一 agent 既实施又验证。Omo 的 Atlas 已有委派机制（Sisyphus → Atlas），但 Atlas 既执行又验证（自证），没有解决验证者≠实施者。需要聚焦「验证分离」：复用 Atlas 作为执行者，编排器（Sisyphus）亲自跑 QG-5 探针。

## What Changes

- 在 SKILL.md G1 出口加「验证分离」机制：
  - Atlas（执行者）完成 G1 实施后返回摘要（diff 统计 + 出口条件结果）
  - Sisyphus（编排器）亲自跑 QG-5 探针，不依赖 Atlas 的自证
  - Sisyphus 持有跨票 SHA 视图，收口时 `--verified-sha` 拦截过期验证
- 不改变现有 G0-G4 流程语义——只在 G1 出口加一层独立验证
- 复用 Omo 现有委派机制（Sisyphus → Atlas），不创建新的子代理类型

## Capabilities

### New Capabilities
- `verification-separation`: G1 出口的验证分离机制——编排器亲自跑 QG-5 探针、跨票 SHA 视图、Atlas 自证作为最低门槛

### Modified Capabilities
<!-- 无现有 spec 的需求变更 -->

## Impact

- **修改文件**：`skills/change-workflow/SKILL.md`（G1 出口加验证分离机制）
- **无新增文件**：纯文档规则，无新脚本
- **消费仓影响**：无（SKILL.md 是受管文件，升级自动获得）
- **与 Omo 的关系**：复用 Atlas 作为执行者，Sisyphus 聚焦验证层
