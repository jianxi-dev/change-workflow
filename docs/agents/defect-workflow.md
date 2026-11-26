<!-- change-workflow 工具包模板 —— 由 setup.sh 安装到目标项目 docs/agents/。
     示例值（模块列表 / 看板 ID / 质量门禁命令）请按目标项目调整；
     占位符 {{REPO}} / {{PROJECT_ID}} / {{STATUS_FIELD_ID}} / {{OPT_*}} 由 setup.sh 自动替换。 -->

# 缺陷管理流程

> 本仓库所有缺陷统一使用 **GitHub Issues** 管理，仓库：`{{REPO}}`
> 
> 本地文件 `bug-registry-*.md` 仅作为缓存，**GitHub Issues 是唯一事实来源**。
> 
> **缓存策略（2026-09-12 起）**：废弃本地 `bug-registry-*.md` 缓存维护，一律以 `gh issue list` 为准。需要本地快照时临时生成，不再维护"缓存 ↔ GitHub"双向同步。

> 涉及未提交改动、错误计划、snapshot 恢复或 `reset`/批量覆盖时，先阅读 `docs/agents/incident-uncommitted-work-loss.md`；该文档是共享工作区保护和恢复流程的唯一来源。

> 缺陷处理的质量判据见 `docs/agents/quality-gates.md` §三（**DQ-1..DQ-9 缺陷处理质量门禁**）与 §二（QG-4/QG-5）；本节末尾「修复质量门禁」为缺陷场景下的强制应用。

---

## 快速操作

### 创建新缺陷

```bash
# 交互式创建
cd {{REPO_ROOT}}
gh issue create --title "[bug] 缺陷标题" --body "详细描述" --label "bug,p0,editor"

# 或一次性创建（推荐用于批量导入）
cd {{REPO_ROOT}}
gh issue create \
  --title "[bug] 缺陷标题" \
  --body "## 问题描述
描述问题...

## 期望行为
期望的结果...

## 复现步骤
1. 步骤1
2. 步骤2

---
*模块: editor*
*优先级: P0*" \
  --label "bug,p0,editor"
```

### 查看缺陷列表

```bash
# 列出所有开放缺陷
cd {{REPO_ROOT}}
gh issue list --state open

# 按标签过滤
gh issue list --label "bug,p0" --state open

# JSON 格式输出
gh issue list --state open --json number,title,labels,assignees
```

### 更新缺陷状态

```bash
# 添加评论
cd {{REPO_ROOT}}
gh issue comment <编号> --body "修复中..."

# 移交 triage 状态（5 个 canonical 标签）
gh issue edit <编号> --add-label "ready-for-agent"    # 已充分定义，可交给 agent 执行
gh issue edit <编号> --add-label "ready-for-human"    # 需要人类决策或实现
gh issue edit <编号> --remove-label "needs-triage"    # 离开待评估队列

# 关闭缺陷（修复完成）
cd {{REPO_ROOT}}
gh issue close <编号> --comment "已修复，提交 commit: xxx"
```

---

## 严重级别定义

| 级别 | 名称 | 定义 | 响应时间 |
|------|------|------|----------|
| P0 | 阻塞级 | 阻塞发布，核心功能无法使用 | 立即处理 |
| P1 | 高优先级 | 主流程受损，有 workaround | 24小时内 |
| P2 | 中优先级 | 有 workaround，体验受影响 | 1周内 |
| P3 | 低优先级 | 体验优化，功能增强 | 排期处理 |

---

## 模块标签

按本仓实际模块划分填写（安装时由 setup.sh 按 `.change-workflow.conf` 的 `MODULE_LABELS` 创建），例如：

- `<module-a>` - 模块 A
- `<module-b>` - 模块 B

---

## 非功能视觉缺陷（视觉偏差票）

「太大」「太丑」「斜杠有点长」这类反馈不是功能 bug，但必须可提票、可度量、可关闭，否则只能挤进 P3 或不了了之。

**定义**：界面元素在**位置、尺寸、比例、形状、层级、留白**上与设计系统条款（`docs/design/system/spec.md`）或部件台账行（`decisions.md`）不一致；功能行为本身正常。

**建票规则**

- 标签：复用 `bug` + `ui-surface` + 模块标签，**不新建专用标签**。
- 级别：默认 P3；影响可读性或主流程识别（控件遮挡内容、控件过小点不中）时 P2。
- 票面必须含三样，缺一样视为信息不足、回 `needs-info`：
  1. **规范锚点**：`design-system:§N` 或 `ledger:<部件>`
  2. **现状值**：现在是多少（px / 比例 / 实测截图）
  3. **期望值**：按规范应为多少，或明确的期望终态描述

