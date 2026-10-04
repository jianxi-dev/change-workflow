## 1. 门禁规范（受管模板）

- [x] 1.1 `quality-gates.md`：新增「规格双形态 + 验收锚点」定义段（人读主产物 + 机读锚点 + 双向链接；四项机检：完备性 / 无孤儿 / 可断言性 / 可生成性；明确「人读层不可丢」）
- [x] 1.2 `quality-gates.md`：QG-1 增验收锚点要求（每条 AC 携带锚点；无具体值/来源不得成锚点）
- [x] 1.3 `quality-gates.md`：QG-4/QG-5 增「CI 三层自动核验」（T1 确定量 / T2 感知 / T3 状态机）与「跨模型验证分离（非人）」条款
- [x] 1.4 `quality-gates.md`：新增「一致性制品 / baseline / 哈希锁 / 禁篡改」条款（落实 v1.9.0 D-d 承诺的 `state-coverage.json` 机检）
- [x] 1.5 `quality-gates.md`：§八 改三指标（执行率 / 阻断数 / 下游归因缺陷数）+ 关键词门禁「高捕获零价值」识别
- [x] 1.6 `quality-gates.md`：QG-5 降级条款收紧（exit-3 需机器可核验理由；降级不改变判据）
- [x] 1.7 `evidence-capture.md`：增「一致性制品 + baseline + T1/T2/T3」约定；`cw-evidence.sh` exit-3 语义收紧
- [x] 1.8 `task-tracking.md`：§3 票面增「验收锚点」字段（人读引用 + 机读锚点 id）
- [x] 1.9 三份模板核对模板头（首行）+ 结尾换行 + 无禁串

## 2. 编排（受管模板）

- [x] 2.1 `SKILL.md` G0：加「锚点门」（四项机检）+「一致性制品生成」（原型→conformance.json + baseline + e2e 骨架 + 哈希锁）
- [x] 2.2 `SKILL.md` G1/G2：加自动核验接线（CI 三层）+ 证据 manifest 校验 + exit-3 收紧说明
- [x] 2.3 `SKILL.md` G4：加收尾校验（baseline 哈希一致 / 制品在位）
- [x] 2.4 `agents-quick-reference.md`：同步锚点门 / 制品 / 自动核验 / §八 三指标
- [x] 2.5 两份模板核对模板头 + 结尾换行

## 3. 脚本（受管）

- [x] 3.1 `cw-tickets-check.sh`：C3/C4 由关键词 grep 改为锚点机检（完备 / 无孤儿 / 可断言 / 来源非空），保留 C1/C2/C5-C8
- [x] 3.2 `cw-evidence.sh`：新增 `record-state` 子命令（写入带 runner 上下文/时间的 state-coverage 条目）；exit-3 需 `--reason` 且记录
- [x] 3.3 `pr-automation.sh`：G2 出口接证据 manifest 校验（ui-surface 票缺 manifest → 退 1）
- [x] 3.4 三个脚本 `bash -n` + `shellcheck --severity=warning` 通过；无 bash 4+ 特性

## 4. 新增受管 CI 工作流 + 受管清单

- [x] 4.1 新增 `workflows/evidence-check.yml`：ui-surface 触发（label ∪ path filter）+ T1/T2/T3 三层核验 + 跨模型复核步骤
- [x] 4.2 `lib/render.sh` 的 `cw_list_files` 增 `workflows/evidence-check.yml`（受管数 **22 → 23**）
- [x] 4.3 `workflows/evidence-check.yml` 核对：无仓库特有值残留、无 bash 4+ 特性

## 5. e2e 契约锁（先红后绿，DQ-3）

- [x] 5.1 受管数断言 22 → 23（含 `cw_list_files` 输出、manifest 行数、模板头计数如受影响）
- [x] 5.2 新增断言：`quality-gates.md` 含「双形态 / 验收锚点 / 一致性制品 / §八 三指标」条目
- [x] 5.3 新增断言：`cw-tickets-check.sh` 锚点机检生效（缺锚点 → 违规）；`cw-evidence.sh` exit-3 需 reason
- [x] 5.4 先跑红相（断言在改模板/脚本前失败）→ 改到绿相
- [x] 5.5 `./test/install-update-e2e.sh` 全绿（输出贴入 CHANGELOG）

## 6. 静态门禁 + 版本

- [x] 6.1 `for s in setup.sh update.sh lib/render.sh scripts/*.sh test/*.sh; do bash -n "$s"; done` 通过
- [x] 6.2 shellcheck `--severity=warning -x` 通过
- [x] 6.3 bash 3.2 静态拦截（无 `local -n` / `declare -A` / `mapfile` / `readarray`）通过
- [x] 6.4 占位符 / 模板头 / 结尾换行 / 特有价值残留 CI 步全绿
- [x] 6.5 `VERSION` + `CHANGELOG.md`（`### 新增/修复` → `### 教训反思` → `### 验证`）+ `config.example.conf:12` 三处同步
- [ ] 6.6 `git tag` + push

## 7. 消费仓迁移

- [ ] 7.1 `./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis` 确认无冲突、LOCAL 哨兵完整、覆盖数一致
- [ ] 7.2 md-bundle：`update.sh` → 接受 `quality-gates.md.new` → **人工合并**（按该仓占位符/模块调整）→ 重跑 rollout-check
- [ ] 7.3 clairis / mdpkg 各自 LOCAL 哨兵（`domain.md` / `issue-tracker.md` / `triage-labels.md`）人工合并

## 8. 元验收

- [x] 8.1 反向用例：本次 20 处偏差逐条问「本机制能否拦」→ 目标 **≥18/20**（记录实测：图标名/几何/色板/hover/残留/栏数走 T1/T3；底色/间距走 T1；余下感知走 T2）
- [x] 8.2 记录每个新/改门禁的 expected capture（供 §八 三指标下季度对账）
