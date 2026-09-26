# 安装指南

## 前置

```bash
gh --version && gh auth status     # 需已登录，且有 repo 权限
git --version
python3 --version                  # 看板字段发现用
openspec --version                 # 可选
```

CI 合并信号需要 Actions 写权限：**Settings → Actions → General → Workflow permissions → Read and write**。

## 一键安装

```bash
cd /path/to/your-project
/path/to/change-workflow/setup.sh --target . --yes
```

`setup.sh` 会：

1. 检测仓库（`gh repo view`）与默认分支
2. 发现 Project V2 看板 + Status 字段/选项 ID（GraphQL；无看板则留空，稍后手填）
3. 创建标签（canonical triage + risk-* + ai-generated + change-close-pending + 模块）
4. 询问质量门禁命令（typecheck/lint/test/e2e，带默认）
5. 写 `.change-workflow.conf`
6. 拷贝 skill / 脚本 / workflow / 规范模板（替换 `{{REPO}}` 等占位符；已存在则跳过）
7. 在 `AGENTS.md` 追加索引段（若存在且未索引）

### 选项

| 参数 | 说明 |
|---|---|
| `--target <dir>` | 目标项目目录（默认当前目录） |
| `--yes` | 非交互，全部用默认值 |
| `--dry-run` | 只打印将执行的动作，不落盘 |

**幂等**：可重复运行；已存在的文件跳过、标签 `--force` 覆盖。

## 安装后

```bash
# 1. 检查配置（尤其看板 ID）
cat .change-workflow.conf

# 2. 若 PROJECT_ID/OPT_* 为空——手动补（或创建看板后重跑 setup.sh）
#    发现命令：
gh project list --owner <OWNER> --format json

# 3. 提交并开 PR：只显式添加安装触碰的受管文件 + AGENTS.md（索引段，仅首装追加）+ conf/manifest（禁 git add -A，白名单约定）
git add <受管文件…> AGENTS.md .change-workflow.conf .change-workflow.manifest
git commit -m "chore: adopt change-workflow"
git push -u origin <branch> && gh pr create
```

## 验证（首个子票即验证全流程）

1. 提一个需求 → 让 agent 走 `change-workflow`（G0）：产出 spec issue + change artifacts + 子票（Parent=spec issue）
2. 子票实施 → 独立分支 → `pr-automation.sh --resume-branch` 收口 PR（1 issue = 1 PR）
3. PR 合并 → 子票自动关闭 → 会话启动消费 `change-close-pending` → 自动 G4

## 升级（已有安装的仓库）

工具包演进时用 `update.sh` 升级。**不会覆盖你的本地修改**。

```bash
# 查版本（不落盘）
/path/to/change-workflow/update.sh --check

# 预览动作（不落盘）
/path/to/change-workflow/update.sh --dry-run

# 执行
/path/to/change-workflow/update.sh
git diff
# 只显式添加升级触碰的受管文件 + conf/manifest（禁 git add -A，白名单约定）
git add <升级触碰的受管文件…> .change-workflow.conf .change-workflow.manifest
git commit -m "chore(change-workflow): 升级到 x.y.z"
```

### 选项

| 参数 | 说明 |
|---|---|
| `--target <dir>` | 目标项目目录（默认当前目录） |
| `--check` | 仅比对版本，不落盘 |
| `--dry-run` | 只打印将执行的动作，不落盘 |
| `--force` | 忽略本地改动强制覆盖（覆盖前备份 `.bak`） |
| `--adopt` | 强制进入接管模式（见下） |

### 从 1.0.0 升级（无基线记录的既有安装）

1.0.0 时代的 `setup.sh` **不写 `.change-workflow.manifest`**，因此无法区分「文件未改」与「被本地改过」。`update.sh` 会**自动检测**此情形并进入**接管模式**：

1. 逐个比对当前文件与新版模板
2. **一致** → 直接接管（记为新基线）
3. **不同** → 新版本写入 `<file>.new`，**当前内容被接管为新基线**（不静默覆盖）
4. **文件不存在** → 按新增安装
5. 写 manifest + 更新 `TOOLKIT_VERSION`

