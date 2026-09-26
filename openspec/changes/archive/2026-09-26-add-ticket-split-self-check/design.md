## Context

**确认的来源（为何要退役它）**：拆票环节的人工确认来自外部 `to-tickets` skill 的 §4「Quiz the user」（原文：「Does the granularity feel right? (too coarse / too fine)」「Are the blocking edges correct」「Should any tickets be merged or split further」「Iterate until the user approves the breakdown」）。本仓把它写入了编排职责（`SKILL.md:140`「quiz 验收粒度…」、`:102`「含 quiz 用户确认」），但它与三处「唯一人工介入 = risk-medium/high PR 合并确认」声明（`SKILL.md:195` / `task-tracking.md:215` / `DESIGN.md:112`）自相矛盾——判定为继承性 holdover，而非本流程设计的 gate。

**粒度规则现状**：QG-7 纵向切片（`quality-gates.md:139-148`，不可豁免）是全仓唯一规范粒度源：「每条 task 必须贯穿 schema→API→UI→test 全层、独立可演示可验证；判据：一张票做完，用户能否看到点东西？」其「如何验证」为反向验收判据（一条 AC 若不修改 `<APP_DIR>` 即可被满足 → 切错）——是 7 条 QG 中唯一没有可执行命令的。`SKILL.md:133` 是唯一完整清单（贯穿全层 / 独立可演示 / 适配单 context window / prefactor 单独成条）。「过细」在全仓无操作化定义；`task-tracking.md:21`「每条约 1 commit」是唯一体量线索。

**执行面现状与教训**：全仓零票内容机检——`pr-automation.sh` 只读 `--json number,title`（3 处）从不读 body；CI 与 e2e 无票语义断言；对账自证是手写 `gh` 一行命令（`SKILL.md:151`）。反面先例：QG-2 文档写「push 前强制」但 `CMD_E2E` 无任何脚本读取（空心门禁）。

**硬约束**：bash 3.2（禁 `local -n`/`declare -A`/`mapfile`）；新增受管脚本需四联改动（`lib/render.sh:153` 受管清单 + e2e 计数/断言 + `ci.yml` 三处脚本清单）；工具包 `ci.yml` 只在工具包仓运行（消费仓侧检查若需 CI 须另发 workflow）；md-bundle 的 `quality-gates.md` 是 LOCAL 哨兵（改规则文本会触发 `.new` + 退 1）。

**可用先例**（不新造轮子）：`validate_whitelist()`（`pr-automation.sh:188-208`，枚举→比对→违规清单→退 1）；`run_gate()`（`:111-119`）；DQ-1 的 `gh`+`jq` 票面谓词（`quality-gates.md:163-168`，已写好但从未脚本化）；`change-closure-signal.yml:101-104` 在消费仓 CI 里按标题前缀计数子票。

## Goals / Non-Goals

**Goals:**
- 可机检判定的拆票失败模式（对账/字段/形态/结构/豁免/规模）在发布前拒收（C1-C8），主门设在 G0-POST（唯一还能改拆分的时机）
- quiz 三问全部被承接（机检 / 声明制 / 下游捕获），拆票环节零人工询问
- 不可机检的三项判断以声明制留痕、可审计（镜像 `quality-gates.md:341` 的豁免声明先例）
- 补齐 QG-7 的可执行验证（7 条 QG 中唯一的空缺）
- 全部新行为有 e2e 断言锁（先红后绿）；三处「唯一人工介入」声明复真

**Non-Goals:**
- 不修改外部 `to-tickets` skill（非受管 + 违背 `SKILL.md:272`「不复制其逻辑」不变量）
- 不动 QG-7 的不可豁免地位与豁免表（`quality-gates.md:319-341`）
- 不把检查放进 `pr-automation.sh`（G2 太晚）
- 不做消费仓 CI 兜底 workflow（本期非目标，待机制稳定后评估）
- 不引入强制独立复核步骤（消费仓 agent 未必有 subagent 能力，机制不得依赖）

## Decisions

**D1—机制落点 = G0-POST 发布前自检脚本。** 备选：`pr-automation.sh`（G2，拆分已发布不可逆，太晚）；纯 prose 指令（无执行，重蹈 QG-2 空心门禁）；消费仓 CI workflow（可作后续兜底，但主门必须能阻塞发布动作本身）。

**D2—quiz 的处置 = 编排层退役 + 外部 skill 不动。** quiz 三问的承接映射：

| Quiz 问句 | 承接机制 | 落点 |
|---|---|---|
| 粒度对不对（过粗/过细） | C3/C4/C8 机检 + 声明制 | 脚本 + tasks.md |
| Blocked by 对不对 | C5 结构机检 + 书面自答（语义） | 脚本 + spec issue 评论 |
| 要不要合并/再切 | C8 重叠检测 + C1 对账 | 脚本 |
| （隐含）每票交付什么 | C2 字段 + 书面自答 | 脚本 + spec issue 评论 |

外部 skill 的 quiz 文本在模型调用路径上被脚本输出替代；用户手动调用 `to-tickets` 时其 quiz 仍在（彼时用户本来在场，不冲突）。

