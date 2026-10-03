# 设计：保真 + 生命周期门禁加固

> 输入证据：`/Users/mason/ToHighs/md-bundle/docs/agents/cw-fidelity-lifecycle-gates-proposal.md`
> 评审：Oracle（架构）+ Momus（计划评审，结论 OKAY）

## 1. 上下文与约束

- CW 是**编排层**，不重实现 skill 逻辑；`docs/agents/*.md` 是**受管模板**（安装到消费仓），非 openspec main spec。
- 无编译、无运行时依赖；bash 3.2 兼容；降级友好。
- `quality-gates.md §八` 减法审计：门禁只增不减 → 必须压到最小充分集，并为新门标注 expected capture。
- `evidence-capture.md §四` 活代码优先：探针写成仓库 e2e，禁静态技能副本（`verify-md-bundle` 试点的三条撤销理由）。
- 既有既定决策：不引 before/after CLI / 上传链（CHANGELOG:263）。

## 2. 核心设计决策

### D1（合门）——学习层证据并入「需求输入门」

**决策**：不设独立 QG-8「学习层证据」；把「对标/学习证据」与「ideation 来源」合并为单一 **G0-PRE 需求输入门**，产物=「需求输入包」，五条契约统一约束。

**理由**：CW 编排图 `SKILL.md:73-79` 已把四类输入源当**同一漏斗**（→ to-spec）；拆两门=分裂同一漏斗、徒增门禁面，直接对抗 §八。
**被否决方案**：Oracle 倾向分门（per-concern 更精确强制）。**裁决：合门**——CW 的抽象层上，两者收敛为同一条规则「输入须有据、空白须显式」。

### D2——门禁架构压到 1 新 + 3 修订 + 1 契约门

| 提案 | 处置 |
|---|---|
| QG-1 三分类 | 修订（加强） |
| QG-4 阶梯 | 修订（具体化） |
| QG-5 视觉探针 + 禁伪 QA | 修订（加强 + 澄清） |
| QG-9 设计→规格保真 | 并入 QG-1 第③类「保真」 |
| QG-8 学习层证据 | 并入需求输入门（D1） |
| QG-10 发现闭环 | 保留为唯一新门，编号 **QG-8** |

**理由**：提案 4 新 + 3 修订 → 压成 1 新 + 3 修订，兼容 §八。

### D3——多态截图是「状态往返断言」的副产物（非人工清单）

**决策**：交互类票的 e2e **必须驱动六态**（`打开·切换·取消·外部点击·空态·关闭`，QG-4 第 4 级「状态往返」），每态断言 + 每态截图，并产出机读清单 `.artifacts/<task>/state-coverage.json`。

**理由**：单层截图之所以出现，正因为 e2e 只断言「元素存在」。把多态证据绑定到**活代码 e2e**（而非独立手工产物），既符合 `evidence-capture.md §四` 活代码优先，又使「是否多态」**可机检**（扫 spec 断言 + 扫清单态数）。

### D4——可执行性分层（避免 hollow checkbox）

| 门禁 | 机检方式 | 信号 |
|---|---|---|
| AC 三分类 | `gh issue view … \| grep -E "取消\|残留\|严格等于"` | 无输出=违规 |
| 断言阶梯 | `git diff … -- '*.spec.ts' \| grep -E "toHaveText\|textContent\|getComputedStyle"` | 无输出=违规 |
| 多态截图 | 机检 `state-coverage.json` 态数 + e2e spec 状态断言 | 态数 <4=违规 |
| 需求输入门 | `grep -c "来源:" input-package.md` + 未显式化空白扫描 | 不匹配=违规 |
| 发现闭环（QG-8） | findings 行数 vs issue 数 | 不匹配=违规 |
| 设计→规格保真 | ❌ 人工（review 并排设计稿 vs Scenario） | — |

**原则**：机检只查**存在性**（关键词/文件/清单/态数），**质量判断留 review**。

### D5——§八 兼容：expected capture 承诺

每个新/改门禁随变更标注 **expected capture**（预期捕获的缺陷场景），下一季度审计对账，连续零捕获即退役。

### D6——收尾层

- 禁伪造手动 QA：把「真机手动 QA」实现成 `*.spec.ts` 是反模式（名字即矛盾）；并入 QG-5「自证无效」。
- 收尾生命周期黑盒巡检：按六态清单走查，发现问题不得收尾（挂 G4 前置）。
- 发现闭环门（QG-8）：findings 每条缺陷须转 tracked issue 或 spec 条目。

## 3. 反例 → 门禁映射（元验收）

| 缺陷（提案 D#） | 现行 QG 能否拦 | 本变更 |
|---|---|---|
| D1 `.md` 落预览（实现违反规格） | ✗ | 规格保真③ / e2e |
| D2 callout「注释 注释」 | ✗ | QG-1③ 文本相等 / QG-4 第 3 级 |
| D3 围栏反引号 `\`js` | ✗ | 同上 |
| D4 菜单点外部不关 | ✗ | QG-1② 生命周期 / QG-4 第 4 级 |
| D5 空态菜单驻留 | ✗ | QG-1② 空态 |
| D6 取消残留 `/` | ✗ | QG-1② / QG-4 第 4 级 |
| D7 表格塌陷（实现弱化规格） | ✗ | QG-1③ 设计→规格保真 |
| D8 表格玩具占位 | ✗ | QG-1③ |
| D9 孤儿功能（无规格实现） | ✗ | 需求输入门⑤ 验收锚点 / QG-9 保真 |
| D10 React 重复 key | ✗ | QG-4 文本/console 断言 |

现状 **0/10**；本变更后目标 **≥8/10**。

## 4. 迁移与交付

1. 走本 openspec change → 实现 → `openspec archive` 进 `openspec/specs/`。
2. 发版（`VERSION` + `CHANGELOG.md` + `config.example.conf:12` 三处）→ tag → push。
3. 消费仓升级：md-bundle 的 `quality-gates.md` 是 `LOCAL` 哨兵 → 接受 `.new` → **人工合并**（按该仓上下文调整占位符/模块）→ `rollout-check.sh` 确认无残留；clairis / mdpkg 同理。

## 5. 风险

- **门禁膨胀**：已用 D2（1 新 + 3 修订）+ D5（捕获承诺）缓解；若下一季度零捕获即退役。
- **LOCAL 哨兵**：门禁变更无法自动送达提案方，须人工合并（这本身强制审查语义变更）。
- **多态机检的空转**：若 e2e 仅补 `state-coverage.json` 而不断言状态，机检仍可被绕过 → 故 D3 同时要求 e2e spec 含状态往返断言（双管）。
