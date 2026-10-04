## Context

- CW 是**编排层**：`docs/agents/*.md` 是**受管模板**（安装到消费仓），非 openspec main spec；`scripts/*.sh` 与 `workflows/*.yml` 同装到消费仓。
- 约束：无编译、无运行时依赖（bash + gh + git + python3）；bash 3.2 兼容；降级友好；受管面变更必须同步 `lib/render.sh` / `test/install-update-e2e.sh` / `ci.yml`。
- 输入证据：`md-bundle/docs/agents/cw-fidelity-verified-defects.md`（实测 20 偏差）+ 本次对话确定的方案 `.omo/plans/cw-mechanized-quality-gates.md`。
- 前序：v1.9.0 `cw-fidelity-lifecycle-gates`（定义层，未归档）建立了 QG-1/4/5/8 与需求输入门；本 change 是其**机制层**补齐。
- **两条硬约束（用户裁定）**：① **不依赖人工兜底**——质量靠机制与措施；② **规格双形态**——既有机读制品，也有能读懂的文字。
- **本地环境实测**：`node v22` / `npx` / `playwright` CLI / `~/Library/Caches/ms-playwright`（`chromium-1234`、`chromium_headless_shell-1234`、`ffmpeg-1011`）/ `ffmpeg` / `chrome-devtools-axi` / `bsk` 均具备 → 截图与录制路径可用。
- **§八**（`quality-gates.md` §八）减法审计：门禁只增不减 → 本 change **不新增门禁条目**，只给现有条目装机制。

## Goals / Non-Goals

**Goals:**

1. 把「期望的需求效果」在 G0 编码成**双形态规格**（人读散文 + 机读锚点，双向链接、可机检）。
2. 把门禁核验搬进**机制 + CI**，**无需人盯**；保真全自动核验（T1 确定量 / T2 感知 / T3 状态机）。
3. **不新增 QG/DQ 条目**，只给现有门禁装机制（兼容 §八）。
4. 修正 §八 退役判据（三指标），避免退役「执行得最好」的门禁。
5. 受管面 +1（`workflows/evidence-check.yml`），受管数 22 → 23。

**Non-Goals:**

- ✗ 不引入 npm CLI / GUI 录制 / 上传链（保持零新增运行时依赖；pstack / 软件工厂**工具不移植**，只借协议与原则）。
- ✗ 不把「人审 / PR 审批」作为质量兜底（硬约束 ①）。
- ✗ 不新增 QG/DQ **条目**（只装机制）。
- ✗ 不把主观美学做成硬门（T2 近似判定 + 阈值；承认边界，达不到即红，**不转人工**）。
- ✗ 不重实现 to-spec / openspec / to-tickets 逻辑（编排层定位不变）。

## Decisions

### D1 —— 规格双形态：人读主产物 + 机读投影，双向链接

**决策**：规格保留**人读层为主**（proposal/design/AC/Scenario 自然语言 + 理由），并新增**机读层**（`conformance.json` 锚点）；人读条目挂锚点引用、锚点回指人读 id；G0 机检四项（完备性 / 无孤儿 / 可断言性 / 可生成性）。
**理由**：纯机读丢意图、不可评审；纯散文不可核验（v1.9.0 的失败）。双形态 + 链接 = 可读 **且** 可核验。
**备选**：纯机读（否决——违背约束 ②）；纯散文（否决——不可强制）；「散文 + 关键词 grep」（C3/C4，已证无效）。

### D2 —— baseline 即 spec：程序化生成 + 哈希锁 + 禁篡改

**决策**：有原型时，G0 从原型结构化表（§2/§3/§4/§7）**程序化解析**出 `conformance.json` 与 baseline 截图，实现前锁哈希；实现阶段只消费。
**理由**：唯一能破「实现反填 baseline / 测试照实现写」的机制；借 pstack `visual-parity`「baseline 即 spec，禁改 baseline」。
**备选**：实现者手填锚点（否决——投毒源）；人工比对原型（否决——违背约束 ①）。

### D3 —— CI 三层自动核验（T1 确定量 / T2 感知 / T3 状态机）

