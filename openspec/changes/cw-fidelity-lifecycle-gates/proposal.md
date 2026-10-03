## Why

现有 QG-1..7 / DQ-1..8 能拦「功能**没接上**」（editor-v2：12 票全绿、用户看不到变化），但拦不住「功能**接上了、体验烂**」。

实证（md-bundle `editor-doubao-parity` + v2，提案 `cw-fidelity-lifecycle-gates-proposal.md`）：交付 **29/29 勾选、CI 全绿、QG 全过**，用户实测仍见 D1–D10——callout 标题重复「注释 注释」、代码围栏残留反引号、斜杠菜单点外部不关、取消后 `/` 残留、表格点一下塌成裸源码、空态无「新建文档」入口、React 重复 key。

根因在链条四层：**L-1 学习/需求输入无证据、L0 设计→规格翻译损耗、L3 断言停在「元素存在」、L4 验收用存在性自证**。现有每条 QG 最终都在问同一句话——「DOM 里有这个节点吗？」。注释：同一条链的第四次复发，症状换壳。

## What Changes

对四层各补一个**可核验契约**（不新增受管文件、不改 bash 脚本行为；唯一脚本改动是 `cw-tickets-check.sh` 的 C3/C4 机检同步）：

1. **L-1 需求输入门**（新增，挂 G0-PRE）：任何以「对标/学习/补齐能力」为由的 change，其需求输入包须满足五条契约——来源可追溯 / 空白显式化（`open-question` 阻断引用它的规格条目）/ 一手证据 / 冲突显式 / 验收锚点。**合并原提案 QG-8（学习层证据）**——CW 编排图已把四类输入源（grill-me / office-hours / wayfinder / 手工）视为同一漏斗。
2. **L0 规格层**（修订 QG-1）：用户可见票 AC 升级为**三分类**——存在 / 生命周期（`打开·切换·取消·外部点击·空态·关闭`，断言取消后无残留）/ 保真（可判真伪的文本/像素）。C3/C4 机检同步。
3. **L3 验证层**（修订 QG-4、QG-5）：QG-4 增「断言强度阶梯」（存在→可见→文本相等→状态往返→视觉），渲染/浮层类 ≥ 文本相等、可取消类 ≥ 状态往返；QG-5 增**视觉探针** + **多态截图规格**（状态覆盖矩阵 ≥4 态 + `state-coverage.json`），明确「元素存在 / count>0」不是有效证据、单层截图对交互票不足。
4. **L4 验收/闭环**（新增 QG-8 + 收尾条款）：禁止把「真机手动 QA」实现成 `*.spec.ts`；收尾强制生命周期黑盒巡检；新增**发现闭环门**——findings 每条缺陷须转 tracked issue 或 spec 条目。

**门禁架构压缩**：提案原为 4 新 + 3 修订；本变更压成 **1 新 + 3 修订 + 1 契约门**（学习层证据并入需求输入门、设计→规格保真并入 QG-1 第③类），以兼容 `quality-gates.md` §八减法审计的「门禁只增不减」约束。

## Capabilities

### New Capabilities
- `fidelity-lifecycle-gates`: 从「存在性验收」升级到「保真 + 生命周期验收」的四层契约——需求输入门、AC 三分类、断言强度阶梯、视觉探针与多态截图、发现闭环门、禁伪手动 QA 与收尾巡检。

### Modified Capabilities
<!-- 无既有 main spec 变更：本变更以新 capability 承载新行为契约；`quality-gates.md` / `evidence-capture.md` / `SKILL.md` 是受管模板（非 openspec main spec），其改动记录在 Impact。 -->

## Impact

- **修改文件**（5 份受管模板，受管文件数 22 不变）：
  - `docs/agents/quality-gates.md`：修订 QG-1 / QG-4 / QG-5；新增 QG-8；§四 AC 格式替换；§五 补正反例；§七 收紧 `no-ui-impact`（浮层/插入/渲染类不得豁免生命周期与保真 AC）；§八 加 expected capture 承诺
  - `docs/agents/evidence-capture.md`：§3.2 追加「状态覆盖矩阵」+ `state-coverage.json` 约定；§三 增「视觉探针」
  - `skills/change-workflow/SKILL.md`：G0-PRE 加需求输入门；G1 出口 QG-5 同步多态截图；G4 加收尾生命周期黑盒巡检
  - `docs/agents/task-tracking.md`：QG 范围引用 QG-1..QG-7 → QG-1..QG-8
  - `skills/change-workflow/agents-quick-reference.md`：速查卡 QG 索引补 QG-8、QG-1/4/5 更新、G0 加需求输入门、G4 加巡检+QG-8
- **修改脚本**（唯一）：`scripts/cw-tickets-check.sh` C3/C4 机检同步三分类 AC 形态
- **并发维护**：`docs/agents/AGENTS.md`（知识库，非受管）同步 QG 范围/证据类数
- **测试**：`test/install-update-e2e.sh` 新增用例 30–34（含用例 34 跨文件引用一致性契约锁；模板头计数仍 13）
- **无需改**：`lib/render.sh`（受管清单不变）、`ci.yml`（脚本 glob 自动纳入）
- **发版连带**：`VERSION` + `CHANGELOG.md` + `config.example.conf:12 TOOLKIT_VERSION` 三处同步
- **消费仓影响**：md-bundle 的 `quality-gates.md` 是 manifest `LOCAL` 哨兵 → 升级**不覆盖**、写 `.new` + 退 1，须**人工合并**；clairis / mdpkg 各自的局部 LOCAL 哨兵同样处理
