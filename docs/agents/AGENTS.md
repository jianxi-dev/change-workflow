# docs/agents/ AGENTS.md

本文件只收 `docs/agents/` 目录特有知识；仓库通用约定见根 `../AGENTS.md`。

## OVERVIEW

本目录 17 份 `*.md` 是规范模板（不是本仓文档），安装到消费仓的 `<DOCS_DIR>`（默认 `docs/agents`）。
清单由 `../lib/render.sh` 的 glob 自动纳入 `cw_list_files`（该 glob 跳过 `AGENTS.md` 自身）；受管文件共 36 个 = 17 份 docs + 19 个其余（2 skill、14 脚本、2 workflow、Makefile）。
改本目录的文件名即改变消费仓的 `docs/agents` 布局。

## 17 份模板

| 文件 | 行数 | 主题 |
|---|---|---|
| `task-tracking.md` | 226 | OpenSpec tasks → GitHub issue 的发布与跟踪（1 task=1 ticket、Parent=spec issue、对账自证） |
| `quality-gates.md` | 670 | 票内容与完成判据的单一事实来源（QG-1..10 + DQ-1..9，含 QG-10 断言审计/反事实复跑、DQ-9 真机偏差验收分级） |
| `issue-tracker.md` | 53 | 声明 GitHub Issues 为 tracker 及 `gh` 操作约定 |
| `project-board.md` | 88 | Projects V2 看板常量（PROJECT_ID/STATUS_FIELD_ID/OPT_*）与入列 API |
| `triage-labels.md` | 23 | 5 个 canonical triage 角色 → 本仓标签字符串的映射 |
| `defect-workflow.md` | 356 | 缺陷流程（`gh issue list` 唯一事实来源；含非功能视觉缺陷建票规则与 C10 数据面缺陷线应用） |
| `domain.md` | 40 | 探索前领域文档消费规则（术语表、ADR 冲突必须显式声明） |
| `incident-uncommitted-work-loss.md` | 301 | 未提交代码被破坏性回滚覆盖的事故复盘 + 共享工作区保护 |
| `incident-merge-local-workspace.md` | 45 | 合并收尾切错分支致本地工作流失效的事故复盘与强制规则 |
| `evidence-capture.md` | 330 | 证据驱动测试规范（证据分层 before/after + 7 类证据：运行时态/视频/截图/测量数字/transcript/headless 降级/视觉探针；挂 QG-5/DQ-3/DQ-5） |
| `code-structure.md` | 95 | 服务层架构约束（actions 管 why/when、service 管 how + 四反模式 + 迁移清单；挂 G1 与 code-review Standards 轴） |
| `pr-writing.md` | 186 | PR 与提交文字规范（去 AI 味：12 条 AI tells + 两遍扫描法 + add soul + Evidence/Merge Danger；挂 G2/G3/G4） |
| `data-surface.md` | 175 | 数据面（可配置面）落点契约：触发信号 + 六栏表 + 票面第 8 字段 + 缺陷线应用；机检 `scripts/cw-data-surface.sh`（C10） |
| `ui-feedback.md` | 52 | 感受性反馈 → 可核验视觉变更的四要素（位置/对象/偏差/对标）+ 执行者规则 |
| `ui-test-matrix.md` | 118 | 交互面状态矩阵：每个 UI 元素必须覆盖的状态清单（防「只测实现者想到的那一个状态」） |
| `incident-change-close-gates.md` | 133 | 收口事故复盘：锚点可断言性口径与 `.artifacts` 证据污染两道陷阱 |

## 模板硬规则

每份模板都受 4 条硬约束，**完整表述与理由见根 `../AGENTS.md`（CONVENTIONS / ANTI-PATTERNS）**，此处只记本目录相关的落点：

