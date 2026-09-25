# scripts/ 目录须知

## OVERVIEW

本目录是模板源：4 个受管脚本 `pr-automation.sh` / `cw-update.sh` / `cw-evidence.sh` / `cw-greploop.sh` 都装到消费仓的 `scripts/`，清单唯一定义在 `../lib/render.sh:153` 的 `cw_list_files`。改这里的文件即改变所有消费仓的安装产物。

## 文件与职责

### pr-automation.sh（357 行）

G2 提交/PR 机械流水线。仓库内无 shell 调用它，仅被 `../skills/change-workflow/SKILL.md` 在 G2 文档化调用。

- 显式白名单提交：只提交 `--files` 指定路径，禁止 `git add -A`（`:259`）。`--files` 之外的改动（含 untracked）拒绝并退 1（`:204-206`、`:213-216`）。
- `--refs-only`：commit message 用 `refs #N`（`:266`），PR body 用 `Refs #N`（`:283`）。用于 parent/spec issue，防合并提前关闭。
- 分支绝不复用（`:30`）；分支名 `feat/<slug>` / `fix/<slug>`，基于 `origin/main`（`:30-31`）。
- risk-low 且 auto-merge 不可用 → fail-open 退 0（`:13`、`:348-351`）。
- 四件套门禁函数 `run_gate`（`:111`）；`--skip-checks` 是逃生舱，`../skills/change-workflow/SKILL.md:189` 明确禁止。

### cw-update.sh（129 行）

消费仓自升级壳。

- 读消费仓 conf 的 `TOOLKIT_SOURCE`（`:93`）。
- 缓存目录优先级：`CHANGE_WORKFLOW_HOME` > `~/.change-workflow` > `~/.cache/change-workflow`（`:21-27`）。
- 缓存已存在则 `git pull --ff-only`，否则 `git clone`（`:114-122`）。
- `exec` 缓存副本的 `update.sh`（`:126`/`:128`），退出码透传；`--target` 之外的参数原样转发。
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

退出码硬约束：`--help` 退出码是 1（`usage()` 末尾 `exit 1`，`pr-automation.sh:106-108`），不是 0。

其余 3 个包装脚本的退出码契约（0/1/3）：

| 脚本 | 0 | 1 | 3 |
|---|---|---|---|
| `cw-evidence.sh` | doctor/headless/`--help` 正常完成（`:422/:425/:426`） | 空/未知子命令（`:427-434`） | 依赖缺失降级：start/stop 显式 `|| exit $?`（`:423-424`），不依赖 `set -e` 的边角语义（`:389`） |
| `cw-greploop.sh` | 能力检测通过、协议已打印（`:357`/`:378`） | 参数错误（`:115`） | 依赖缺失降级（`:361`/`:381`） |
| `cw-update.sh` | `--help`/`-h`（`:37`） | 目标不存在/非 git 仓（`:42-43`/`:48`） | —（`exec` 透传 `update.sh` 退出码，`:126`/`:128`） |

3 是「降级未录制/未审查」的显式信号，不是失败：调用方（SKILL.md 编排）据此决定是否升级用户。

## 共享 helper（lib/render.sh）

4 个脚本装到消费仓后**不依赖 `lib/`**，但 conf 读取与写入面共用 `../lib/render.sh` 的同一批 helper —— 改这些 helper 必须四脚本一起看：

- `cw_refuse_symlink`（`../lib/render.sh:62`）：所有受管写入面（渲染重定向、`cp` 安装、manifest/conf 重写）必须先过这道闸，拒绝符号链接目标（C2 安全边界）。使用点：渲染目标 `:103`、cp 源/目标 `:175-176`、受管脚本 `:201`；`update.sh:132`/`:194`/`:258-259`/`:458-459`、`setup.sh:146`/`:221`。
- `cw_atomic_cp`（`:173`）/ `cw_chmod_scripts`（`:196`）：安装原子性与执行位（见下方修改清单第 4 条）。
- `cw_conf_get`（`:226`）：**B1 安全边界** —— 替代 `source "$CONF"`，杜绝值内命令注入（`:213`）。语义：跳过注释行、取首个 `key=` 后引号剥离的值、键不存在返 1；**不能截断含空格值**（如 `SKILLS_DIR="My Skills"`）。
- **`conf_get` 是刻意重复的独立副本**：`cw-greploop.sh:52` 与 `cw-update.sh:60` 各有一份（消费仓无 `lib/`，不能 source）。改 conf 读取逻辑 = `render.sh:226` + 这两处**三处一起改**，漏一处即行为漂移。
- **不 source conf（B1/RCE 边界）**：`cw-evidence.sh:45`/`:68`、`cw-greploop.sh:40`、`cw-update.sh:50`、`pr-automation.sh:42` 均显式「不 source conf」——全部改为白名单逐键解析（`conf_get`）；conf 提交进消费仓且不受管，source 即 RCE。

## 修改清单（新增/改动脚本必须连带）

1. 新增/删除受管脚本 → 改 `../lib/render.sh:153` 的 `cw_list_files`。
2. 同步 `../test/install-update-e2e.sh`：脚本语法检查循环（`:216`）与 Python 裸 `$VAR` 检查列表（`:223`）—— **新增任何脚本（含测试侧）都要加进这两处**：本仓的「`$VAR` 紧邻全角字符」陷阱只有这里拦得住（1.2.1 的 `test/rollout-check.sh` 与 `update.sh` 守卫都曾踩中）。
3. 同步 `../.github/workflows/ci.yml` 的脚本清单（`:21`、`:35`、`:43` 三处）。
4. 执行位：`cw_render` 用重定向写文件，装出来的新文件不带执行位；`../setup.sh` 与 `../update.sh`（两条更新路径）在渲染后**从 `cw_list_files` 派生**对 `scripts/*.sh` 统一 `chmod +x`（1.3.0 修复：清单即名单）。新增受管脚本只要进了 `cw_list_files` 就自动获得执行位，**不需要再登记第二份 chmod 名单** —— 硬编码名单曾两次漏加（1.2.0 与 1.3.0 均致消费仓 `./scripts/<name>.sh` 报 Permission denied），这正是「清单派生」要消灭的缺陷类；回归锁在 `../test/install-update-e2e.sh` 用例 1 的新增脚本 x 位断言。
5. 行为变更 → 同步 `../VERSION` + `../CHANGELOG.md` 并发版。

## 本目录特有约定

- `pr-automation.sh` 白名单路径若被 .gitignore 匹配，`git add` 失败后自动 fallback 到 `git add -f`（`:259-261`）；路径已由 `--files` 显式限定，不违反白名单原则。
- `pr-automation.sh` 从头模式要求无已跟踪未提交改动（`:222-227`）；resume 模式允许脏工作区，但必须配 `--files`（`:210-220`）。
- 4 个脚本的 `--help` 语义：`pr-automation.sh --help` 退 1，其余 3 个（`cw-update.sh` / `cw-evidence.sh` / `cw-greploop.sh`）均退 0（`cw-update.sh:35-37`）。
- `cw-update.sh` 除 `--target`、`--help` 外的参数原样转发给 `update.sh`（`:38`）。
