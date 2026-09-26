## ADDED Requirements

### Requirement: 发布前机检门禁
在 G0-POST 发布子票之前，编排层 MUST 运行拆票自检脚本 `scripts/cw-tickets-check.sh`；仅当全部检查通过（退出码 0）时才允许执行 `gh issue create`。

#### Scenario: 全部检查通过
- **WHEN** 对拟发布子票与 tasks.md 运行自检脚本且全部通过
- **THEN** 脚本退出码为 0，编排层直接发布子票，过程中不发起确认询问

#### Scenario: 存在违规项
- **WHEN** 任一检查项判定违规
- **THEN** 脚本退出码为 1 并逐项列出违规；编排层 MUST NOT 发布，须重切（修订 tasks.md）后重跑直至全过

### Requirement: 机检覆盖集（结构类）
自检脚本 MUST 至少实现以下结构性检查（判据全部复用仓库既有规范）：
- C1 对账双射：拟发子票数 == tasks.md 任务数；`[change=<名>/<task号>]` 标题前缀编号与 tasks.md 编号一一对应
- C2 六字段：每票含 Parent / What to build / Acceptance criteria / Blocked by / 接线归属 / 标签
- C5 Blocked by 结构：引用全部位于本 change 子票集合内、无自环与环、存在拓扑序
- C6 豁免显式：`no-ui-impact` 必须显式声明，不得默认
- C7 规模钩子：change 票数 ≥6 时须含集成 checkpoint 计划声明

#### Scenario: 计数或编号不齐
- **WHEN** 子票数量与 tasks.md 任务数不一致，或存在无法与任务编号对应的标题前缀
- **THEN** 检查项 C1 判违规，脚本列出缺失/多余的编号

#### Scenario: 票面字段缺失
- **WHEN** 某票缺少六个必备字段中的任一字段（如未写出「接线归属」）
- **THEN** 检查项 C2 判违规，脚本列出缺失字段与票号

#### Scenario: Blocked by 引用越界或成环
- **WHEN** 某票 Blocked by 引用了集合外不存在的票，或引用关系形成环
- **THEN** 检查项 C5 判违规，脚本列出涉及票号与环路径

### Requirement: 纵向切片可执行验证
自检脚本 MUST 以可执行方式落实 QG-7 的验证（补上 `quality-gates.md` 中 QG-7「如何验证」的命令空缺）：
- C3 QG-1 形态：面向用户票的 AC 命中浏览器可观测形态（`打开.*页面|dev server|\.spec\.ts`），除非票面显式 `no-ui-impact`
- C4 禁入信号（任一即拒）：AC 全部为库层断言 / 导出新 API 却无接线归属
- C8 粒度声明：每票声明「用户可见交付物」或「expand–contract 序列角色（expand / migrate / contract / integrate-verify）」；票间 `What` 高度重叠判为过细/重复信号

#### Scenario: 横向切片票被拒
- **WHEN** 某票 AC 全部为库层断言且未显式声明 `no-ui-impact`
- **THEN** 检查项 C3/C4 判违规，该票被拒收

#### Scenario: 合法宽重构获得角色豁免
- **WHEN** 某票声明为 expand–contract 序列角色（如 `expand` / `migrate` / `contract` / `integrate-verify`）
- **THEN** 该票不因「无用户可见交付物声明」被拒（例外来源：to-tickets 的 wide refactor 条款）

#### Scenario: 票间职责重复
- **WHEN** 两张子票的 `What to build` 达到重叠阈值
- **THEN** 检查项 C8 判违规，提示合并或重切

### Requirement: quiz 语义退役与自动发布
编排层 MUST NOT 在拆票环节向用户发起粒度确认询问；原 quiz 三问（粒度 / Blocked by / 合并或再切）MUST 由机检（C 检查集）与书面自答承接；全绿后 MUST 自动发布子票。

#### Scenario: 拆票阶段零人工询问
- **WHEN** 自检全部通过
- **THEN** 编排层直接进入发布流程，不出现「请确认粒度/阻塞边」类询问

#### Scenario: 升级通道收窄
- **WHEN** 出现的情形不属于「同一门禁连续 2 轮修复未通过 / 涉及人工权限或不可逆操作 / 规范冲突无法裁决」三类
- **THEN** 编排层 MUST 自行处置（重切或修复），不得升级用户

### Requirement: 不可机检判断的声明制留痕
三项不可机检判断（Blocked by 语义真伪 / `What` 与 spec 相符性 / 总票数匹配度）MUST 以书面自答落款至 spec issue 评论，且 MUST 引用证据（spec 原文或脚本原始输出）。

#### Scenario: 可追溯审计
- **WHEN** 后续对拆票质量发起反查（如多票同环节的流程反查）
- **THEN** 可从 spec issue 评论文本回溯当时的三项自答及其依据

### Requirement: 逃逸处置与规则演进
拆票错误逃逸（如横向切片进入实施）MUST 由下游捕获路径处置：G1 第 0.5 步拒开工 / 缺陷反查清单「是 QG-7 失效？」/ DQ-7（≥3 票同环节）；触发后 MUST 产出对 C 检查集或 QG-7 判据的规范修订并留痕。

#### Scenario: 多票指向拆票环节
- **WHEN** ≥3 张缺陷票指向拆票环节失效
- **THEN** 反查 MUST 产出检查集或 QG-7 判据的修订，且修订可回溯到触发它的缺陷集合