- 模板头（首行 `<!-- change-workflow 工具包模板`）与结尾换行：照抄任一份现有模板的这两处即可；CI 对应 `../.github/workflows/ci.yml` 的「模板头一致性」「受管模板以换行结尾」两步。
- 占位符登记表在 `../lib/render.sh:29-46`；禁仓库特有值的禁串清单与门禁项同见 `ci.yml` 的「无仓库特有值残留」步。
- 安装时剥头由 `cw_strip_header`（`../lib/render.sh:50`）完成；模板本身不带占位符残留才可通过 e2e 断言。

## 写作骨架

`quality-gates.md` 的每条规则固定四段：规则 / 理由 / 实证案例 / 如何验证（定义见 `../DESIGN.md:52`）。新条目照此结构写。

## 质量门禁索引

本目录最重要的一份是 `quality-gates.md`：

- QG-1..QG-10 在第二节，约 `:38-291`。
- DQ-1..DQ-9 在第三节，约 `:293-466`。
- 最小充分集（`:635` 附近）= QG-1+QG-2+QG-5（拦「功能不存在」）＋ DQ-1+DQ-3+DQ-5（拦「假修复」）。
- 豁免表在 `§七`（约 `:572-604`）：不可豁免 QG-3/4/5/9、DQ-1/2/3/4/5/8；可豁免的 QG-1/QG-2 必须由票作者显式声明，不得默认；DQ-9 未命中触发信号时自然不适用。
- 挂载点（`§九`）：QG-7/QG-3 → G0 拆票；QG-1..QG-5 → G1 出口；QG-6 → G1 循环；QG-8 → G4 收尾前置；QG-9 → G0-POST 票面（C4(d)）；QG-10 → G1 出口（断言审查）；DQ-1..9 → SKILL 缺陷处理章节。
- 减法审计在 §八（约 `:522` 起）：季度捕获统计表 + 零捕获合并/退役；最小充分集免退役。

新增 4 份规范与门禁的挂接：

- `data-surface.md`：数据面（配置/主题/图标/菜单/开关）落点六栏契约 + 票面第 8 字段——机检 `scripts/cw-data-surface.sh`（C10），挂 G0 阶段二 / G0-POST / G1 出口与缺陷线 `pr` 子命令。
- `ui-feedback.md`：感受性反馈 → 可核验视觉变更的四要素——与 `defect-workflow.md`「非功能视觉缺陷（视觉偏差票）」配套。
- `ui-test-matrix.md`：交互面状态矩阵（每个 UI 元素必须覆盖的状态清单）——QG-4/QG-10 判定面的输入。
- `incident-change-close-gates.md`：收口两道陷阱（锚点可断言性口径 / `.artifacts` 证据污染）——G2 收口与 cw-conformance 的取证纪律。

- `evidence-capture.md`：证据分层与 7 类证据（运行时态/视频/截图/测量数字/transcript/headless 降级/视觉探针）——QG-5（独立验证+原始证据）与 DQ-3（先红后绿）/DQ-5（关闭附原始证据）的取证细则。UI 票 QG-5 证据至少含一项运行时证据。
- `code-structure.md`：服务层架构约束（actions 管 why/when、service 管 how）——G1 出口的 code-review Standards 轴判据。
- `pr-writing.md`：PR 与提交文字规范（12 条 AI tells + 两遍扫描法）——G2/G3/G4 的文字质量判据。

## 改动清单

- 新增/删除一份模板：首行模板头与结尾换行必须满足（见上面硬规则）。
- `cw_list_files` 是 glob，新增模板无需改受管清单（`../lib/render.sh:162-168`）。
- 但要更新 e2e 模板头计数断言（`../test/install-update-e2e.sh:220` 期望 13）。
- 改任何一份模板：它同时是消费仓的受管文件；该文件若被消费仓本地改过（或 `manifest` 记 `LOCAL`），升级时不会覆盖，写 `<file>.new` 并退 1。
- 已知 `LOCAL` 哨兵：md-bundle 的 `change-closure-signal.yml`、`incident-merge-local-workspace.md`、`quality-gates.md`；clairis 的 `domain.md`、`issue-tracker.md`、`triage-labels.md`。
- 行为/规范变更：同步 `../VERSION` + `../CHANGELOG.md` 并发版。