**D3—粒度「过粗/过细」判据 = 声明制 + 重叠检测 + 角色豁免。** 备选：数值阈值（假精确、人为且脆弱）；全交判断（回到空洞）。完整定义：
- 每票必须声明其一：「用户可见交付物」或「expand–contract 序列角色（expand / migrate / contract / integrate-verify）」——角色豁免直接来自 `to-tickets` 的 wide refactor 例外条款，防止误伤合法宽重构；
- 票间 `What` 高度重叠 → 拒（过细/重复信号，阈值实施时定并用 e2e 固定）；
- 「适配单个 context window」上界维持定性，不假装有量化阈值；完整「经济性」判断（过细本质是管理成本 vs 反馈频率的权衡）交由声明制审计 + 下游捕获——这是本机制公开承认的能力边界。

**D4—独立性 = 证据纪律 + 可审计 + 下游兜底。** 自答有「自己批改作业」风险，对冲三件套：机检输出必须是原始输出（QG-5 先例）；三项自答落款 spec issue 评论（与对账锚点同源，可被 DQ-7 反查引用）；逃逸由既有下游捕获（G1 第 0.5 步拒开工 / 缺陷反查点名 QG-7 / DQ-7 强制修订）。不选强制独立复核的原因见 Non-Goals。

**D5—规范落点分布。** 行为契约 → spec delta；编排 → `SKILL.md:140`（协议替换）、`:102`（表格）、`:151`（对账改调脚本）；QG-7 可执行命令 → `quality-gates.md:147`（§四 `:271` 呼应）；粒度定义 → `task-tracking.md` §2；顺带修复 §4 模板漏「接线归属」「标签」两字段的既有漂移。

**D6—检查集明细（C1-C8，全部复用既有判据，不新造语义）：**

| 编号 | 检查 | 判据来源 | 违规动作 |
|---|---|---|---|
| C1 | 对账双射：子票数 == tasks.md 任务数；标题前缀编号一一对应 | `SKILL.md:151`（手写命令脚本化） | 拒收 |
| C2 | 六字段：Parent / What / AC / Blocked by / 接线归属 / 标签 | `task-tracking.md:29-35` | 拒收 |
| C3 | QG-1 形态：面向用户票 AC 命中 `打开.*页面\|dev server\|\.spec\.ts` | `quality-gates.md:50` | 拒收（豁免需 C6） |
| C4 | 禁入信号（任一即拒）：AC 全库层断言 / 新导出无接线归属 | `task-tracking.md:53-56` | 拒收 |
| C5 | Blocked by 结构：引用在集合内、无自环与环、存在拓扑序 | `SKILL.md:194` 的 frontier 前提 | 拒收 |
| C6 | 豁免显式：`no-ui-impact` 必须显式声明 | `quality-gates.md:341` | 拒收 |
| C7 | 规模钩子：票数 ≥6 须含 checkpoint 计划声明 | QG-6 | 拒收 |
| C8 | 粒度声明与重叠：逐票「用户可见交付物 / expand-contract 角色」；票间 `What` 重叠检测 | QG-7 + `to-tickets:40` wide refactor 例外 | 拒收 |

**D7—脚本接口。** `scripts/cw-tickets-check.sh`：退出码 0（全过）/ 1（有违规或用法错误）；逐项打印 verdict + 违规清单（照 `validate_whitelist()` 形态）；bash 3.2 兼容；参数从 `.change-workflow.conf` 读 label/目录约定。拒收后按 fix-first 自愈回路「就地重切（`/opsx-update` 修订 tasks.md）→ 重跑」，循环到过；升级仅保留 `SKILL.md:211` 既有三类。

## Risks / Trade-offs

- [自答空洞化（走过场）] → 证据纪律（原始输出）+ 落款可审计 + DQ-7 反查逼迫判据机械化。
- [C8 误报/漏报] → 角色豁免白名单 + 拒收可自愈重切（不问人）+ 逃逸触发判据修订；「过细」只拦明显形态（重复/无独立增量），完整判断显式留给审计与下游。
- [文档与执行脱节（QG-2 教训）] → 先红后绿：每项机检先有 e2e 断言（红）再有实现（绿）；禁止「写了强制但无脚本读」的措辞。
- [md-bundle LOCAL 冲突] → 升级时 `quality-gates.md` 出 `.new` + 退 1，一次性手动合并（预期内）；`rollout-check.sh` 预演三仓。
- [消费仓坏境差异] → 脚本只依赖既有栈（bash/gh/git/python3，G0-POST 本就需要 gh）；失败即列为拆票门违规（fail-closed 于发布动作）。

## Migration Plan

1. 实施（本仓）：e2e 断言先行（红）→ 实现脚本 → 注册受管面（`lib/render.sh:153` + e2e 计数 + `ci.yml` 三处清单）→ 规范文本改写 → e2e 转绿。
2. 发布：`VERSION` + `CHANGELOG.md`（新增/修复 → 教训反思 → 验证）→ tag → push。
3. 消费仓：`update.sh` 升级；md-bundle 手动合并 `quality-gates.md` 的 `.new`；三仓 `rollout-check.sh`（冲突 0 + LOCAL 哨兵完整 + 覆盖数一致）。
4. 回滚：脚本为独立新增、其余为模板文本改动——revert PR 或删脚本还原文档即可恢复原状；无数据迁移。

## Open Questions

- C8 重叠检测的阈值（词元/字符重叠比例）具体取值 → 实施时确定并用 e2e 断言固定。
- 消费仓侧可选 CI 兜底 workflow（对已发布子票做逾期巡检）是否值得做 → 本期 Non-Goal，待机制在三个消费仓跑顺后评估。