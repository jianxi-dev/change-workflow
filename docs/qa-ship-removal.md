# qa/ship 移除决策记录（change-workflow 1.4.0）

> 本文件整理 2026-09-25 关于 gstack `qa` / `ship` 是否属于 change-workflow 的完整论证过程。
> 结论：两者不承重，1.4.0 移除。
> 落地：`CHANGELOG.md` 1.4.0；`skills/change-workflow/SKILL.md`（「明确不纳入」行）；
> `docs/agents/task-tracking.md` §7.6「浏览器验证与发版」。
>
> 本文件是仓库内部决策记录，**不是受管模板**（受管 glob 是 `docs/agents/*.md`），不会装进消费仓。

## 一、为什么要论证这件事

起因是三个具体的困惑，它们逐层揭开了一个未定义的接缝：

1. change-workflow 里交付用的「原子提交」是什么，与 `/ship` 什么关系
2. 消费仓什么时候该跑 `qa` / `ship`
3. 在「非 base 分支」跑 qa 到底指哪条分支

前两个问题文档里都有答案；第三个一追问就露底：**文档从未定义 qa/ship 在「逐票合 main」模型里的落点**。

## 二、事实澄清

### 2.1 交付的「原子提交」是脚本，不是 skill

**结论**：G2 的机械动作由 `scripts/pr-automation.sh` 承担。

「原子」在本工具包里的含义是 **1 task = 1 ticket = 1 分支 = 1 PR**：一次只 `git add` `--files` 白名单内的路径，禁止 `git add -A`（`pr-automation.sh:296`；白名单外的改动含 untracked 一律拒收退 1，`:240-244`）。

**误导来源**：`docs/agents/task-tracking.md` 的闭环示意图曾写 `git-master 提交 fixes #N`。`git-master` 是 gstack 的通用 git skill，它**不在** `SKILL.md` 的 skill 调用总表里；那行是 `pr-automation.sh` 脚本化之前留下的孤儿引用，1.4.0 已改为 `pr-automation.sh`。

> 判据：确认某个依赖是否真在流程里，查 `SKILL.md` 的调用总表与 `quality-gates.md` 的门禁条目，不要只看某处提到它的文字。

### 2.2 `/ship` 与 `pr-automation.sh` 的分工

| 维度 | `pr-automation.sh`（G2） | `/ship`（gstack） |
|---|---|---|
| 性质 | bash 脚本，确定性机械动作 | skill，判断性全流程 |
| 触发 | 每票交付（G1 出口通过后） | 正式发版 且 QA 已通过 |
| 范围 | 单票：白名单提交 → push → PR → 分级合并 | 整条发布链：merge base → test → coverage audit → review → VERSION bump → CHANGELOG → TODOS → commit → push → 发版 PR |
| token | 低（无 LLM 判断） | 高（跑 review/coverage/plan 检查，会发现问题并当场修） |
| 版本文件 | 不碰 | 核心职责就是 bump |
| 进日常流程 | 是（G2 唯一收口） | 否 |

一句话：G2 把「这一票的代码」变成 PR；ship 把「一批已合并的成果」变成一次带版本号的发布。

### 2.3 为什么 G2 收口后再跑 `/ship` 会「无可提交」

`/ship` 的幂等设计（gstack `ship` SKILL.md 的 Re-run behavior 段）：**verification 每次重跑，action 幂等**。

- G2 已 commit → 工作区干净，无未提交改动可纳入
- VERSION 未动 → Step 12 跳过 bump
- 已 push → Step 17 跳过 push
- PR 已存在 → Step 19 只改 body

所以「无可提交」是预期行为。更根本的问题是**时机**：G2 刚在 feature 分支上收口，此时根本不该跑 ship。

### 2.4 什么时候跑 qa / ship

| skill | 触发条件 | 性质 |
|---|---|---|
| `qa` | 发版前必做（ship 前置门禁）；日常 risk-high / 核心模块收口前按需；change ≥6 票时按 QG-6 做轻量浏览器确认 | 判断性验证，产 health score + ship-readiness |
| `ship` | 正式发版 **且 QA 已通过**；G3 之后，按发布节奏 | 发布通道 |

### 2.5 ship 里没有 learn / sync-gbrain

**不含。** ship 内部有三套自己的学习 / 记录动作，名字相似，但写的是 gstack 私有库：

| ship 内部动作 | 写到哪 | 是 change-workflow 的 learn / sync-gbrain 吗 |
|---|---|---|
| `gstack-learnings-log`（Capture Learnings） | `~/.gstack/` 跨项目 learnings | 不是 |
| `gstack-review-log`（Step 20 持久化 metrics） | `~/.gstack/projects/<slug>/` | 不是 |
| `gstack-skill-end`（Telemetry） | `~/.gstack/analytics/` | 不是 |

