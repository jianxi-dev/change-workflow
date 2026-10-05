## 1. 生成器脚本（受管）

- [x] 1.1 `scripts/cw-conformance.sh`：新增四子命令（scaffold/generate/lock/verify）+ 退出码 0/1/3 契约 + 内嵌 python3 解析/校验/锁/验证
- [x] 1.2 `bash -n` + `shellcheck --severity=warning` 通过；无 bash 4+ 特性
- [x] 1.3 `lib/render.sh` 的 `cw_list_files` 追加 `scripts/cw-conformance.sh|scripts/cw-conformance.sh`（受管数 **23→24**）

## 2. openspec change 自举制品

- [x] 2.1 `openspec/changes/cw-conformance-generator/.openspec.yaml`（schema + created）
- [x] 2.2 `openspec/changes/cw-conformance-generator/proposal.md`（Why/What Changes/Capabilities/Impact）
- [x] 2.3 `openspec/changes/cw-conformance-generator/design.md`（Context/Goals/Decisions/Risks/Migration/IC）
- [x] 2.4 `openspec/changes/cw-conformance-generator/tasks.md`（本清单）
- [x] 2.5 `openspec/changes/cw-conformance-generator/specs/conformance-generator/spec.md`（capability 定义）
- [x] 2.6 `openspec/changes/cw-conformance-generator/anchors.md`（人写源，含 R-1 与 A-1.1/A-1.2）
- [x] 2.7 用生成器产出 `conformance.json` + `conformance.lock` 并 `verify` 全绿（自举 dogfood）

## 3. 受管模板/文档同步（6 份）

- [x] 3.1 `scripts/AGENTS.md`：新增 `### cw-conformance.sh` 节（职责/子命令/退出码 0|1|3/契约锁用例号）
- [x] 3.2 `skills/change-workflow/SKILL.md`：G0 段补生成器调用（有/无原型分支均先 `generate` → `lock`，实现前锁哈希）；G0-POST 校验行补 `verify`
- [x] 3.3 `skills/change-workflow/agents-quick-reference.md`：速查卡 G0/门禁处加一行 conformance 生成器
- [x] 3.4 `docs/agents/evidence-capture.md` §八：把「生成方式」列由约定改为 `scripts/cw-conformance.sh generate`
- [x] 3.5 `docs/agents/quality-gates.md`：QG-1「如何验证」补 `scripts/cw-conformance.sh {generate|verify}`

## 4. e2e 契约锁（先红后绿，DQ-3）

- [x] 4.1 受管数断言 23→24（含 `cw_list_files` 输出、manifest 行数、模板头计数如受影响）
- [x] 4.2 新增用例 `[36] cw-conformance.sh 一致性制品生成器契约锁`（6 条核心断言：scaffold/generate/lock/verify/幂等/降级）
- [x] 4.3 先跑红相（断言在改模板/脚本前失败）→ 改到绿相
- [x] 4.4 `./test/install-update-e2e.sh` 全绿（输出贴入 CHANGELOG）

## 5. 静态门禁 + 版本

- [x] 5.1 `for s in setup.sh update.sh lib/render.sh scripts/*.sh test/*.sh; do bash -n "$s"; done` 通过
- [x] 5.2 `shellcheck --severity=warning -x` 通过
- [x] 5.3 bash 3.2 静态拦截（无 `local -n` / `declare -A` / `mapfile` / `readarray`）通过
- [x] 5.4 占位符 / 模板头 / 结尾换行 / 特有价值残留 CI 步全绿
- [ ] 5.5 `VERSION` + `CHANGELOG.md`（`### 新增/修复` → `### 教训反思` → `### 验证`）+ `config.example.conf:12` 三处同步
- [ ] 5.6 `git tag` + push

## 6. 消费仓迁移

- [ ] 6.1 `./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis` 确认无冲突、LOCAL 哨兵完整、覆盖数一致
- [ ] 6.2 md-bundle：`update.sh` → 接受 `quality-gates.md.new` / `evidence-capture.md.new` 等 → **人工合并** → 重跑 rollout-check
- [ ] 6.3 clairis / mdpkg 各自 LOCAL 哨兵人工合并

## 7. 元验收

- [x] 7.1 自举验证：本 change 自己的 `anchors.md` → `generate` → `lock` → `verify` 全绿
- [x] 7.2 `openspec validate cw-conformance-generator --strict` valid