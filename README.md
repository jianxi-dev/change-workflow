# change-workflow 工具包

一套让 **agent 按项目规范执行变更** 的自动化流程，可安装到任意 GitHub 仓库（OpenSpec 可选）。

## 解决什么问题

AI agent 常跳过工程规范：不建分支/issue 就开发、不拆票、误关子票、按过期规范操作、主 spec 提前同步、把真实回归误判为 flaky……本工具包把「变更生命周期」编码为**强制 gate + 自愈回路**，使 agent 每次变更都走同一条可审计的路径。

## 组成

| 文件 | 作用 |
|---|---|
| `skills/change-workflow/SKILL.md` | 总编排 skill：G0-G4 五 gate + fix-first 自愈回路 + 缺陷机制 |
| `scripts/pr-automation.sh` | issue 驱动分支/PR 自动化（`--resume-branch` 白名单收口、`--refs-only`、auto-merge fail-open） |
| `scripts/cw-update.sh` / `cw-evidence.sh` / `cw-greploop.sh` | 项目自升级 / G1 证据录制包装 / G2 Greptile 审查闭环包装（依赖缺失均降级） |
| `scripts/cw-tickets-check.sh` | G0-POST 拆票自检（C1-C8 机检：对账/字段/AC 形态/禁入信号/DAG/豁免/规模/粒度；`--live` 对账已发子票） |
| `workflows/change-closure-signal.yml` | CI 合并信号（Layer 1）：合并关闭 change 最后一张子票时打标 |
| `docs/agents/*.md` | **12 份规范模板**（task-tracking / **quality-gates** / issue-tracker / project-board / triage-labels / defect-workflow / domain / incident-uncommitted-work-loss / incident-merge-local-workspace / evidence-capture / code-structure / pr-writing） |
| `setup.sh` | 安装向导：检测仓库 → 发现看板 → 建标签 → 写配置 → 渲染安装 → 写基线 manifest → 更新 AGENTS.md |
| `update.sh` | **升级向导**：版本比对 → 基线哈希判定本地改动 → 安全覆盖 / 冲突旁路 → 刷新 manifest |
| `lib/render.sh` | 占位符替换与模板头剥离的**唯一实现**（setup/update 共用，防漂移） |
| `VERSION` / `CHANGELOG.md` | 工具包版本与变更历史 |
| `config.example.conf` | 参数化配置模板（看板 ID / 标签 / 门禁命令 / 目录约定） |

## 核心约定

- **1 task = 1 ticket = 1 分支 = 1 PR**（垂直切片，独立可评审/合并/回滚）；**N 票同根因/同文件**时允许 1 PR 关 N 票（DQ-6）
- **Parent = 源 spec issue**（不另建 change parent；G4 才关闭 spec issue）
- **`fixes #N`** → PR 合并自动关子票；**`Refs #N`** → 仅引用（parent/spec issue 用）
- **gate 失败 → fix-first 自愈**（自行修复，2 轮未通才升级用户）
- **合并 → CI 信号 → 会话启动消费 → 自动 G4 收尾**（跨会话自动化）
- **分支保护**：main 要求质量门禁 + 分支与 main 同步（strict）

## 质量门禁（QG / DQ）

`docs/agents/quality-gates.md` 是**票内容与完成判据**的单一事实来源，分两组：

- **QG-1..QG-7（变更开发侧）**：用户层 AC / e2e 绑定 / 接线归属 / 真实路径测试 / 独立验证+原始证据 / 集成 checkpoint / 纵向切片
- **DQ-1..DQ-8（缺陷处理侧）**：triage 不可跳过 / 根因独立确认 / 先红后绿 / flaky 须机制解释 / 关闭附原始证据 / 同根因合并例外 / 多票同根因→升级规范 / 生命周期标签维护

**最小充分集**：`QG-1 + QG-2 + QG-5`（拦截「功能不存在」）＋ `DQ-1 + DQ-3 + DQ-5`（拦截「假修复」）。

## 五个 gate