change-workflow 的 `learn` → `sync-gbrain` 由**编排层在 ship 之后补跑**（`SKILL.md` 调用总表与 G3 章节）。

### 2.6 「非 base 分支」是什么，怎么创建

**base 分支 = PR 的目标分支**，在本工具包里就是 conf 的 `DEFAULT_BRANCH`（默认 `main`）。qa/ship 启动时自动探测：`gh pr view --json baseRefName` → `gh repo view --json defaultBranchRef` → `origin/HEAD` → `main` / `master`。

**非 base 分支 = 除它以外的任何分支**。为什么必须：

- `ship` Step 1 在 base 分支直接 abort（"You're on the base branch. Ship from a feature branch."）：它要 bump 版本并开 PR，PR 不能从 main 指向 main
- `qa` 的 diff-aware 主模式靠 `git diff <base>...HEAD` 找改动；在 main 上 diff 为空

创建：

```bash
git fetch origin
git checkout -b chore/release-vX.Y.Z origin/main
git branch --show-current          # 确认不是 main
```

## 三、根因：模型不匹配

gstack 的 qa/ship 假设「工作累积在**长命分支**上，收尾时一次性 ship」；change-workflow 是「1 票 1 PR，**逐票合 main**」。两套模型没有对齐，文档也没说清，于是留下一个未定义的接缝。

## 四、三个被击穿的错误论证

这是本次讨论最有价值的部分：三个听起来合理、实则站不住的论证，全部由追问击穿。

### 4.1 「在最后一批 feature 分支上跑 qa」不成立

- **定义不了**：逐票合 main 没有「批」的概念，任何「批」都是人临时圈的
- **没意义**：验最后一条票只是重复 G1 已做的事（risk-high / 核心模块本就该在 G1 出口跑 qa）
- **真实的多票集成验证是 QG-6**：change ≥6 票时，每 ≤4 票合并到**集成分支** → build → 浏览器打开一次 → 记录「用户现在能看到什么」。集成分支才是有 diff 可验的那条

### 4.2 「在发版分支上全量跑 qa」不成立

qa 是**浏览器驱动**的 skill，只有两种入口：

| 模式 | 触发 | 需要什么 |
|---|---|---|
| Diff-aware | feature 分支且未给 URL | 一个 **diff**（`git diff main...HEAD`） |
| Full / Quick | 给了 URL | 一个**运行中的应用** |

就算 diff-aware 找不到受影响页面，它也不跳过浏览器测试，而是退回 Quick（首页 + 前 5 个导航目标），**但仍需要应用在跑**。

所以「全量跑」的正确说法是：**必须指向一个运行实例**（本地 `pnpm dev` 或预览部署）。空分支不是问题，「没有可运行实例」才是。qa 不是「跑在分支上」，是「跑在运行中的应用上」；分支只决定测哪些页面。

### 4.3 为什么先写出了前两个错误论证（自我记录）

因为它们**能糊住文档的空白**。文档没定义 qa/ship 的落点，就用「最后一批」「全量跑」补了一段听起来合理的解释，而不是承认「这里没定义」。

识别信号：**当一个解释需要引入文档里不存在的概念（「批」）才能自洽时，它大概率是在掩盖缺失。**

## 五、判定：qa/ship 是否承重

### 5.1 决定性证据：门禁的唯一事实来源里零引用

`docs/agents/quality-gates.md` 是「票内容与完成判据」的单一事实来源，含 QG-1..QG-7 与 DQ-1..DQ-8。**它从不引用 qa/ship**，说明两者从未是门禁。

### 5.2 失效模式对照：没有一条靠 qa/ship 防

| 失效模式 | 实证 | 谁防 |
|---|---|---|
| 功能不存在（CI 绿但用户看不到变化） | editor-v2：9 个 PR 中 8 个对 app 与 e2e 双双零改动 | QG-1 / QG-2 / QG-7 |
| 自测全绿但实际无效 | 4/4 全部由独立探针抓出 | QG-5 |
| 假修复（票面方向当结论） | #187 | DQ-2 / DQ-3 / DQ-5 |
| 多分支延迟集成、合并 ≠ 能跑 | 12 票机械粘 export | QG-6 |

`QG-5`（独立验证 + 原始证据）就是本工具包版的 qa：验证者跑自己的探针（真实按键 / `getComputedStyle` / XML 解析 / `EditorView`），把原始输出贴到票上，**不可豁免**。`QG-6` 就是本工具包版的集成冒烟。