**决策**：T1 用计算样式/DOM/文本精确断言；T2 用像素/感知 diff + 多模态结构化判定；T3 用六态往返。全部在 CI 跑，断言已提交。
**理由**：本次 20 偏差**全部可枚举**（图标名/几何/色值/状态迁移），非审美——T1/T3 精确、T2 兜感知。CI 执行在 agent 写权限之外。
**备选**：只做 T1（漏视觉）；只做 T2（误报高、无精确性）；人审截图（否决——约束 ①）。

### D4 —— 验证分离用跨模型（非人）

**决策**：判者 ≠ 写者，靠不同模型家族对同一 diff + 同一 baseline 独立判定（consensus）。
**理由**：单 agent 下「验证者 ≠ 实施者」是假命题；跨模型是可用且无需人工的冗余。借 pstack `shipping`「judge never the writer」+ `interrogate`/`arena`。
**备选**：人工审批（否决——约束 ①）；同模型自审（否决——共享盲区）。

### D5 —— 不新增门禁条目，只装机制

**决策**：机制映射到现有 QG/DQ（M0 强化 QG-1+L-1；M0' 落实 QG-1③/QG-4+D-d；M1 定适用范围；M2 强化 QG-5；M3 强化 QG-5/DQ-3/DQ-5；M4' 强化 QG-5 视觉探针）。
**理由**：兼容 §八；v1.9.0 已验证「缩减门禁面」的取向（提案 4 新压成 1 新）。
**备选**：新增 QG-9/10（否决——§八 反对门禁膨胀）。

### D6 —— `evidence-check.yml` 纳入受管清单（用户裁定）

**决策**：新增 `workflows/evidence-check.yml` 并加入 `cw_list_files`，受管数 22 → 23。
**理由**：CI 是「机制层有牙」的载体（执行在 agent 写权限之外）；与既有 `change-closure-signal.yml` 同款注入方式。用户明确「纳入管控单」。
**备选**：不入库、由消费仓自理（否决——用户裁定纳入；不纳入则无法统一升级下发）。

### D7 —— §八 改三指标

**决策**：退役判据由「捕获次数」改为「执行率 / 阻断数 / 下游归因缺陷数」。
**理由**：良好执行的机检门禁合规率高 → 零阻断，恰会被现行「零捕获即退役」退役（自我否定）。关键词门禁则高捕获零价值。
**备选**：保留单一捕获计数（否决——会退役成功的门禁）。

### D8 —— 全量交付（用户裁定）

**决策**：机制 A（双形态 + 锚点）+ 机制 B（制品 + CI 核验）+ §八 修正 + 受管面 +1，一次全量交付。
**理由**：用户明确「全量」；A/B 互为前提（锚点喂制品、制品喂核验）。
**备选**：最小先导（M0+M2）（否决——用户裁定全量）。

## Risks / Trade-offs

- **baseline 投毒（最大风险）** → ①程序化解析规格表（非手填）；②条目带 `source`（原型截图#/URL+时间戳）；③baseline 变更走**独立模型复核 + 哈希锁**。
- **T2 感知容差误报** → 容差阈值可配；对精确量走 T1（零误报）；T2 仅兜「视觉/布局」。
- **多模态模型判定可能错** → 跨模型投票降误判（机制内冗余）。
- **受管面 +1 的连带破碎** → `cw_list_files` / e2e 计数断言（22→23）/ 模板头计数 / `ci.yml` 三处同步；先红后绿锁定。
- **消费仓 LOCAL 哨兵** → md-bundle 的 `quality-gates.md` 是 `LOCAL`，升级只写 `.new` + 退 1，须人工合并（这本身强制审查语义变更）。
- **生成器与 schema 复杂度** → 锚点/manifest schema 先冻结到最小必要字段；主 spec sync 时再定稿。
- **CI 成本** → T2 感知核验较贵；仅对 ui-surface 票触发，非全量。

## Migration Plan

1. 实现 → 全 CI 门禁本地复现 → 发版（`VERSION` + `CHANGELOG.md` + `config.example.conf:12` 三处）→ tag → push。
2. 消费仓升级：`update.sh` → md-bundle 接受 `quality-gates.md.new` → **人工合并**（按其占位符/模块调整）；`evidence-check.yml` 为新增文件直接安装，按各仓 `CMD_*` 配置并设分支保护 required check。
3. `test/rollout-check.sh` 确认冲突 0、LOCAL 哨兵完整、覆盖数一致。
4. 回滚：revert 合并提交即可；新工作流可先在非 required 模式观察。
5. 主 spec：本 change 归档后，`fidelity-lifecycle-gates`（v1.9.0，未归档）与本 capability 的关系在归档时裁定（见 Open Questions）。

