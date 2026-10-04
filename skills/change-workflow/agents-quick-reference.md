<!-- change-workflow 工具包模板 -->

---
name: agents-quick-reference
description: 四拍速查卡——G0 规一 → G1 实施 → G2 提交 → G3/G4 收尾的关键动作与出口条件。日常执行照此跑，细节回 SKILL.md。
---

# 四拍速查卡

> 日常执行照此跑，细节回 `SKILL.md` 对应段。SKILL.md 是单一事实来源。

## G0 规一

**执行**：to-spec → openspec-propose（切片）→ to-tickets 拆票（Parent=spec issue）

**关键动作**：
1. to-spec 综合产出 spec issue → 四要素映射写入 requirements.md
2. 需求输入门（L-1）：来源可追溯 / 空白显式化 / 一手证据 / 冲突显式 / 验收锚点
3. openspec-propose 生成 proposal/design/tasks.md（垂直切片约束）
4. to-tickets 拆子票（1 task=1 ticket，Parent=#S，标签 ready-for-agent）
5. cw-tickets-check.sh 自检全绿 → 自动发布
6. **锚点门**：规格双形态（人读叙述 + 机读 `conformance.json` 锚点）机检四项——完备 / 无孤儿 / 可断言 / 来源非空
7. **一致性制品**：G0 从原型程序化生成 `conformance.json` + `baseline/*.png` + e2e 骨架，**实现前锁哈希**

**出口条件**：tasks.md 就绪 + 子票全发布 + 看板入列 Ready（详见 SKILL.md §G0）

## G1 实施

**执行**：implement skill（内嵌 tdd）

**关键动作**：
1. 建票级分支 `git checkout -b feat/<slug> origin/main`
2. QG 前置校验（QG-1 AC 可观测 / QG-3 接线归属）
3. implement 按 spec/tickets 实施（内嵌 tdd + 定期 typecheck/test）
4. 四件套硬门禁（typecheck/lint/test/e2e）
5. G1 出口：code-review 双轴 → QG-5 独立验证（编排器跑探针 + 原始证据）
6. **证据 manifest（ui-surface 票）**：`state-coverage.json` ≥4 态，`cw-evidence.sh record-state` 录制；exit-3 降级须附机器可核验理由

**出口条件**：code-review 零未解决项 + QG-5 原始证据 + 验证基于 SHA 标注（详见 SKILL.md §G1）

## G2 提交

**执行**：pr-automation.sh --resume-branch

**关键动作**：
1. 门禁引用纪律：PR body 逐条写 `QG-x: 具体决策`
2. 验证时效：--verified-sha 拦截过期验证
3. 成对证据：UI 变更嵌入 before/after 对比
4. 文字质量：commit/PR 过 pr-writing.md（去 AI 味）
5. auto-merge：risk-low 尝试启用
6. **CI 三层自动核验**（`evidence-check.yml`）：T1 确定量 / T2 感知 / T3 状态机，全自动无人

**出口条件**：PR 创建 + 门禁引用完整 + 成对证据嵌入（详见 SKILL.md §G2）

## G3/G4 收尾

**执行**：learn + sync-gbrain → frontier 推进 → openspec 归档

**关键动作**：
1. G3：learn 沉淀 → sync-gbrain 刷新索引 → decisions-log.sh 决策日志
2. frontier 自动推进下一张可开工票（零询问：会话内连跑 + 跨会话自动接力；被未合并前票阻塞 → 轮询等待）
3. G4：全部合并 → 收尾生命周期黑盒巡检 + 发现闭环门（QG-8）→ opsx-sync → validate --strict → archive → 看板 Done → 关 spec issue
4. G4 收口后：盘点剩余 open issue（分类清单 + 下一项建议 + 询问是否继续）
5. G4 一致性制品校验：baseline 哈希与 G0 锁一致（不一致不得收尾）

**出口条件**：change 归档 + spec issue 关闭 + 看板 Done + 剩余清单已盘点（详见 SKILL.md §G3/G4）

## 质量门禁索引

| 编号 | 一句话 |
|---|---|
| QG-1 | AC 三分类：存在 / 生命周期 / 保真 |
| QG-2 | 用户可见变更必须新增/扩展 e2e |
| QG-3 | 新 API 必须指定接线票与位置 |
| QG-4 | 测试驱动真实链路 + 断言强度阶梯（渲染类 ≥ 文本相等 / 可取消类 ≥ 状态往返） |
| QG-5 | 验证者跑自己的探针 + 原始证据 + 视觉探针（交互票多态截图） |
| QG-6 | ≥6 票时每 ≤4 票做集成 checkpoint |
| QG-7 | 每条 task 须能回答「用户能看到什么」 |
| QG-8 | 发现闭环门：findings 须转 tracked issue / 规格 |
| DQ-1 | triage 不可跳过（brief 评论必须存在） |
| DQ-2 | 根因须独立确认，票面方向是假设 |
| DQ-3 | 先红后绿（复现证据强制） |
| DQ-4 | flaky 须给机制解释，不以重跑结案 |
| DQ-5 | 关闭缺陷须附验证者原始证据 |
| DQ-6 | 同根因可 1 PR 关 N 票（逐票 fixes） |
| DQ-7 | ≥3 票同根因 → 升级规范修订 |
| DQ-8 | 关闭票时移除生命周期标签 |

## 机制层（不新增门禁条目，给现有门禁装机检）

- **规格双形态 + 验收锚点**：人读散文 + 机读 `conformance.json`，双向链接；G0 四项机检（`cw-tickets-check.sh` C3/C4）。
- **一致性制品 + baseline**：原型 = spec，G0 程序化生成、哈希锁、禁篡改。
- **证据 manifest**：`.artifacts/<票号>/state-coverage.json`（≥4 态）——本地 G2 校验（`pr-automation.sh`）+ CI 结构校验（`evidence-check.yml`）。
- **降级收紧**：exit-3 须附机器可核验理由；环境已具备 Playwright/ffmpeg 时不构成降级理由。
- **§八 三指标**：执行率 / 阻断数 / 下游归因缺陷数（替代单一「捕获次数」，防退役执行最好的门禁）。
