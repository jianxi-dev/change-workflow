# Matt Pocock Skills：wayfinder / to-spec / to-tickets 关系与自动化执行机制

> 基于对 [mattpocock/skills](https://github.com/mattpocock/skills) 仓库 SKILL.md 源码的研读整理。

---

## 一、三个技能的定位

| 技能 | 一句话 | 产物 |
|---|---|---|
| **wayfinder** | 为「大到一次会话装不下」的模糊目标绘制决策地图 | 一个 `wayfinder:map` 父 issue + 一堆决策子 issue |
| **to-spec** | 把已讨论/已决策的内容**综合**成一份 spec | 一个 spec issue |
| **to-tickets** | 把 spec/计划**切片**成可实施的 tracer-bullet 票 | 一组带阻塞关系的实施子 issue |

### 流水线位置

```
grill-with-docs（讨论）
       │
       ▼
   wayfinder  ←── 目标太大、太模糊时先画地图
       │  (决策票逐个解决)
       ▼
   to-spec    ←── 把地图上的决策综合成一份 spec
       │  (/to-spec #<map_issue>)
       ▼
  to-tickets  ←── 把 spec 切成实施票
       │  (/to-tickets)
       ▼
   implement  ←── 逐个实施
```

---

## 二、wayfinder：决策地图

### 核心概念

1. **Map issue**：打 `wayfinder:map` 标签，作为父 issue，是整张地图的**索引**（不是容器）。
2. **决策票（tickets）**：map 的 child issue，打 `wayfinder:<type>` 标签（research / prototype / grilling / task）。
3. **Blocking**：子票之间用 tracker 的**原生依赖关系**（GitHub sub-issue / Linear dependency）。
4. **Frontier（前沿）**：open + unblocked + unclaimed 的子票，即可立即执行的工作。

### Map body 结构

```markdown
## Destination
<这条地图要走到什么终点>

## Notes
<领域、技能、偏好>

## Decisions so far
- [<closed ticket title>](link): <one-line gist>

## Not yet specified
<!-- 战争迷雾：能感觉到但还无法精确提问的领域 -->

## Out of scope
<!-- 明确排除的工作 -->
```

### 生命周期

| 阶段 | 做什么 |
|---|---|
| **Chart** | 命名目的地 → 广度优先映射 frontier → 创建 map issue → 创建子票 → 第二遍连线 blocking → 启动 research 子 agent |
| **Work through** | 加载 map → 选 frontier 票 → assign 给自己 → 解决 → **resolution comment + close + 追加到 Decisions-so-far** → 新票/迷雾毕业 |
| **完成** | 所有子票 close = 路已清晰，map 交给 to-spec |

### 关键规则

- **每会话最多解决一张票**（research 除外）。
- 票通过 **assign** 占位，未 assign = 未认领。
- 答案**不写在票 body 里**，而是 resolution comment + map 索引行。
- 超出目的地的票 → **close + 记入 Out of scope**。

---

## 三、to-spec：综合成 spec

### 触发条件

- 对话已经讨论清楚 → `/to-spec`
- wayfinder map 已清空 → `/to-spec #<map_issue>`（把 map 作为输入）

### 做什么

1. 探索仓库，理解当前状态
2. 找出测试 seam（最高可能的 seam）
3. 写 spec（Problem / Solution / User Stories / Implementation Decisions / Testing Decisions / Out of Scope）
4. 发布到 tracker，打 `ready-for-agent` 标签

**关键**：to-spec 不采访用户，只综合已有上下文。

---

## 四、to-tickets：切分成实施票

### 触发条件

- 已有 spec（或计划/对话） → `/to-tickets`

### 做什么

1. 收集上下文（spec 路径 / issue 编号 / 对话）
2. 探索代码库（可选）
3. 切 **tracer-bullet 垂直切片**：
   - 每片贯穿 schema → API → UI → test
   - 每片可独立 demo
   - 每片能装进一个全新 context window
4. 用户 确认粒度与阻塞关系
5. 发布到 tracker

### 发布规则

- **有 blocker 的票** 等 blocker 全 close 后才进入 frontier
- **无 blocker 的票** 立即可以开始
- **打 `ready-for-agent` 标签**（默认）
- **不关闭、不修改父 issue**

### 宽重构例外

 mechanical 改动（改名、改类型）用 **expand → migrate（分批）→ contract** 序列，每批一票，共享 integration branch。

---

## 五、issue 自动化执行机制

### 核心问题：agent 怎么知道该干哪个？

**答案：不需要人为排序。** 依赖顺序由 **tracker 原生 blocking 关系**声明，"能不能抢"由 **`ready-for-agent` 标签**标记。

### 自动化领活流程

```
┌─────────────────────────────────────────────────────┐
│  人的介入点（3 个）                                    │
├─────────────────────────────────────────────────────┤
│  1. to-tickets 拆分后 → 人确认粒度/阻塞关系对不对     │
│  2. triage 时 → 人决定 ready-for-agent 还是 human     │
│  3. code-review → 人审 diff                          │
└─────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────┐
│  自动流转（agent 驱动）                               │
├─────────────────────────────────────────────────────┤
│  ready-for-agent → agent 抢 → implement → close     │
│  blocker close → 下游票解锁 → 新 frontier → 下一个    │
└─────────────────────────────────────────────────────┘
```

### agent 查询条件

```
label = ready-for-agent
AND state = open
AND 所有 blocker 已 closed
```

= **frontier**

### 领活步骤

1. 查 frontier
2. 领一张票（**assign 给自己** = 占位）
3. 实施（implement 技能：TDD → typecheck → test → code-review → commit）
4. close 票
5. 下一张票的 blocker 解除，自动进入 frontier

### 5 个 triage 标签

| 标签 | 含义 | agent 能抢吗 |
|---|---|---|
| `needs-triage` | 待评估 | ❌ |
| `needs-info` | 等信息 | ❌ |
| **`ready-for-agent`** | 完全就绪，AFK agent 可抢 | ✅ |
| `ready-for-human` | 需要人类实施 | ❌ |
| `wontfix` | 不做 | ❌ |

### 父票怎么关闭？

**父票不会因子票关闭而自动关闭。** 这是刻意设计。

| 技能 | 父票 | 关闭时机 |
|---|---|---|
| wayfinder | map issue | 所有决策票 close + Decisions-so-far 填满 → 人/agent 手动关 |
| to-tickets | spec issue | 所有实施票 close → 人/agent 手动关（to-tickets 明确说 "Do NOT close or modify any parent issue"） |

**核心设计哲学**：父票是"目的地"，子票是"步骤"。步骤完成 ≠ 到达目的地——父票的关闭永远是**独立的、有意识的动作**。

---

## 六、总结对比

| 维度 | wayfinder | to-spec | to-tickets |
|---|---|---|---|
| **输入** | 模糊的大目标 | map / 对话上下文 | spec / 计划 |
| **输出** | 决策地图（父 + 子决策票） | 一份 spec issue | 实施子票组 |
| **子票性质** | 决策（research/prototype/grilling/task） | — | tracer-bullet 垂直切片 |
| **子票间关系** | 原生 blocking | — | 原生 blocking |
| **父票关闭** | 人/agent 手动 | 人/agent 手动 | 人/agent 手动 |
| **是否自动关父票** | ❌ | ❌ | ❌ |
| **人介入点** | 确认 map 结构 | 确认 spec 内容 | 确认切片粒度 |
| **agent 自动领活** | ✅ research 票 | — | ✅ 所有实施票 |

---

## 七、设计哲学

1. **人定义"做什么"和"切片"**，agent 负责"按依赖顺序逐个执行"
2. **顺序不是人手动排的**，是 blocker 关系自动推导的
3. **父票关闭是独立动作**，不委托给 tracker 自动联动
4. **implement 故意极简**——没有"先做 A 再做 B"，因为顺序已经在 blocker 里
5. **`ready-for-agent` 是闸门**——只有打了这个标签的票 agent 才会自动领
