# Issue 关联机制完善方案

> **创建日期**：2026-09-27
> **状态**：待评审
> **关联地图**：#1（内容驱动的「高设计页面引擎」）

---

## 一、问题诊断

### 1.1 当前 Issue 结构

```
#1 地图（parent，open）
├── #8  研讨：文档结构模型（open）── 机制已决，代码已有（S1），但 issue 还 open
├── #9  研讨：布局文法（open）
├── #10 研讨：效果词汇（open）
├── #11 研讨：受众矩阵（open）
├── #12 研讨：硬约束调和（open）
├── #13 原型：天花板样张（open）
├── #14 原型：多样性证明（open）
├── #15 原型：演示/汇报模式（open）
├── #16 规格初稿（open）── 依赖 #8 + #9
├── #17 规格二稿（open）── 依赖 #16
├── #18 规格三稿（open）── 依赖 #17
├── #19 规格终稿（open）── 依赖 #18
├── #20 迁移策略（open）── 依赖 #19
├── #21 品牌规范（open）
├── #22 3D 方案（open）
├── #23 观感情绪（open）
├── #24 美学门禁（open）
└── #25 原型：S1 核心测试（open）── S1 已完成，但 issue 还 open

S1 change（独立，非 #1 子 issue，全部 closed）
├── #52 spec ───────────── closed
├── #53 语料基座 ───────── closed
├── #54 数据模型 schema ── closed（= #8 想要的代码）
├── #55 信号抽取器 ─────── closed
├── #56 意图评分器 ─────── closed
├── #57 LayoutPlan 规划器 ─ closed
├── #58 自证之一：骨架熵 ── closed（= #25 想要的证据）
├── #59 自证之二：轮廓距离 ─ closed
├── #60 自证之三：反例集 ── closed
├── #61 自证之四：跨机确定性 ─ closed
└── #62 自证之五：对抗检查 ─ closed
```

### 1.2 核心问题

| 问题 | 表现 | 影响 |
|------|------|------|
| **S1 与 #8/#25 无正式链接** | S1 产出满足 #8/#25，但 GitHub 上看不出关系 | #8/#25 该关没关，状态失真 |
| **决策 issue 与规格 issue 无依赖声明** | #16 依赖 #8，但 GitHub 上看不出 | 无法自动判断 #16 是否可启动 |
| **状态不自动传播** | S1 完成 → #8/#25 不自动关；#8 关 → #16 不自动解锁 | 人工追踪成本高，易遗漏 |
| **19 个 open issue 无优先级** | 全部 open，无 blocked/ready 区分 | 不知从哪开始 |

### 1.3 根因

1. **Issue 正文无关联声明段**——决策 issue 和规格 issue 的正文里没有标准化的"依赖/被依赖"声明
2. **标签体系缺失**——没有统一的角色标签（decision/spec/impl）和状态标签（blocked-by/satisfied-by）
3. **无自动化机制**——状态传播完全靠人工，没有 GitHub Actions 或定期巡检

---

## 二、方案：三层关联机制

### 2.1 第一层：标签体系

#### 角色标签

| 标签 | 含义 | 适用 issue |
|------|------|-----------|
| `decision` | 研讨/原型类决策 issue | #8–#15, #21–#25 |
| `spec` | 规格文档 issue | #16–#20 |
| `impl` | 实现 change（S0/S1/S2…） | #52–#62 等 |

#### 关联标签

| 标签 | 含义 | 示例 |
|------|------|------|
| `satisfied-by:<N>` | 被 change #N 满足 | #25 标 `satisfied-by:52` |
| `blocked-by:<N>` | 被 issue #N 阻塞 | #16 标 `blocked-by:8` `blocked-by:9` |
| `auto-close` | 满足后自动关闭 | #25 标 `auto-close` |
| `ready` | 依赖已解除，可启动 | #16 自动加 `ready` |
| `in-progress` | 正在推进 | 人工标记 |

#### 标签组合规则

```
决策 issue 生命周期：
  open（初始）
  → 被 change 满足 → 加 satisfied-by:<N>
  → change 全部 closed → 加 auto-close → 自动关闭

规格 issue 生命周期：
  open + blocked-by:<N>（初始）
  → 所有 blocked-by 解除 → 自动加 ready，移除 blocked-by
  → 开始工作 → 移除 ready，加 in-progress
  → 完成 → 关闭，触发下游检查
```

### 2.2 第二层：Issue 正文标准化模板

#### 决策 issue 模板（研讨/原型）

