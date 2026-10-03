## ADDED Requirements

### Requirement: 需求输入门（L-1 契约门）

系统 SHALL 要求任何以「对标 / 学习某产品 / 补齐某能力」为由的 change，在进入 G0 拆票前，其**需求输入包**（`docs/requirements/<change>/input-package.md` 或 `requirements.md` 增补段）满足五条契约：来源可追溯、空白显式化、一手证据、冲突显式、验收锚点。该门**合并**学习层证据与 ideation 来源，二者同属 G0-PRE 输入漏斗。

#### Scenario: 来源缺失

- **WHEN** 需求输入包中存在未标注 `来源:` 的需求条目
- **THEN** 需求输入门判定违规，change 不得进入 G0 拆票（fix-first：补来源后重验）

#### Scenario: 空白被规格引用

- **WHEN** 学习/研究中未观察到的行为（应标 `open-question`）被某条规格条目引用
- **THEN** 阻断该规格条目，禁止用「想当然」补空白

#### Scenario: 一手证据缺失

- **WHEN** 存在对标/学习类结论，但 `docs/research/<topic>/` 下无截图/录屏/来源版本
- **THEN** 判定违规（结论不可核验）

#### Scenario: 纯重构/文档票豁免

- **WHEN** change 为纯重构 / 纯文档 / 纯基建
- **THEN** 票上显式标注 `no-ui-impact`，需求输入门不适用

### Requirement: AC 三分类（修订 QG-1）

系统 SHALL 要求用户可见票的 Acceptance Criteria **同时**覆盖三类：① 存在（打开页面后出现 X）、② 生命周期（覆盖 `打开·切换·取消·外部点击·空态·关闭` 六态，并断言取消后无残留）、③ 保真（可判真伪的文本/像素结果，而非「渲染正确」）。缺一即违规。

#### Scenario: 仅存在性 AC

- **WHEN** 票的 AC 只有「打开页面…出现 X」，无生命周期与保真陈述
- **THEN** `cw-tickets-check.sh` C3/C4 判定违规，子票不得发布

#### Scenario: 生命周期六态

- **WHEN** 票涉及浮层 / 插入 / 可取消 / 可关闭交互
- **THEN** AC 须覆盖适用生命周期态，并含「取消后无残留」的可观测断言

#### Scenario: 保真文本相等

- **WHEN** 票涉及渲染 / 装饰 / 插入结果
- **THEN** AC 须含可判真伪的文本/像素结果（例：卡片标头文本严格等于「注释」；fenced code 行不含反引号）

### Requirement: 设计→规格保真（并入 QG-1 第③类）

系统 SHALL 要求从设计稿/设计文档转 requirement 时，设计的**交互动词**（如单元格 contenteditable）不得被弱化，设计的**退出语义/导航/边界**（Tab / Esc / 外部点击）必须逐条进入 requirement 的 Scenario。

#### Scenario: 设计行为无对应 Scenario

- **WHEN** 设计稿写明某交互动词或退出语义，而 requirement 无对应 Scenario（或被降级为弱表述）
- **THEN** review 判定保真违规，须补齐 Scenario 后方可实施

### Requirement: 断言强度阶梯（修订 QG-4）

系统 SHALL 要求 e2e 断言落在阶梯中**尽可能高**的层级：存在（`toHaveCount(1)`，仅用于确认挂载）→ 可见（计算样式非隐藏）→ 文本相等（`toHaveText` / `textContent`）→ 状态往返（操作→反向→回初始）→ 视觉（多态截图对比）。渲染 / 装饰 / 插入 / 浮层类变更至少到**文本相等**；可取消 / 可关闭交互必须到**状态往返**。

#### Scenario: 存在性断言冒充可见变更

- **WHEN** 渲染/浮层类变更的 e2e 唯一断言为 `toHaveCount(1)`
- **THEN** 判定违反断言阶梯

#### Scenario: 可取消交互无往返断言

- **WHEN** 存在「可取消/可关闭」交互，但 e2e 无「操作→取消→回初始」的状态往返断言
- **THEN** 判定违规（无法捕获「取消后残留」）

### Requirement: 视觉探针与多态截图（修订 QG-5）

系统 SHALL 将**视觉探针**纳入 QG-5 探针类型（关键态截图 + 人工/多模态复核）；对交互类 UI 变更，截图证据必须覆盖**状态覆盖矩阵**（`打开·切换·取消·外部点击·空态·关闭` 中适用项，至少 4 态）并产出机读清单 `.artifacts/<task>/state-coverage.json`。**单层截图对交互票明确不足**。

#### Scenario: 交互票仅单层截图

- **WHEN** 交互类 UI 变更的截图证据只有一张单点截图
- **THEN** 判定证据不足（须补状态覆盖矩阵）

#### Scenario: 多态证据绑定活代码

- **WHEN** 采集多态截图
- **THEN** 应由 e2e 状态往返断言驱动产生（QG-4 第 4 级副产物），而非独立手工产物；`state-coverage.json` 与 e2e spec 状态断言双管

#### Scenario: 元素存在不算证据

- **WHEN** 验证证据仅为「元素存在 / count>0」
- **THEN** 判定为无效原始证据（无法区分「可见」与「不可见」，无法捕获文本残留）

### Requirement: 禁止伪造手动 QA（修订 QG-5 自证范围）

系统 SHALL NOT 接受把「真机手动 QA」实现为自动化 spec（如 `qa-*.spec.ts`）；手动 QA 必须是**真用一遍 + 逐步观察 + 截图 + 结论**。系统 SHALL NOT 接受由同类探针自证「通过率」。

#### Scenario: 手动 QA 被脚本化

- **WHEN** 「手动 QA」以自动化 spec 形式存在并被计为验收通过
- **THEN** 判定为伪造手动 QA（名字即矛盾），不予采信

#### Scenario: 同类探针自证

- **WHEN** 报告「通过率」由与实现者同类的自动化探针自证（如「91% 通过」）
- **THEN** 判定自证无效

### Requirement: 收尾生命周期黑盒巡检

系统 SHALL 在 change 收尾（G4）前强制执行一次生命周期黑盒巡检：按六态清单真机走查 `打开→插入→编辑→切换→取消→关闭→空态→错误`，发现问题即**不允许收尾**。

#### Scenario: 巡检发现缺陷

- **WHEN** 收尾巡检发现任一生命周期缺陷
- **THEN** change 不得收尾（转缺陷处理机制，修复后重巡）

### Requirement: 发现闭环门（新增 QG-8）

系统 SHALL 要求任何报告 / findings / 实测发现中记录的缺陷，转成 tracked issue 或规格条目，否则该 change 不得标记完成。

#### Scenario: findings 未闭环

- **WHEN** findings 文件中存在未转 tracked issue / 规格条目的缺陷条目
- **THEN** 发现闭环门判定违规，change 不得完成（该缺陷将在下游复发）

### Requirement: 门禁减法审计兼容

系统 SHALL 为每条新增/修订门禁标注 expected capture（预期捕获场景），并纳入 `quality-gates.md §八` 季度审计；连续两周期零捕获的门禁提案合并/退役。

#### Scenario: 零捕获退役

- **WHEN** 某新/改门禁连续两个审计周期捕获数为 0
- **THEN** 提案合并或退役（留痕 + 数据）
