## Why

v1.9.0 把保真/生命周期门禁写进了**定义层**（`quality-gates.md` QG-1/4/5/8 的文字 + SKILL 指令），并显式声明非目标「不改 bash 脚本行为」。24 小时后被消费仓 md-bundle 证伪：其 `editor-fidelity` change **16/16 勾选、CI 全绿、已归档**，用户打开即见约 20 处与原型不符（图标无统一规范、分栏点不开、表格「+」错位、菜单不关、取消残留 `/`、编辑底色≠预览、色板/行距不符…）。取证显示：**10/11 票零证据产物**（#327–#336 无 `.artifacts`）、QG-5 证据写成「测试通过数 + 文字描述」（QG-5 自认无效的形式）、已有测试把实现的偏差写成预期（同义反复）、空断言两分支皆过。

根因一句话：**门禁有定义、无机器强制、靠自证**。在无人盯守的 agent 运行里，文字规则必然静默失效——这正是 pstack `principle-encode-lessons-in-structure` 的结论（教训要编码成 lint/脚本/元数据，不要写成文字）。本 change 补齐**机制层**：给**现有** QG/DQ 装机制（不新增门禁条目），并遵守两条硬约束——**不依赖人工兜底**、**规格双形态（人读文字 + 机读制品）**。

## What Changes

- **规格双形态 + 验收锚点（机制 A）**：规格同时产出**人读散文**（主产物：意图/理由/验收叙述）与**机读锚点**（`conformance.json`：具体值 + 来源 + 断言类型），二者**双向链接**；G0 机检「锚点完备性 / 无孤儿 / 可断言性 / 可生成性」，缺一拒收。把「规格明确性」从「让人读一遍」变为**机检**。
- **一致性制品 + CI 自动核验（机制 B）**：原型 = baseline（哈希锁、禁篡改）。G0 从原型结构化表**程序化生成** `conformance.json` + baseline 截图 + e2e 断言骨架；CI 跑三层自动核验——T1 确定量（计算样式/几何/图标名/文案精确断言）、T2 感知（像素/感知 diff + VLM 结构化判定）、T3 状态机（六态往返 + 无残留）。**全自动、无人**。
- **验证分离机制化**：判者 ≠ 写者，靠**跨模型自动复核**（非人）；`multimodal-looker` / `visual-qa` 作为自动化 gate 步骤。
- **现有门禁装机制（不新增条目）**：M0 规格锚点门（强化 QG-1 + L-1 需求输入门）、M0' 一致性制品门（落实 QG-1③/QG-4 + D-d 承诺）、M1 ui-surface 机械触发、M2 证据 manifest 双校验、M3 exit-3 收紧、M4' 自动感知核验（**替换**「人审复核包」）。**BREAKING（对消费仓）**：`evidence-check.yml` 为新增受管 CI 工作流，消费仓升级后需按本仓门禁命令配置生效。
- **§八 减法审计修正**：退役判据由「零捕获」改为**执行率 / 阻断数 / 下游归因缺陷数**三指标，避免退役「执行得最好」的门禁（合规率高 → 零阻断）；识别关键词门禁的高捕获零价值问题。
- **受管面 +1**：新增 `workflows/evidence-check.yml` 纳入 `cw_list_files`，受管文件 **22 → 23**。

## Capabilities

### New Capabilities

- `mechanized-quality-gates`: 门禁的机制化强制能力——规格双形态与验收锚点机检、一致性制品（原型 baseline）生成与哈希锁、CI 三层自动核验（确定量/感知/状态机）、跨模型验证分离、证据 manifest 机检与降级收紧，以及 §八 三指标退役判据。它把 v1.9.0 `fidelity-lifecycle-gates` 定义的门禁从「文字」变为「可机检机制」。

### Modified Capabilities

<!-- 无既有 main spec 变更：v1.9.0 的 `fidelity-lifecycle-gates` capability 尚未归档进 openspec/specs/，本 change 以新 capability 承载其机制化强制；`quality-gates.md` / `evidence-capture.md` / `SKILL.md` 是受管模板（非 openspec main spec），其改动记录在 Impact。 -->

## Impact

- **修改文件（受管模板，8 份）**：
  - `docs/agents/quality-gates.md`：QG-1/QG-4/QG-5 增机检条款；§八 改三指标；新增「双形态规格 / 验收锚点 / 一致性制品」定义段。
  - `docs/agents/evidence-capture.md`：增「一致性制品 + baseline + T1/T2/T3」约定；exit-3 收紧。
  - `docs/agents/task-tracking.md`：§3 增「验收锚点」字段。
  - `skills/change-workflow/SKILL.md`：G0 加锚点门 + 制品生成；G1/G2 加自动核验；G4 收尾校验。
  - `skills/change-workflow/agents-quick-reference.md`：速查卡同步。
  - `scripts/cw-tickets-check.sh`：C3/C4 由关键词 grep 改为锚点机检（**先红后绿**）。
  - `scripts/cw-evidence.sh`：增 `record-state`；exit-3 收紧。
  - `scripts/pr-automation.sh`：G2 出口接证据/manifest 校验。
- **新增受管文件（1 份）**：`workflows/evidence-check.yml`（CI 三层核验；与 `change-closure-signal.yml` 同款注入方式）→ **受管数 22 → 23**，连带改 `lib/render.sh` 的 `cw_list_files`。
- **测试与 CI**：`test/install-update-e2e.sh` 同步受管数（22→23）与模板头计数，新增锚点/制品/§八 契约锁（先红后绿）；`ci.yml` 脚本/受管清单相关步骤同步。
- **发版连带**：`VERSION` + `CHANGELOG.md` + `config.example.conf:12 TOOLKIT_VERSION` 三处同步。
- **消费仓影响**：md-bundle 的 `quality-gates.md` 是 manifest `LOCAL` 哨兵 → 升级写 `.new` + 退 1，须人工合并；新增 `evidence-check.yml` 为新增文件直接安装，需消费仓按自身 `CMD_*` 配置并启用分支保护；clairis / mdpkg 各自 LOCAL 哨兵同样处理。
- **依赖**：不新增运行时依赖（复用 Playwright/`npx` + `odiff`/`pixelmatch` + ffmpeg，均为消费仓测试环境可选件，缺失走 P5 降级）；bash 3.2 兼容不变。
