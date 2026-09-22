# docs/agents/ AGENTS.md

本文件只收 `docs/agents/` 目录特有知识；仓库通用约定见根 `../AGENTS.md`。

## OVERVIEW

本目录 9 份 `*.md` 是规范模板（不是本仓文档），安装到消费仓的 `<DOCS_DIR>`（默认 `docs/agents`）。
清单由 `../lib/render.sh:77-81` 的 glob 自动纳入 `cw_list_files`；受管文件共 13 个 = 4 硬编码 + 9 份 docs（`../lib/render.sh:71`）。
改本目录的文件名即改变消费仓的 `docs/agents` 布局。

## 9 份模板

| 文件 | 行数 | 主题 |
|---|---|---|
| `task-tracking.md` | 199 | OpenSpec tasks → GitHub issue 的发布与跟踪（1 task=1 ticket、Parent=spec issue、对账自证） |
| `quality-gates.md` | 362 | 票内容与完成判据的单一事实来源（QG-1..7 + DQ-1..8） |
| `issue-tracker.md` | 60 | 声明 GitHub Issues 为 tracker 及 `gh` 操作约定 |
| `project-board.md` | 88 | Projects V2 看板常量（PROJECT_ID/STATUS_FIELD_ID/OPT_*）与入列 API |
| `triage-labels.md` | 23 | 5 个 canonical triage 角色 → 本仓标签字符串的映射 |
| `defect-workflow.md` | 310 | 缺陷流程（`gh issue list` 唯一事实来源；废弃本地 bug-registry 缓存） |
| `domain.md` | 39 | 探索前领域文档消费规则（术语表、ADR 冲突必须显式声明） |
| `incident-uncommitted-work-loss.md` | 300 | 未提交代码被破坏性回滚覆盖的事故复盘 + 共享工作区保护 |
| `incident-merge-local-workspace.md` | 45 | 合并收尾切错分支致本地工作流失效的事故复盘与强制规则 |

## 模板硬规则

每份模板都受 4 条硬约束，**完整表述与理由见根 `../AGENTS.md`（CONVENTIONS / ANTI-PATTERNS）**，此处只记本目录相关的落点：

- 模板头（首行 `<!-- change-workflow 工具包模板`）与结尾换行：照抄任一份现有模板的这两处即可；CI 对应 `../.github/workflows/ci.yml` 的「模板头一致性」「受管模板以换行结尾」两步。
- 占位符登记表在 `../lib/render.sh:23-36`；禁仓库特有值的禁串清单与门禁项同见 `ci.yml` 的「无仓库特有值残留」步。
- 安装时剥头由 `cw_strip_header`（`../lib/render.sh:40`）完成；模板本身不带占位符残留才可通过 e2e 断言。

## 写作骨架

`quality-gates.md` 的每条规则固定四段：规则 / 理由 / 实证案例 / 如何验证（定义见 `../DESIGN.md:52`）。新条目照此结构写。

## 质量门禁索引

本目录最重要的一份是 `quality-gates.md`：

- QG-1..QG-7 在第二节，约 `:38-148`。
- DQ-1..DQ-8 在第三节，约 `:151-257`。
- 最小充分集（`:353` 附近）= QG-1+QG-2+QG-5（拦「功能不存在」）＋ DQ-1+DQ-3+DQ-5（拦「假修复」）。
- 豁免表在 `:319-341`：不可豁免 QG-3/4/5、DQ-1/2/3/4/5/8；可豁免的 QG-1/QG-2 必须由票作者显式声明，不得默认。
- 挂载点 `:349`：QG-7/QG-3 → G0；QG-1..QG-5 → G1 出口；QG-6 → G1 循环；DQ-1..8 → SKILL 缺陷处理章节。

## 改动清单

- 新增/删除一份模板：首行模板头与结尾换行必须满足（见上面硬规则）。
- `cw_list_files` 是 glob，新增模板无需改受管清单（`../lib/render.sh:77-81`）。
- 但要更新 e2e 模板头计数断言（`../test/install-update-e2e.sh:184-188` 期望 10）。
- 改任何一份模板：它同时是消费仓的受管文件；该文件若被消费仓本地改过（或 `manifest` 记 `LOCAL`），升级时不会覆盖，写 `<file>.new` 并退 1。
- 已知 `LOCAL` 哨兵：md-bundle 的 `change-closure-signal.yml`、`incident-merge-local-workspace.md`、`quality-gates.md`；clairis 的 `domain.md`、`issue-tracker.md`、`triage-labels.md`。
- 行为/规范变更：同步 `../VERSION` + `../CHANGELOG.md` 并发版。