- 票面写法：在 `**Acceptance criteria**` 之后增加一行 `**视觉锚点**: design-system:§N` 或 `**视觉锚点**: ledger:<部件>`，多条用 `;` 分隔；**锚点内不得写像素值**（数值只在 spec 定义）。该字段是 `cw-tickets-check.sh` C9 的检查对象（C9 随第二个 change 落地，在此之前由 code-review 执行）。

用户只给模糊描述时，执行者先补全三样，并给 2–3 个候选终态供选择（见 `docs/agents/ui-feedback.md`），再开票或直接改。

**锚点不存在时**（gap）：先补条款或补台账行，不把「规范没有」当成「可以随便定」。gap 本身是正常信号，不等于缺陷挂起。

**关闭条件**：修后附 before/after 成对证据（QG-5 / `evidence-capture`），票面写清对上了哪一条款。

**升级规则**：同一部件 30 天内出现第 2 张视觉偏差票 → 至少追加一行台账并写明复发；累计 **≥3 张同源票**时按 DQ-7 强制升级为规范修订（阈值与 `quality-gates.md` 的 DQ-7 一致）。

---

## 状态流转

```
待评估 (open + needs-triage)
    ↓
已确认 (open + bug)
    ↓
待执行 (open + ready-for-agent) / 待人工 (open + ready-for-human)
    ↓
已关闭 (closed)
```

---

## 从聊天反馈创建缺陷

当用户通过聊天反馈缺陷时，按以下流程操作：

1. **提取信息**
   - 问题描述
   - 期望行为
   - 复现步骤
   - 严重级别判断 (P0/P1/P2/P3)
   - 模块归属

   > batch 级反馈先走对账表（[feedback-alignment.md](./feedback-alignment.md)）：每条编号反馈必须有处置（做票/暂缓+理由/待补充），禁止静默丢弃；对账确认后才拆票。

2. **创建 GitHub Issue**
   ```bash
   cd {{REPO_ROOT}}
   gh issue create \
     --title "[bug] 问题摘要" \
     --body "## 用户反馈
问题描述...

## 期望行为
...

## 复现步骤
...

---
*来源: 聊天反馈*
*模块: xxx*
*优先级: Px*" \
     --label "bug,px,模块"
   ```

3. **通知用户**
   - 回复用户："已创建 GitHub Issue #xxx 追踪此问题"
   - 提供链接：`https://github.com/{{REPO}}/issues/xxx`

---

## 批量导入（从本地文件）

如果缺陷先记录在本地 `bug-registry-*.md`，批量导入命令：

```bash
# 先确保所有标签已创建（模块标签按本仓实际填写，即 .change-workflow.conf 的 MODULE_LABELS）
cd {{REPO_ROOT}}
for label in "p0" "p1" "p2" "p3" "bug" <module-a> <module-b>; do
  gh label create "$label" --force
done

# 然后逐个创建 issue（或使用脚本批量创建）
gh issue create --title "..." --body "..." --label "..."
```

---

## 查看缺陷看板

GitHub Projects 看板地址：
https://github.com/{{REPO}}/projects

或直接在仓库 Issues 页面查看：
https://github.com/{{REPO}}/issues

---

## 修复质量门禁（DQ-1..DQ-9 / QG-4 / QG-5 / C10 数据面）

> 完整定义见 `docs/agents/quality-gates.md` §三。本节说明缺陷修复场景下的强制应用。

### 开工前：triage 不可跳过（DQ-1）

任何缺陷票在开工前必须三条件齐备，缺一**禁止开工**：

1. 已移除 `needs-triage`
2. 已加 `ready-for-agent`
3. 票上**存在 triage brief 评论**（含「## Triage 结论」+「## Agent Brief」）

```bash
gh issue view <N> --json labels,comments \
  --jq '{labels: [.labels[].name], hasBrief: ([.comments[].body] | map(select(test("Triage 结论|Agent Brief"))) | length > 0)}'
```

**真实教训**：`#187` 全程仅有 `needs-triage`、无 `ready-for-agent`、评论数 0 —— 从未 triage 就被修复并合并。流程本身可用（`#171/#172/#173/#178` 均有 brief），只是**无门禁强制**。

### 开工前：根因须独立确认（DQ-2）

票面写的「修复方向 / 建议方案」是**假设，不是结论**。开工前必须独立复现并定位根因；**与票面不符时，必须在票上更正实际根因**（含与票面假设的对照）。