```markdown
## 关联声明

- **被满足 by**: change #N（S?）— 产出见 #N1, #N2, ...
- **阻塞**: #M（下游规格 issue）
- **自动关闭条件**: S? 全部子票 closed → 本 issue 自动关闭
- **决策结论**: （一句话概括已决方案）
```

#### 规格 issue 模板

```markdown
## 输入依赖

- **blocked-by**: #N（决策 issue 标题）, #M（决策 issue 标题）
- **自动解锁条件**: #N 和 #M 均 closed → 本 issue 自动解锁
- **输入文档**: （列出依赖的决策 issue 产出链接）
```

#### 实现 change 模板

```markdown
## 关联声明

- **满足**: #N（决策 issue）— 产出见本子票 #N1, #N2
- **被阻塞**: （无，或列出阻塞的 spec issue）
```

### 2.3 第三层：自动化机制（GitHub Actions）

#### Workflow 设计

文件：`.github/workflows/issue-link-check.yml`

```yaml
name: Issue Link Status Sync

on:
  issues:
    types: [closed, reopened, edited, labeled]
  schedule:
    - cron: '0 */6 * * *'  # 每 6 小时检查

jobs:
  sync:
    runs-on: ubuntu-latest
    permissions:
      issues: write
    steps:
      - uses: actions/github-script@v7
        with:
          script: |
            const { data: issues } = await github.rest.issues.listForRepo({
              owner: context.repo.owner,
              repo: context.repo.repo,
              state: 'open',
              per_page: 100
            });

            for (const issue of issues) {
              const labels = issue.labels.map(l => l.name);
              const body = issue.body || '';

              // 规则 1: satisfied-by:<N> + auto-close
              // 检查 N 是否全部 closed，若是则关闭当前 issue
              const satisfiedBy = labels.find(l => l.startsWith('satisfied-by:'));
              if (satisfiedBy && labels.includes('auto-close')) {
                const changeNum = parseInt(satisfiedBy.split(':')[1]);
                const { data: subIssues } = await github.rest.issues.listForRepo({
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  state: 'all',
                  per_page: 100
                });
                const changeSubIssues = subIssues.filter(i =>
                  i.body && i.body.includes(`change=s1-content-driven-core`) &&
                  i.number !== changeNum
                );
                // 简化：检查 change spec issue 是否 closed
                const changeIssue = subIssues.find(i => i.number === changeNum);
                if (changeIssue && changeIssue.state === 'closed') {
                  await github.rest.issues.update({
                    owner: context.repo.owner,
                    repo: context.repo.repo,
                    issue_number: issue.number,
                    state: 'closed'
                  });
                  await github.rest.issues.createComment({
                    owner: context.repo.owner,
                    repo: context.repo.repo,
                    issue_number: issue.number,
                    body: `🤖 自动关闭：satisfied-by:${changeNum} 已 closed，auto-close 条件满足。`
                  });
                }
              }

              // 规则 2: blocked-by:<N>
              // 检查所有 N 是否 closed，若是则移除 blocked-by，加 ready
              const blockedBy = labels.filter(l => l.startsWith('blocked-by:'));
              if (blockedBy.length > 0) {
                const allResolved = await Promise.all(blockedBy.map(async (label) => {
                  const num = parseInt(label.split(':')[1]);
                  const { data: target } = await github.rest.issues.get({
                    owner: context.repo.owner,
                    repo: context.repo.repo,
                    issue_number: num
                  });
                  return target.state === 'closed';
                }));

                if (allResolved.every(Boolean)) {
                  const newLabels = labels.filter(l => !l.startsWith('blocked-by:'));
                  newLabels.push('ready');
                  await github.rest.issues.update({
                    owner: context.repo.owner,
                    repo: context.repo.repo,
                    issue_number: issue.number,
                    labels: newLabels
                  });
                  await github.rest.issues.createComment({
                    owner: context.repo.owner,
                    repo: context.repo.repo,
                    issue_number: issue.number,
                    body: `🤖 自动解锁：所有 blocked-by 依赖已解除，标记为 ready。`
                  });
                }
              }
            }
```

---

## 三、状态传播规则

### 3.1 决策 issue 状态流

```
┌─────────────┐
│   open      │  初始状态
│  (decision) │
└──────┬──────┘
       │ 被 change 满足
       ▼
┌──────────────────┐
│ open             │
│ + satisfied-by:N │  标记被 change #N 满足
│ + auto-close     │
└──────┬───────────┘
       │ change #N 全部 closed（workflow 检测）
       ▼
┌─────────────┐
│   closed    │  自动关闭
└─────────────┘
```

### 3.2 规格 issue 状态流

