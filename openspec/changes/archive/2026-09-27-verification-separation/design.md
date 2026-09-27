## Context

SKILL.md:183 声称「验证者（orchestrator，非实施者）」，但单会话模型下该规则**无机制保障**——同一 agent 既实施又验证。

Omo 的 Atlas 已有委派机制（Sisyphus → Atlas），但 Atlas 既执行又验证（自证），没有解决验证者≠实施者。

**约束**：
- 复用 Omo 现有委派机制（Sisyphus → Atlas），不创建新的子代理类型
- 不改变 G0-G4 流程语义——只在 G1 出口加一层独立验证
- 纯文档规则，无新脚本

## Goals / Non-Goals

**Goals:**
- G1 出口实施验证分离：Atlas 实施，Sisyphus 亲自跑 QG-5
- Sisyphus 持有跨票 SHA 视图，收口时拦截过期验证
- Atlas 自证（lsp_diagnostics）作为最低门槛，Sisyphus 的 QG-5 作为应用专属验证

**Non-Goals:**
- 不重新发明委派机制（Atlas 已有）
- 不改变现有 G0-G4 流程语义
- 不引入新的 agent 类型

## Decisions

### 决策 1：复用 Atlas 作为执行者

**选择**：Sisyphus → Atlas 委派 G1 实施，不创建新的子代理类型。

**理由**：
- Atlas 已有委派机制和干净上下文
- 避免重复造轮子
- 与 Omo 现有架构一致

**备选**：创建新的子代理类型 — 拒绝，Atlas 已经是合适的执行者。

### 决策 2：Sisyphus 亲自跑 QG-5

**选择**：Sisyphus 在 G1 出口亲自跑 QG-5 探针，不依赖 Atlas 的自证。

**理由**：
- 真正分离验证者≠实施者
- Sisyphus 只保摘要（spec + ticket + 出口条件），上下文成本可控
- 与 Omo 现有机制兼容

**备选**：Atlas 跑 QG-5 — 拒绝，Atlas 自证合格的风险无法消除。

### 决策 3：两层验证互补

**选择**：Atlas 的 lsp_diagnostics 作为最低门槛，Sisyphus 的 QG-5 作为应用专属验证。

**理由**：
- Atlas 抓语法/类型错误（静态、与业务无关）
- Sisyphus 抓业务逻辑错误（动态、与业务相关）
- 两层验证互补，不冲突

## Risks / Trade-offs

- **[Sisyphus 上下文成本]** → Sisyphus 只保摘要，不加载全部 diff；QG-5 探针只跑当前票的相关文件
- **[Atlas 自证被绕过]** → Atlas 的 lsp_diagnostics 保留作为最低门槛，但 Sisyphus 的 QG-5 是更高门槛，不能绕过
- **[与 Omo 现有机制的兼容]** → 只需要在 Sisyphus 的 G1 出口加一步「跑 QG-5 探针」，不需要修改 Omo 核心

## Migration Plan

1. 在 `SKILL.md` G1 出口加「验证分离」机制
2. 运行 e2e 确认全绿
3. 发布时 VERSION + CHANGELOG 同步

**回滚**：从 SKILL.md 删除该段即可。