## Open Questions

1. 锚点 / manifest 的最终 schema（字段最小集）——实现阶段冻结。
2. `fidelity-lifecycle-gates`（v1.9.0 未归档）与本 `mechanized-quality-gates` 归档时是否合并为一个 main spec，还是本 capability 显式「依赖 / 取代」它。
3. T2 感知容差的默认阈值与配置键名。
4. `evidence-check.yml` 触发条件（仅 ui-surface 票如何被 CI 识别：label 事件 / path filter）。

## Implementation Contract（冻结 2026-10-04，实施阶段不得偏离）

### IC-1 `conformance.json`（机读锚点层）

位置：`openspec/changes/<change>/conformance.json`（无 openspec 的消费仓：`docs/requirements/<change>/conformance.json`）。

```json
{
  "change": "<name>",
  "requirements": [
    {"id": "R-<n>", "text": "<人读验收叙述>", "anchors": [
      {"id": "A-<n>.<m>", "claim": "<可判真伪一句>",
       "kind": "exact | state-machine | perceptual",
       "assert": "<可执行断言描述，须含具体值>",
       "source": "<原型§/截图#/决策#/一手观察>"}
    ]}
  ]
}
```

G0 机检（`cw-tickets-check.sh` C3/C4 扩展）：**完备性**（每 requirement ≥1 anchor）、**无孤儿**（anchor 回指存在 requirement）、**可断言性**（assert 非空且含具体值 token：`[0-9]` 或引号串或 `#hex` 或状态迁移关键词）、**来源非空**。

### IC-2 证据 manifest（`state-coverage.json`）

复用 `evidence-capture.md` §3.2 结构；ui-surface 票必产出，≥4 态，每态 `{state, screenshot, assertion ∈ passed|failed|untested}`。位置 `.artifacts/<票号>/state-coverage.json`。

### IC-3 `cw-evidence.sh record-state`

`record-state <artifact-dir> --state <name> --screenshot <file> --assertion passed|failed|untested`：创建/合并 `<artifact-dir>/state-coverage.json`（python3 做 JSON 合并；python3 缺失退 3）。其余子命令与退出码契约（0/1/3）不变。

### IC-4 `evidence-check.yml`

- 触发：`pull_request`（default branch）；`permissions: contents: read, pull-requests: read`。
- 步骤：checkout（sparse `.change-workflow.conf`）→ 按 `change-closure-signal.yml` 的 `cw_conf_label` 模式读 conf（禁 source）→ ui-surface 判定 → 结构性校验（ui-surface 票须有提交的 `state-coverage.json` 且 ≥4 态；spec diff 含断言强度标记）→ 若 conf 配 `CMD_FIDELITY` 则运行三层核验命令。
- 降级：工具/命令缺失 → 打印降级说明、跑结构校验、**不改变判据**；非 UI 票直接通过。
- 禁仓库特有值；`run:` 块内 bash 3.2 兼容。

### IC-5 ui-surface 触发

「label ∪ diff 路径」析取。label 名从 conf `LABEL_UI_SURFACE`（默认 `ui-surface`）；路径 glob/正则从 conf `UI_PATH_GLOB`（默认 UI 组件/CSS 路径）。任一命中即 ui-surface。

### IC-6 受管数 22 → 23

`lib/render.sh` 的 `cw_list_files` 在 `change-closure-signal.yml` 后新增：
`echo "workflows/evidence-check.yml|.github/workflows/evidence-check.yml"`。
e2e 断言 `22` → `23`：用例 1 manifest 行数（`:97`）、`已最新 22`（`:107`）、缺失+LOCAL 五桶和（`:362`/`:376`）、干净仓受管文件数（`:490`）、`已最新 22`（`:706`）。**模板头计数 `13` 不变**（新文件非 `.md` 模板）。

### IC-7 e2e 契约锁（先红后绿）

新增：`quality-gates.md` 含「双形态」「验收锚点」「执行率」「阻断数」；`cw-tickets-check.sh` 缺锚点 → 违规；`cw-evidence.sh` exit-3 需 reason；`lib/render.sh` 清单含 `evidence-check.yml` 且计数 23。