```
┌─────────────────────┐
│ open                │  初始状态
│ + blocked-by:8      │  声明依赖
│ + blocked-by:9      │
└──────┬──────────────┘
       │ #8 和 #9 均 closed（workflow 检测）
       ▼
┌─────────────────────┐
│ open                │  自动解锁
│ + ready             │  标记可启动
│ - blocked-by:*      │  移除阻塞标签
└──────┬──────────────┘
       │ 开始工作
       ▼
┌─────────────────────┐
│ open                │
│ + in-progress       │  人工标记
│ - ready             │
└──────┬──────────────┘
       │ 完成
       ▼
┌─────────────┐
│   closed    │  关闭，触发下游检查
└─────────────┘
```

### 3.3 规格链传播

```
#8 closed ──┐
            ├──→ #16 解锁（ready）──→ #16 完成 ──→ #17 解锁 ──→ ...
#9 closed ──┘
```

---

## 四、执行计划

### 阶段一：Issue 正文与标签更新（纯文档，无代码）

| 步骤 | Issue | 内容 | 产出 |
|------|-------|------|------|
| 1.1 | #8 | 补"关联声明"段：satisfied-by:52, 阻塞 #16, 决策结论 | #8 正文更新 |
| 1.2 | #25 | 补"关联声明"段：satisfied-by:52, auto-close | #25 正文更新 |
| 1.3 | #25 | 关闭（S1 已满足） | #25 closed |
| 1.4 | #16 | 补"输入依赖"段：blocked-by:8,9 | #16 正文更新 |
| 1.5 | #17 | 补"输入依赖"段：blocked-by:16 | #17 正文更新 |
| 1.6 | #18 | 补"输入依赖"段：blocked-by:17 | #18 正文更新 |
| 1.7 | #19 | 补"输入依赖"段：blocked-by:18 | #19 正文更新 |
| 1.8 | #20 | 补"输入依赖"段：blocked-by:19 | #20 正文更新 |
| 1.9 | #9–#15, #21–#24 | 补"关联声明"段（被满足 by 无，阻塞下游） | 各 issue 正文更新 |
| 1.10 | 全部 open issue | 加角色标签（decision/spec） | 标签体系建立 |

### 阶段二：自动化机制（代码）

| 步骤 | 内容 | 产出 |
|------|------|------|
| 2.1 | 创建 `.github/workflows/issue-link-check.yml` | workflow 文件 |
| 2.2 | 测试：手动关闭 #8，验证 #16 自动解锁 | 验证记录 |
| 2.3 | 测试：验证 #25 自动关闭逻辑 | 验证记录 |
| 2.4 | 启用 schedule 触发（每 6 小时） | 自动化上线 |

### 阶段三：验证与收尾

| 步骤 | 内容 | 产出 |
|------|------|------|
| 3.1 | 验证 #8 关闭后 #16 自动加 ready | 截图/记录 |
| 3.2 | 验证 #25 自动关闭 | 截图/记录 |
| 3.3 | 验证规格链 #16→#17→#18→#19 传播 | 截图/记录 |
| 3.4 | 更新 `docs/agents/issue-tracker.md` 加入新机制说明 | 文档更新 |

---

## 五、验证标准

| 验证项 | 判据 | 验证方式 |
|--------|------|----------|
| #25 自动关闭 | S1（#52）closed → #25 自动 closed | 关闭 #25 后检查状态 |
| #16 自动解锁 | #8 + #9 closed → #16 加 ready | 关闭 #8 后检查 #16 标签 |
| 规格链传播 | #16 closed → #17 加 ready | 关闭 #16 后检查 #17 标签 |
| 无误关闭 | 不相关的 issue 不被影响 | 检查其他 issue 状态不变 |

---

## 六、风险与备选

| 风险 | 影响 | 备选 |
|------|------|------|
| GitHub Actions 权限不足 | workflow 无法写 issue | 改用 `issue_comment` 触发 + 人工确认 |
| 标签解析错误 | 状态传播失败 | 正文模板 + 标签双通道，正文为主 |
| 规格链过长传播慢 | #19 解锁延迟 | schedule 频率提高到每 2 小时 |
| 决策 issue 被误关 | 决策丢失 | auto-close 只对有 satisfied-by 标签的 issue 生效 |

---

## 七、后续扩展

1. **看板视图**：GitHub Projects 中按 blocked/ready/in-progress 分列
2. **通知机制**：issue 解锁时自动 @ 相关人
3. **度量指标**：统计平均解锁时间、规格链周期
4. **跨 change 关联**：S2/S3 的产出自动关联到对应决策 issue