### 5.3 放弃各自失去什么

| 放弃 | 失去的独有价值 | 不受影响 |
|---|---|---|
| qa | 穷举式浏览器探索（找「没人写探针的潜伏 UI bug」）+ health score + 自动修 bug | QG-2 e2e、QG-5 独立探针、QG-6 集成确认全保留 |
| ship | 自动 VERSION / CHANGELOG / TODOS / 发版 PR | 发版仍可 `VERSION + CHANGELOG + tag` |

**qa 的独有价值是真的，但它不是 change-workflow 要防的东西。** QG-5 防「功能根本不存在」（有预设探针、有原始证据）；qa 防「功能存在但有潜伏 bug」（无预设探针、靠探索）。本工具包整套设计目标是前者。

## 六、决策判据与结论

**决定性问题**：消费仓有没有「没人为它写探针、但用户会撞上」的 UI bug 风险？

| 答案 | 处置 |
|---|---|
| 没有（工具包 / 契约型仓） | 全部移除；浏览器验证交 QG-5/QG-6；发版走 tag |
| 有（真 UI 消费仓） | 保留 qa 但重新定位到 feature 分支 + 集成分支（diff-aware）；移除 ship |

**本仓（工具包 / 契约型）选择全部移除。** 理由：本仓失败模式是契约与回归（渲染不幂等、CI 绿但 macOS 炸），防护重心在 `test/` + CI，qa/ship 提供不了增量。

**注意打击面**：不适配的只有 qa/ship。`review`（pre-landing 结构审查）、`code-review`（双轴自审）、`sync-gbrain`（代码索引）都作用于 diff 或工作区，与逐票模型无冲突，继续保留。

## 七、落地清单

| 项 | 落点 |
|---|---|
| 删除 qa/ship 流程引用 | `skills/change-workflow/SKILL.md`（术语表、编排图第 ⑫⑬ 边、调用总表、G3 措辞、明确不做） |
| 显式排除说明 | `SKILL.md`「明确不纳入」行 |
| 替代方案成文 | `docs/agents/task-tracking.md` §7.6「浏览器验证与发版」 |
| 文档同步 | 删 qa/ship 行；`git-master` → `pr-automation.sh`；`README.md` 依赖行 |
| 防回归 | `.github/workflows/ci.yml` 新增「qa/ship 移除回归锁」（锁被删的流程字符串，豁免 incident 史料） |
| 发版 | `VERSION` 1.3.1 → 1.4.0；`CHANGELOG.md` 1.4.0 |
| 消费仓 | 三仓升级到 1.4.0（md-bundle / mdpkg / clairis） |

验证：e2e 176 → 178 断言全绿；rollout-check 3 仓 9/0；回归锁红绿双证。

## 八、术语表：最容易混淆的几组

| 名称 | 是什么 | 易混点 |
|---|---|---|
| `pr-automation.sh` | G2 脚本，白名单提交 + PR | 不是 skill；旧文档曾写 `git-master` |
| `git-master` | gstack 通用 git skill | 不在本工具包的调用总表 |
| `learn` | Real Engineers 的 skill，沉淀项目经验 | 与 gstack 的 `gstack-learnings-log`（写 `~/.gstack/`）不同 |
| `sync-gbrain` | 刷新 gbrain 代码索引 | ship 不调用它 |
| QG-5 / QG-6 | 独立验证 / 集成 checkpoint（门禁） | 与 gstack `qa`（探索式工具）不同层 |
| 发版（tag） | `VERSION + CHANGELOG + tag` | 与 gstack `ship`（发版 PR 模型）不同 |
| base 分支 | PR 目标分支 = `DEFAULT_BRANCH`（默认 main） | 不是「集成分支」，也不是「发版分支」 |

## 九、三条可复用的教训

1. **门禁的唯一事实来源是 `quality-gates.md`，不是 skill 调用表。** 一个 skill 若不出现在 QG/DQ 条目里，它就不是门禁。`qa` / `ship` 被编排表列了很久，门禁文档零引用，说明它们从未承重。移除后 QG/DQ 判据一字未动，e2e 与消费仓滚动验证全绿，反证了这一点。

2. **外部 skill 的模型假设必须先与本流程对齐才能纳入。** 模型不匹配时硬塞进流程，只会产生「在哪个分支跑」这类无法回答的问题。落点放不对就该移除，而不是为它编解释。

3. **文档里的孤儿引用是负债。** `git-master` 早于脚本化实现，却留了很久，足以让人以为提交走的是 git skill 而非脚本。清理受管面时要连带扫「同义但过期」的引用，别只删本次点名的那个。