```bash
# 直接运行即可，会自动进入接管模式
/path/to/change-workflow/update.sh

# 完成后三选一：
diff <file> <file>.new      # a. 人工核对并合并需要的部分，然后删 .new
/path/to/update.sh --force  # b. 全部采用新版本（先备份 .bak）
rm <file>.new               # c. 全部保留现状（基线已接管，无需其它操作）
```

> 接管后 manifest 已就位，**后续升级恢复正常语义**（只把「新增的本地改动」判为冲突）。

### 冲突保护

安装/升级时把每个受管文件的 sha256 记入 `.change-workflow.manifest`。升级时按基线判定：

| 目标文件状态 | 动作 | 退出码 |
|---|---|---|
| 本地未修改 | 覆盖（备份 `.bak`，升级收尾清理） | 0 |
| 本地已修改 | **不覆盖**；写 `<file>.new` + 列出清单 | **1** |
| 文件不存在 | 直接安装（新增规范） | 0 |

冲突文件**保留旧基线**，因此在你解决前每次升级都会继续报告（不会被静默接受为正典）。

**处理方式三选一**：

```bash
diff <file> <file>.new      # 1. 人工合并：以 .new 为参考改 <file>，然后删 .new
mv <file>.new <file>        # 2. 放弃本地改动，采用新版本
/path/to/update.sh --force  # 3. 强制覆盖全部冲突（备份 .bak 保留）
```

### 受管文件

`SKILL.md` / `pr-automation.sh` / `cw-update.sh` / `cw-evidence.sh` / `cw-greploop.sh` / `cw-tickets-check.sh` / `decisions-log.sh` / `change-closure-signal.yml` / `docs/agents/*.md`（12 份）。
**不受管**（升级不会触碰）：`.change-workflow.conf`、`AGENTS.md` 中的索引段、你新增的其它文档与脚本。

> 注：`AGENTS.md` 的索引段只在首次安装时追加；升级不会重复追加，新增的门禁段落需人工补（参考工具包 `setup.sh` 中的 heredoc 内容）。

## 手动安装（不用 setup.sh）

> ⚠️ **本工具包自身不是自己的消费者。** `--target` 指向工具包源目录会被 `setup.sh` /
> `update.sh` 直接拒绝：20 个受管文件里 18 个的模板源与安装目标同路径，渲染会先截断再
> 读取 → 清空模板。下面的手动安装同样**不适用于自我安装**（步骤 2 是同路径 `cp`，步骤 4
> 是同文件渲染）。在本仓开发时，流程依据直接读 `docs/agents/` 与
> `skills/change-workflow/SKILL.md` 即可。

1. 复制 `skills/change-workflow/` → `<SKILLS_DIR>/change-workflow/`
2. 复制 `scripts/pr-automation.sh` → `scripts/`（`chmod +x`）
3. 复制 `workflows/change-closure-signal.yml` → `.github/workflows/`
4. 复制 `docs/agents/*.md` → `<DOCS_DIR>/`（**剥离首部 `<!-- change-workflow 工具包模板 ... -->` 注释**，替换 `{{...}}` 占位符）
5. 复制 `config.example.conf` → `.change-workflow.conf` 并填值（含 `TOOLKIT_VERSION`）
6. 在 `AGENTS.md` 索引 change-workflow 与 quality-gates
7. 生成基线：安装后执行 `shasum -a 256 <各受管文件>` 写入 `.change-workflow.manifest`

> 手动安装需自行完成 4/5/7 三步（`setup.sh` 会自动做），否则 `update.sh` 会因缺基线而保守跳过。

## 目录约定（可在 conf 中改）

| 变量 | 默认 | 含义 |
|---|---|---|
| `SKILLS_DIR` | `.opencode/skills` | skill 安装目录 |
| `DOCS_DIR` | `docs/agents` | 规范文档目录 |
| `DEFAULT_BRANCH` | `main` | PR base / 分支基点 |

## 卸载

删除 `.change-workflow.conf`、`<SKILLS_DIR>/change-workflow/`、`scripts/pr-automation.sh`、`.github/workflows/change-closure-signal.yml`、`<DOCS_DIR>/` 下由本工具包安装的文档即可（标签可保留，无害）。