**真实教训**：`#187` 票面「修复方向」指向「拆分巨型旅程（首要）」，理由是「4 个串行 download 和 = 120s = 测试预算」。独立探针实测真根因是**步骤 4/7 的陈旧断言**各烧 10-15s 把预算推到边界 —— 这既解释了「间歇」，也说明票面的「预算不足」解释是**片面的**。若按票面只做拆分而不修陈旧断言，**超时会依旧复现**。

### 修复前：先红后绿（DQ-3）

修复前**必须先有可复现的失败证据**，并作为「红」粘贴到票上；修复后附「绿」。未附「红」证据的修复**不予合并**。

**真实教训**：`#176` 首版「修复」实际**引入回归**（有序列表数字消失 + 圆点覆盖任务标记）。若有先行的红/绿对照，回归会在同一轮暴露。

### 修复触及数据面须走既有数据链路（C10 的缺陷线应用）

数据面门禁（`docs/agents/data-surface.md` / C10）最初只挂在 change-workflow 的 G0/G0-POST/G1；**缺陷路径当时完全旁路**——修「工具条缺动作」类票时可直接往常量数组里塞一项，硬编码回潮无检查拦截。

规则：修复 diff 命中数据面路径（`.change-workflow.conf` 的 `DATA_SURFACE_PATHS`）时，**禁止新增硬编码常量**（新动作 id / 新扇区 / 新图标名直接写死常量数组）。两种合法出口：

1. 缺陷本身是**既有数据链路的 bug**（字段被忽略 / 校验漏判 / 回滚失效）→ 正常修复 + 回归测试；
2. 缺陷根因是**该面根本没有数据化** → 按 DQ-7 同款语义**升级为 change**，不在缺陷票内打补丁。

机检（把原始输出作为证据附在票上，与 QG-5 同款）：

```bash
./scripts/cw-data-surface.sh pr <基线ref>   # diff(基线..HEAD+未提交) 命中数据面路径 → exit 1
```

**同构教训**：`UI_PATH_GLOB` 当初为躲误报收窄识别，结果 17 个 UI 修复 PR 全部旁路。缺陷线是新旁路口，故用同一「路径信号优先」机制堵住，不做意图判断。

### 复现必须走真实路径（QG-4）

缺陷复现与回归测试**必须驱动真实链路**，禁止为「让测试好写」而绕过被破坏的那几跳。

```ts
// ❌ 绕过 keymap，bug 恰在 keymap 里 → 测试全绿但真实按键仍失效
handleAutoPair(view, '**')

// ✅ 驱动真实输入路径
await view.dispatch(inputEvent(view, '**'))
```

**同源规则**：
- 测可见性 → 断言**计算样式**（`getComputedStyle`），禁止断言「元素存在」（元素可能在 DOM 中但 `opacity:0`）
- 测扩展 → 经**真实 `EditorView`**，禁止 mock `EditorState`（依赖 Lezer 语法树的逻辑无法被 mock 满足）

**真实教训（editor-v2 修复期）**：`#174` 自动配对的修复测试直接调 `handleAutoPair()`，绕过 `keydown → keymap → inputHandler` 两跳——而 bug 恰在那两跳（`key: '**'` 是非法 CM6 键名，被静默丢弃）。测试全绿，真实按键**零配对**。

### 关闭票必须附验证者原始证据（DQ-5 / QG-5）

**关闭缺陷票前**，必须由**验证者（非修复者）**跑自己的探针，并把**原始输出**粘贴到票上。

**禁止采信的证据形式**：「测试通过」「已修复」「冒烟正常」——这些是**结论**，不是**证据**。证据必须是可复核的原始观察：标准输出 / DOM 快照 / 计算样式值 / 解析错误数 / 真实按键结果。

```bash
# 关闭票的正确形态
gh issue close <编号> --comment "已验证。原始观察：

ORDERED spans: \"1. \" | \"2. \"
HEADING inactive class: cm-heading-marker text: \"# \"
computed opacity: 0

验证方式：本地真实浏览器 e2e，16 passed (16.3s)"
```

**真实教训（editor-v2 修复期）**：修复期抓出 **4 个「自测全绿但实际无效」**的交付，**4/4 全部由独立探针抓出**：

| 对象 | 自报 | 独立探针实测 |
|------|------|--------------|
| `#174` 自动配对 | 测试通过 | 绕过 keymap，真实按键零配对 |
| `#176` 有序列表 | 已修复 | 引入回归：数字消失 + 圆点覆盖 `○`/`✓` |
| `#170` 结构面板 | 浏览器冒烟通过 | `useMemo([editorView])` 依赖稳定对象 → 诊断**永不刷新** |
| `#170` 测试 | 408 passed | 残留 `makeMockView is not defined` 半成品文件未被计数，**误报为绿** |

