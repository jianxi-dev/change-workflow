## ADDED Requirements

### Requirement: 规格双形态与验收锚点

系统 SHALL 要求每个 change 的规格同时产出两种形态并**双向链接**：**人读层**（主产物——proposal / design / AC / Scenario 的自然语言叙述，承载意图、理由与验收语义）与**机读层**（`conformance.json` 锚点集——每条锚点含具体期望值、来源、断言类型）。人读条目 MUST 携带锚点引用；锚点 MUST 回指存在的人读条目 id。

#### Scenario: 人读条目缺锚点

- **WHEN** 人读的某条 AC / Requirement 未携带任何验收锚点
- **THEN** G0 锚点门判定违规并拒收该票（fix-first：补锚点后重验）

#### Scenario: 孤儿锚点

- **WHEN** `conformance.json` 中存在不指向任何人读条目 id 的锚点
- **THEN** 判定违规并拒收

#### Scenario: 人读层不可丢

- **WHEN** 规格仅有机读制品而无可读叙述
- **THEN** 判定违规（规格 MUST 保留人能读懂的文字内容）

### Requirement: 锚点可断言性与来源

每条锚点 MUST 为可自动判定的形态（含具体值：文本 / 色值 / 数值+单位 / 状态迁移），且 MUST 标注可追溯来源（原型 §/截图#、一手观察、决策#）。「渲染正确 / 功能可用」类无具体值、或来源缺失者 MUST NOT 成为锚点。

#### Scenario: 不可断言的需求

- **WHEN** 某需求无法归约为含具体值的锚点
- **THEN** G0 判定该需求不可验证并拒收（不得进入拆票）

#### Scenario: 来源缺失

- **WHEN** 锚点未标注来源
- **THEN** 判定违规（无来源不得长出 requirement）

### Requirement: 一致性制品生成与哈希锁

系统 SHALL 在实现之前（G0）从原型结构化表**程序化生成**一致性制品：`conformance.json`、`baseline/*.png`（每定义态基准截图）、e2e 断言骨架；并 MUST 锁定制品哈希。实现阶段 MUST 只消费、MUST NOT 篡改 baseline（哈希变即核验失败）。

#### Scenario: 制品缺失

- **WHEN** 有原型的 change 进入实施但无一致性制品
- **THEN** G1 MUST NOT 开工

#### Scenario: baseline 被篡改

- **WHEN** baseline 制品哈希与锁不一致
- **THEN** 核验失败并拒收，须经独立模型复核后重新锁定

#### Scenario: 无原型时的锚点来源

- **WHEN** change 无原型
- **THEN** 锚点来源 MUST 为显式决策或一手观察（`来源:` 非空），否则 G0 拒收

### Requirement: CI 三层自动核验

系统 SHALL 在 CI 对实现运行三层自动核验：T1 确定量（计算样式 / DOM 属性 / 文本 vs `conformance.json`，精确）、T2 感知（实现截图 vs baseline 的像素/感知 diff + 多模态结构化判定）、T3 状态机（六态往返 + 无残留）。核验 MUST 在 CI 执行，MUST NOT 依赖人工观察。

#### Scenario: T1 确定量偏离

- **WHEN** 实现的色值 / 字阶 / 间距 / 图标名 / 几何与 `conformance.json` 不等
- **THEN** T1 判定失败，CI 红

#### Scenario: T2 感知偏离

- **WHEN** 实现截图与 baseline 的感知 diff 超出容差，或多模态判定为偏离
- **THEN** T2 判定失败，CI 红

#### Scenario: T3 状态往返失败

- **WHEN** 交互票的六态往返断言失败，或取消后存在残留
- **THEN** T3 判定失败，CI 红

#### Scenario: 核验自动执行

- **WHEN** 核验运行
- **THEN** 全过程由 CI 自动完成，无人工复核环节

### Requirement: 验证分离机制化（跨模型）

系统 SHALL 以**跨模型自动复核**实现判者 ≠ 写者（不同模型家族对同一 diff + 同一 baseline 独立判定，consensus 为高置信信号）；MUST NOT 将人工审批作为质量兜底。

#### Scenario: 单一模型自审

- **WHEN** 核验仅由实施所用模型完成
- **THEN** 判定不符合验证分离，须补跨模型复核

### Requirement: 证据 manifest 机检与降级收紧

交互类（ui-surface）票 MUST 产出证据 manifest（≥4 态 + 每态断言结果 + 产物引用），且 CI MUST 对已提交 manifest 做结构与关联校验。`cw-evidence.sh` 降级（exit 3）MUST 附机器可核验的理由并记录，MUST NOT 默认放行；降级 MUST NOT 改变门禁判据。

#### Scenario: 零产物

- **WHEN** ui-surface 票无证据 manifest
- **THEN** G2 / CI 拒收

#### Scenario: 散文冒充证据

- **WHEN** 证据为「测试通过数 + 文字描述」而无机读 manifest 与产物引用
- **THEN** 判定无效证据并拒收

#### Scenario: 降级无理由

- **WHEN** 以无 GUI / 无 ffmpeg 触发降级但无可核验理由
- **THEN** 判定违规（本地环境已具备截图条件）

### Requirement: ui-surface 机械触发

系统 SHALL 以「标签 ∪ diff 路径」析取判定 ui-surface：票带 ui-surface 标签，或 diff 触及 UI/渲染路径，任一命中即需证据与保真核验。

#### Scenario: 标签缺失但路径命中

- **WHEN** 票未标 ui-surface 但 diff 触及 UI 路径
- **THEN** 仍按 ui-surface 要求证据与保真核验

#### Scenario: 纯文档票豁免

- **WHEN** 票为纯文档 / 基建且既无标签、diff 也不触及 UI 路径
- **THEN** 不触发证据与保真核验

### Requirement: 反同义反复与反基线投毒

系统 SHALL 要求 expected value 仅来自锁定的 baseline 制品，断言 MUST 按锚点 id **具名引用**（MUST NOT 内联实现自产的字面量）；锚点 MUST 由原型结构化表程序化解析，MUST NOT 由实现者手填。

#### Scenario: 断言内联实现自产值

- **WHEN** e2e 断言使用实现自产的字面量而非按锚点 id 引用
- **THEN** 判定违规（同义反复）

#### Scenario: baseline 反填

- **WHEN** 锚点值被按「已实现」反填而非来自原型
- **THEN** 独立模型复核判定违规，baseline 不得锁定

### Requirement: §八 三指标退役判据

系统 SHALL 以三指标对账门禁（**执行率 / 阻断数 / 下游归因缺陷数**）取代单一「捕获次数」；退役判据 MUST 为「高执行 + 零阻断 + 零下游事故」。关键词型门禁的「高捕获、零预防价值」MUST 可被识别。

#### Scenario: 高执行零阻断零事故

- **WHEN** 某门禁执行率高、零阻断，且该领域无下游事故
- **THEN** 列为可退役候选（含数据留痕），不得凭印象删除

#### Scenario: 关键词门禁

- **WHEN** 某门禁为关键词形态，每次命中但不拦真实缺陷
- **THEN** 按「高捕获零价值」识别，提出合并 / 退役
