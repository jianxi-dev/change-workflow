## Why

v1.10.0 交付了「机制化门禁」——锚点机检、一致性制品约定、CI 三层核验、证据 manifest、§八 三指标退役判据，受管面 +1（`evidence-check.yml`），受管数 22→23。但「一致性制品」的生成仍停留在**约定层**（`evidence-capture.md` §八 规则）：G0 应从原型结构化表**程序化生成** `conformance.json` + `baseline/*.png` + e2e 断言骨架并**锁定哈希**，实现阶段只消费、禁篡改。缺生成器 → 实现者仍可手填/反填制品 → 投毒源未堵。

本 change 补齐**生成器**（`scripts/cw-conformance.sh`），把「规格双形态」的机读层从「约定」变为「可机检机制」：
- `scaffold`：生成 `anchors.md` 骨架（人写一次、任意 markdown 查看器可读）
- `generate`：解析 `anchors.md`→四规则校验（完备/无孤儿/可断言/来源非空）→原子写 `conformance.json`
- `lock`：对 `conformance.json` + `baseline/*.png` 逐文件 sha256 → 写 `conformance.lock`（哈希锁）
- `verify`：①重投影 `anchors.md` 与 `conformance.json` 语义比对→漂移退 1；②lock 缺失→退 3；③重算哈希，篡改/缺失/多出→退 1 逐文件列出
- 退出码 0/1/3 对齐 `cw-evidence.sh`：内容错→1（fail-closed），环境缺→3（降级，调用方决定）

**自举 dogfood**：本 change 自己的 `anchors.md` → `generate` → `lock` → `verify` 全绿，作为「生成器生成自身制品」的回归锁。

## What Changes

- **新增受管脚本（1 份）**：`scripts/cw-conformance.sh`（~534 行，bash 3.2 + 内嵌 python3）→ 纳入 `lib/render.sh:cw_list_files`，受管数 **23→24**
- **新增 openspec change（自举）**：`openspec/changes/cw-conformance-generator/` 含 `.openspec.yaml` / `proposal.md` / `design.md` / `tasks.md` / `specs/conformance-generator/spec.md` / `anchors.md` / `conformance.json` / `conformance.lock`
- **改动受管模板/文档（6 份）**：
  - `lib/render.sh`：`cw_list_files` 追加 `scripts/cw-conformance.sh`
  - `scripts/AGENTS.md`：新增 `### cw-conformance.sh` 节（职责/子命令/退出码/契约锁用例号）
  - `skills/change-workflow/SKILL.md`：G0 段补生成器调用（有/无原型分支均先 `generate` → `lock`，实现前锁哈希）；G0-POST 校验行补 `verify`
  - `skills/change-workflow/agents-quick-reference.md`：速查卡 G0/门禁处加一行 conformance 生成器
  - `docs/agents/evidence-capture.md` §八：把「生成方式」列由约定改为 `scripts/cw-conformance.sh generate`
  - `docs/agents/quality-gates.md`：QG-1「如何验证」补 `scripts/cw-conformance.sh {generate|verify}`
- **测试与 CI**：`test/install-update-e2e.sh` 受管数断言 23→24，新增用例 `[36] cw-conformance.sh 一致性制品生成器契约锁`（6 条核心断言：scaffold/generate/lock/verify/幂等/降级），**先红后绿**；`bash -n` / `shellcheck` / `openspec validate --strict` 全绿

## Capabilities

### New Capabilities

- `conformance-generator`：一致性制品生成器能力——从人读 `anchors.md` 程序化生成机读 `conformance.json` + 哈希锁 `conformance.lock`，四规则机检（完备/无孤儿/可断言/来源非空），verify 语义比对 + 哈希核验，退出码 0/1/3 契约。它把 v1.10.0 `mechanized-quality-gates` 约定的「一致性制品生成」从「文字」变为「可机检机制」。

### Modified Capabilities

<!-- 无既有 main spec 变更：本 change 以新 capability 承载生成器机制；受管模板改动记录在 Impact。 -->

## Impact

- **修改文件（受管模板/脚本，7 份）**：
  - `lib/render.sh`：`cw_list_files` 追加 `scripts/cw-conformance.sh|scripts/cw-conformance.sh`
  - `scripts/AGENTS.md`：新增 `### cw-conformance.sh` 节
  - `scripts/cw-conformance.sh`：新增（受管脚本）
  - `skills/change-workflow/SKILL.md`：G0/G0-POST 补生成器调用与 verify
  - `skills/change-workflow/agents-quick-reference.md`：速查卡同步
  - `docs/agents/evidence-capture.md` §八：生成方式指向脚本
  - `docs/agents/quality-gates.md` QG-1：如何验证补脚本调用
- **新增受管文件（1 份）**：`scripts/cw-conformance.sh` → **受管数 23→24**，连带改 `lib/render.sh` 的 `cw_list_files`
- **新增 openspec change 制品（自举）**：`openspec/changes/cw-conformance-generator/{anchors.md,conformance.json,conformance.lock}`
- **测试与 CI**：`test/install-update-e2e.sh` 同步受管数（23→24）与模板头计数，新增契约锁用例 36（先红后绿）；`ci.yml` 脚本/受管清单相关步骤同步（glob 自动纳入）
- **发版连带**：`VERSION` + `CHANGELOG.md` + `config.example.conf:12 TOOLKIT_VERSION` 三处同步
- **消费仓影响**：新增 `cw-conformance.sh` 为新增文件直接安装；现有 `quality-gates.md` / `evidence-capture.md` 等若被消费仓本地改过（或 `manifest` 记 `LOCAL`），升级时写 `.new` + 退 1，须人工合并
- **依赖**：不新增运行时依赖（仅 python3/shasum，均为工具包声明依赖）；bash 3.2 兼容不变