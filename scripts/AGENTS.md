# scripts/ 目录须知

## OVERVIEW

本目录是模板源：`pr-automation.sh` 与 `cw-update.sh` 都作为受管文件装到消费仓的 `scripts/`，清单唯一定义在 `../lib/render.sh:71` 的 `cw_list_files`。改这里的文件即改变所有消费仓的安装产物。

## 文件与职责

### pr-automation.sh（308 行）

G2 提交/PR 机械流水线。仓库内无 shell 调用它，仅被 `../skills/change-workflow/SKILL.md` 在 G2 文档化调用。

- 显式白名单提交：只提交 `--files` 指定路径，禁止 `git add -A`（`:173`）。`--files` 之外的改动（含 untracked）拒绝并退 1（`:154-158`、`:165-167`）。
- `--refs-only`：commit message 用 `refs #N`（`:217`），PR body 用 `Refs #N`（`:234`）。用于 parent/spec issue，防合并提前关闭。
- 分支绝不复用（`:30`）；分支名 `feat/<slug>` / `fix/<slug>`，基于 `origin/main`（`:30-31`）。
- risk-low 且 auto-merge 不可用 → fail-open 退 0（`:13`、`:301-303`）。
- 四件套门禁函数 `run_gate`（`:62`）；`--skip-checks` 是逃生舱，`../skills/change-workflow/SKILL.md:181` 明确禁止。

### cw-update.sh（71 行）

消费仓自升级壳。

- 读消费仓 conf 的 `TOOLKIT_SOURCE`（`:52`）。
- 缓存目录优先级：`CHANGE_WORKFLOW_HOME` > `~/.change-workflow` > `~/.cache/change-workflow`（`:20-26`）。
- 缓存已存在则 `git pull --ff-only`，否则 `git clone`（`:56-64`）。
- `exec` 缓存副本的 `update.sh`（`:68`/`:70`），退出码透传；`--target` 之外的参数原样转发。
- 退出码语义继承 `update.sh`：1 表示有冲突，是正常语义，不是失败。

## 参数与退出码

pr-automation.sh 参数表：

| 参数 | 说明 |
|---|---|
| `--role feat\|fix` | 必填，缺则退 1 |
| `--issue <N>` | 必填 |
| `--title` | commit/PR 标题 |
| `--risk low\|medium\|high` | 默认 medium；驱动风险标签与 auto-merge |
| `--slug` | 分支 slug；缺省从 issue title 生成 |
| `--resume-branch <branch>` | resume 模式：分支已由 G1 创建，跳过建分支 |
| `--files <path>` | 白名单路径，可重复，配 `--` 使用 |
| `--refs-only` | 关联用 refs，不用 fixes/Closes |
| `--skip-checks` | 跳过本地四件套（逃生舱，禁止） |
| `--list-ready` | 列出 ready-for-agent 的 open issue |
| `--help` | 打印用法 |

退出码硬约束：`--help` 退出码是 1（`usage()` 末尾 `exit 1`，`pr-automation.sh:57-59`），不是 0。

## 修改清单（新增/改动脚本必须连带）

1. 新增/删除受管脚本 → 改 `../lib/render.sh:71` 的 `cw_list_files`。
2. 同步 `../test/install-update-e2e.sh`：脚本语法检查循环（约 `:191`）与 Python 裸 `$VAR` 检查列表（约 `:198`）。
3. 同步 `../.github/workflows/ci.yml` 的脚本清单（`:21`、`:33`、`:41` 三处）。
4. 执行位：`cw_render` 用重定向写文件，装出来的新文件不带执行位；`../update.sh:193-196` 与 `:329-332`、`../setup.sh:165` 在渲染后统一 `chmod +x`。新增受管脚本必须加进该 chmod 列表，否则消费仓 `./scripts/<name>.sh` 报 Permission denied（1.2.0 真实缺陷）。
5. 行为变更 → 同步 `../VERSION` + `../CHANGELOG.md` 并发版。

## 本目录特有约定

- `pr-automation.sh` 白名单路径若被 .gitignore 匹配，`git add` 失败后自动 fallback 到 `git add -f`（`:210-213`）；路径已由 `--files` 显式限定，不违反白名单原则。
- `pr-automation.sh` 从头模式要求无已跟踪未提交改动（`:174-179`）；resume 模式允许脏工作区，但必须配 `--files`（`:163-171`）。
- 两脚本 `--help` 行为相反：`pr-automation.sh --help` 退 1，`cw-update.sh --help` 退 0（`cw-update.sh:34-36`）。
- `cw-update.sh` 除 `--target`、`--help` 外的参数原样转发给 `update.sh`（`:37`）。