### flaky 必须给出机制解释（DQ-4）

判为「flaky」时**必须给出「为何间歇」的机制解释**，不得以「重跑通过」结案。

**关键**：若测试**吞掉断言失败以延续后续步骤**（继续执行模式），flaky 可能掩盖**确定性损坏** —— 此时必须逐步核对每个子步骤的结论，而非只看测试退出码。

**真实教训**：`#187` 以「CI flaky，跨 PR 间歇复现」立项并长期挂着。真相是步骤 4/7 **确定性失败**（陈旧断言必失败），吃掉约 25s 预算使总时长落在 115-125s，**恰好跨过 120s 线**于是表现为「间歇」。更严重的是该 spec 用 `record()` 吞掉步骤失败 → **步骤全挂也「绿」**，CI 只看退出码 → 该 spec 长期失去守门能力。

### 同根因合并例外（DQ-6）

默认 **1 bug 票 = 1 `fix/<slug>` = 1 PR**。**例外**：N 票**同根因 / 同文件 / 同修复**时，允许 1 PR 关 N 票，但 PR body 必须**逐票 `fixes #N`** 并说明共同根因。

**真实案例**：`#173/#174/#175/#177` 同属「智能输入」同一根因、同一文件（`smart-input.ts`），由 PR `#182` 一并关闭 —— 合理，但原规则无豁免条款，属于「规则与现实不符」。无豁免通道时执行者会**静默忽略规则**，侵蚀整条规则。

### 多票同根因 → 必须升级为规范修订（DQ-7）

当 **≥3 张缺陷票指向同一流程环节**时，不得只逐票修复，必须**反查该环节并产出规范修订**留痕。

**真实教训**：`editor-v2` 的 10 张票（`#170`-`#179`）**全部**指向同一环节 ——「完成定义写在库层 + 无 e2e 绑定 + 接线无归属」。当时逐票修复（6 个 PR），**从未反查流程**，直到用户要求复盘才产出 QG-1..QG-7。**若在第 3 张票时就反查，可提前拦截后续 7 张。**

### 关闭时维护生命周期标签（DQ-8）

关闭票时**必须移除** `needs-triage` / `ready-for-agent`。P0/P1 票**部分交付**时票**保持 OPEN**，并在票上评论**列出已交付增量与剩余项**。

```bash
gh issue list --label ready-for-agent --state all --json number,state \
  --jq '.[] | select(.state=="CLOSED") | .number'
# 期望：无输出
```

**理由**：关闭票残留 `ready-for-agent` 会污染 `gh issue list --label ready-for-agent --state open` —— 而该查询正是 G3 自动推进（frontier）的依据。

### 真机偏差类验收分级（DQ-9）

**规则**：修复命中真机偏差类触发信号（字体/布局测量、持久化/生命周期、协议/原生行为、用户语义裁定、同一面被 IPC mock 桥覆盖）时，验收须含**双路径证明或用户执行的真机检查清单**，**headless e2e 绿单独不构成关闭条件**。完整定义、触发信号、实证案例与反模式见 `docs/agents/quality-gates.md` DQ-9（含配套的「测试基础设施卫生」小节：验证前须清理 dev server 端口陈旧监听，服务复用导致的假红/假绿是第一类失败模式）。

### 修复必须同时防回归

修复缺陷时**必须**同时新增或扩展一条 e2e 用例或真实路径测试，**锁住该缺陷不再复现**。仅改源码不锁行为的修复不予合并（QG-2 在缺陷线的应用）。

### 从「功能不可见」类缺陷反查流程（DQ-7 的应用）

当缺陷表现为「**功能根本没在操作页面中显示**」（如 `#170`：11 个功能未接入应用层）时，**不得只记为单张 bug 票**，必须反查 change 流程缺陷并写入 `docs/agents/quality-gates.md` 或本仓质量复盘文档：

- 是 QG-1 失效（AC 写在库层）？
- 是 QG-2 失效（无 e2e 覆盖）？
- 是 QG-3 失效（接线无归属）？
- 是 QG-7 失效（横向切片）？

反查结论用于修订规范，避免同类问题在下一个 change 复现。

> **触发阈值（DQ-7）**：**≥3 张**缺陷票指向同一流程环节时，反查是**强制**的，不能只逐票修复。

---

_最后更新：2026-11-26_