```
G0 启动   to-spec 归一化 → openspec-propose(切片) → to-tickets 拆票(Parent=spec issue) + 看板
G1 实施   建票级分支 → implement(内嵌 tdd) → 质量门禁 → code-review(+review)
G2 提交/PR pr-automation.sh --resume-branch 收口（1 issue = 1 PR，feat/fix 同 gate）
G3 收尾   learn → sync-gbrain → 对账 → frontier 自动推进下一张票（非阻塞）
G4 归档   全部合并 → validate --strict → archive → 看板 Done → 关闭 spec issue
```

## 前置依赖

### 工具
- `gh`（GitHub CLI，已 `gh auth login`）、`git`、`python3`
- 可选：`openspec` CLI（`OPENSPEC_ENABLED=false` 时降级，G0 阶段二 / G4 归档跳过）

### 依赖的 agent skills（本流程是**对它们的编排**，不重复实现其逻辑）
本工具包只定义「何时调用哪个 skill、如何衔接」，各 skill 的 `SKILL.md` 是其逻辑的**单一事实来源**：

| 来源 | 提供的 skills | 在流程中的角色 |
|---|---|---|
| **OpenSpec** | `openspec-propose` / `openspec-apply-change` / `openspec-sync-specs` / `openspec-archive-change` / `openspec-update-change` / `openspec-explore`（+ `openspec` CLI） | change 规划产物生成、实施指令流、主 spec 同步、归档 |
| **Real Engineers**（Matt Pocock 的 engineering skills） | `to-spec`（需求综合成规格票）/ `to-tickets`（垂直切片拆票）/ `triage`（缺陷状态机）/ `implement`（实施总编排）/ `tdd`（测试先行）/ `code-review`（Standards+Spec 双轴自审）/ `learn`（经验沉淀）；配置入口 `setup-matt-pocock-skills` | G0 归一化与拆票、G1 实施与出口自审、G3 沉淀 |
| **gstack** | `review`（pre-landing 结构审查）/ `sync-gbrain`（代码索引刷新）/ `browse` / `investigate` | G1 出口条件审查、G3 索引刷新 |
| **gbrain** | 知识库能力（`query` / `capture` 等） | 跨会话经验与代码检索（`sync-gbrain` 桥接 gstack ↔ gbrain） |

> **降级友好**：目标项目未安装上述 skill 时，流程仍可运行——对应环节降级为「agent 直接执行」；未装 `openspec` 时设 `OPENSPEC_ENABLED=false`。
> 集合归属以各 skill 自身 `SKILL.md` 的元数据为准。

## 安装

```bash
cd /path/to/your-project
/path/to/change-workflow/setup.sh --target . --yes
# 检查 .change-workflow.conf → 只显式 git add 安装触碰的文件 + AGENTS.md（索引段，仅首装追加）+ conf/manifest（禁 git add -A）→ 开 PR
```

## 升级（已有安装的仓库）

工具包会演进（新增门禁、修订规范、修复模板缺陷）。升级时**不覆盖你的本地修改**：

```bash
# 1. 先看有没有新版本（不落盘）
/path/to/change-workflow/update.sh --check

# 2. 预览将执行的动作（不落盘）
/path/to/change-workflow/update.sh --dry-run

# 3. 执行升级
/path/to/change-workflow/update.sh

# 4. 检查并提交：只显式添加升级触碰的受管文件 + conf/manifest（禁 git add -A，白名单约定）
git diff
git add <升级触碰的受管文件…> .change-workflow.conf .change-workflow.manifest
git commit -m "chore(change-workflow): 升级到 x.y.z"
```

**冲突保护机制**：安装/升级时会把每个受管文件的 sha256 记入 `.change-workflow.manifest`。升级时：

| 目标文件状态 | 动作 |
|---|---|
| 本地**未修改**（哈希 == 基线） | 安全覆盖（备份 `.bak`，升级收尾清理冗余副本） |
| 本地**已修改**（哈希 != 基线） | **不覆盖**，新版本写入 `<file>.new` 旁路文件，退出码 1 并列出清单 |
| 文件不存在（新增规范） | 直接安装 |

冲突处理三选一：人工合并 `diff <file> <file>.new` ／ 放弃本地改动 `mv <file>.new <file>` ／ 强制覆盖 `update.sh --force`（备份 `.bak` 保留：它是本地定制的唯一副本）。

详见 [INSTALL.md](INSTALL.md)；设计原理见 [DESIGN.md](DESIGN.md)。
