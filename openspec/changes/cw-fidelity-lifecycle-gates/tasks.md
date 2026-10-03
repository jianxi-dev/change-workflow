## 1. `quality-gates.md` 修订（受管模板）

- [x] 1.1 修订 QG-1：AC 升级为三分类（存在 / 生命周期 / 保真），补四段式（规则/理由/实证案例/如何验证）
- [x] 1.2 将「设计→规格保真」并入 QG-1 第③类保真（吸收原提案 QG-9 的 Scenario 要求）
- [x] 1.3 修订 QG-4：新增「断言强度阶梯」（存在→可见→文本相等→状态往返→视觉）与触发规则
- [x] 1.4 修订 QG-5：探针类型增「视觉探针」；明确「元素存在/count>0」非有效证据、「同类探针自证」不算证据、禁伪造手动 QA
- [x] 1.5 新增 QG-8「发现闭环门」（四段式 + 机检命令）
- [x] 1.6 §四 AC 固定格式替换为三分类模板（存在/生命周期/保真三行）
- [x] 1.7 §五 代码对照增补：callout 重复 / 围栏反引号 / 取消残留 三条正反例
- [x] 1.8 §七 收紧 `no-ui-impact`：浮层/插入/渲染类不得豁免生命周期与保真 AC
- [x] 1.9 §八 为每个新/改门禁加 expected capture 行
- [x] 1.10 核对模板头（首行）+ 结尾换行

## 2. `evidence-capture.md` 修订（受管模板）

- [x] 2.1 §3.2 追加「状态覆盖矩阵」小节（六态 + 命名示例 + ≥4 态规则 + 机检命令）
- [x] 2.2 约定 `.artifacts/<task>/state-coverage.json`（每态：截图路径 + 断言结果）
- [x] 2.3 §三 增「视觉探针」小节（关键态截图 + 人工/多模态复核；交互票单层截图不足）
- [x] 2.4 对齐 §四 活代码优先：多态证据为状态往返断言副产物
- [x] 2.5 核对模板头 + 结尾换行

## 3. `SKILL.md` 修订（受管模板）

- [x] 3.1 G0-PRE 步骤 1 前加「需求输入门」前置检查（五条契约 + fix-first）
- [x] 3.2 编排图输入源段补「需求输入门」节点说明
- [x] 3.3 G1 出口 QG-5 条款同步多态截图与视觉探针
- [x] 3.4 G4 加「收尾生命周期黑盒巡检」+ 发现闭环门（QG-8）前置
- [x] 3.5 核对模板头 + 结尾换行

## 4. `cw-tickets-check.sh` C3/C4 同步（唯一脚本改动）

- [x] 4.1 C3（QG-1 形态）扩展为校验三分类 AC 关键词（取消/残留/空态/严格等于/不含）
- [x] 4.2 C4（禁入信号）同步
- [x] 4.3 `bash -n` + shellcheck 通过（bash 3.2 无 4+ 特性）

## 5. e2e 契约锁（先红后绿，DQ-3）

- [x] 5.1 新增 e2e 断言：`quality-gates.md` 含 QG-1 三分类 / QG-4 阶梯 / QG-5 视觉探针 / QG-8 条目
- [x] 5.2 新增 e2e 断言：`evidence-capture.md` 含状态覆盖矩阵 + `state-coverage.json`
- [x] 5.3 新增 e2e 断言：`SKILL.md` 含需求输入门 / 收尾巡检 / 无 qa-*-manual 反模式
- [x] 5.4 先跑红相（确认断言在改模板前失败）→ 改到绿相
- [x] 5.5 `./test/install-update-e2e.sh` 全绿（断言数更新）

## 6. 静态门禁 + 版本

- [x] 6.1 `for s in setup.sh update.sh lib/render.sh scripts/*.sh test/*.sh; do bash -n "$s"; done` 通过
- [x] 6.2 shellcheck `--severity=warning -x` 通过
- [x] 6.3 bash 3.2 静态拦截（无 `local -n`/`declare -A`/`mapfile`/`readarray`）通过
- [x] 6.4 占位符/模板头/结尾换行/特有价值残留 CI 步全绿
- [x] 6.5 `VERSION` + `CHANGELOG.md`（`### 新增/修复`→`### 教训反思`→`### 验证`）+ `config.example.conf:12` 三处同步
- [ ] 6.6 `git tag` + push

## 7. 消费仓迁移

- [ ] 7.1 `./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis` 确认无冲突、LOCAL 哨兵完整
- [ ] 7.2 md-bundle `update.sh` → 接受 `quality-gates.md.new` → **人工合并**（按该仓占位符/模块调整）→ 重跑 rollout-check
- [ ] 7.3 clairis / mdpkg 各自 LOCAL 哨兵（`domain.md`/`issue-tracker.md`/`triage-labels.md`）人工合并

## 8. 元验收

- [ ] 8.1 反向用例：D1–D10 逐条问「本门禁能否拦」→ 目标 ≥8/10（记录实测）
- [ ] 8.2 记录每个新/改门禁的 expected capture（供 §八 下季度对账）
