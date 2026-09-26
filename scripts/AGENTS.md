# scripts/ 目录须知

## OVERVIEW

本目录是模板源：6 个受管脚本 `pr-automation.sh` / `cw-update.sh` / `cw-evidence.sh` / `cw-greploop.sh` / `cw-tickets-check.sh` / `decisions-log.sh` 都装到消费仓的 `scripts/`，清单唯一定义在 `../lib/render.sh:153` 的 `cw_list_files`。改这里的文件即改变所有消费仓的安装产物。

## 文件与职责

### pr-automation.sh（397 行）

G2 提交/PR 机械流水线。仓库内无 shell 调用它，仅被 `../skills/change-workflow/SKILL.md` 在 G2 文档化调用。

- 显式白名单提交：只提交 `--files` 指定路径，禁止 `git add -A`（`:296`）。`--files` 之外的改动（含 untracked）拒绝并退 1（`:240-244`、`:249-254`）。
- `--refs-only`：commit message 用 `refs #N`（`:303`），PR body 用 `Refs #N`（`:320`）。用于 parent/spec issue，防合并提前关闭。
- 分支绝不复用（`:31`）；分支名 `feat/<slug>` / `fix/<slug>`，基于 `origin/main`（`:31-32`）。
- risk-low 且 auto-merge 不可用 → fail-open 退 0（`:13`、`:388-392`）。
- 四件套门禁函数 `run_gate`（`:112`）；`--skip-checks` 是逃生舱，`../skills/change-workflow/SKILL.md:190` 明确禁止。
- `--verified-sha`（仅 `--resume-branch` 生效）：QG-5 验证时效检查——与分支 HEAD 不一致（rebase / 追加提交后未重验）→ 拒收退 1；未提供仅警告（降级不阻塞）。检查块 `:156-189` 置于 gh 前置校验之前：纯本地判定（`git rev-parse`），不依赖网络/凭证。

### cw-update.sh（129 行）

消费仓自升级壳。

- 读消费仓 conf 的 `TOOLKIT_SOURCE`（`:93`）。
- 缓存目录优先级：`CHANGE_WORKFLOW_HOME` > `~/.change-workflow` > `~/.cache/change-workflow`（`:21-27`）。
- 缓存已存在则 `git pull --ff-only`，否则 `git clone`（`:114-122`）。
- `exec` 缓存副本的 `update.sh`（`:126`/`:128`），退出码透传；`--target` 之外的参数原样转发。
- 退出码语义继承 `update.sh`：1 表示有冲突，是正常语义，不是失败。

### cw-tickets-check.sh（733 行）

G0-POST 拆票自检——发布前门禁（quiz 人工确认退役后的替代机制；把原手写对账命令脚本化）。

- 草稿模式（默认）：校验 `.tickets-draft/<change>/` 下的票面草稿（每票一文件：标题 `[change=<名>/<task号>]` + 七字段）——C1 对账双射 / C2 七字段 / C3 QG-1 形态 / C4 禁入信号 / C5 Blocked by DAG（越界/自环/环）/ C6 豁免显式 / C7 规模钩子 / C8 粒度声明 + 票间 `What` 重叠（阈值常量 `OVERLAP_THRESHOLD_PCT=80`）。
- `--live`：以 `gh issue list --state all` 对账已发子票（仅 C1）；与 `--drafts` 互斥。
- 退出码：0 = 全部通过（含 `--help`）；1 = 违规或用法错误。python3 缺失 → fail-closed 退 1。
- 契约锁：`../test/install-update-e2e.sh` 用例 23（含 gh 桩的 live 测试）；判据映射与设计说明见脚本头注。

### decisions-log.sh（157 行）

G3 决策日志追加器（pstack P0 反哺）：隔夜/无人值守的 frontier 循环每票写一行 TSV（时间/阶段/决策/理由/证据指针/结果），作为可审计轨迹（跨会话收尾只有 change-close-pending 信号，审计决策本身原本无迹可循）。

- 子命令：`add <阶段> <决策> <理由> <证据指针> <结果>`（恰 5 个非空参数；首写建 TSV 头）/ `show [N]`（N = 最近 N 行；无文件退 0）/ `path` / `--help`。
- 路径解析：`--file <路径>`（全局标志，任意位置） > `DECISIONS_LOG` 环境变量 > 默认 `./.artifacts/decisions.tsv`（**cwd 相对，不 cd 脚本父目录**）。默认不入库——运行记录不是交付物；需要留档的项目自行指向入库路径。
- 字段消毒（与上游 pstack `show-me-your-work/scripts/log.sh` 逐语义对齐，改语义须同步上游）：tab/换行/CR 折为空格（保 TSV 单行结构）；首字符 `= + - @` 前缀 `'`（防表格公式注入——决策文本/证据指针来自外部输入）。
- 退出码：0 = 成功（含 `--help` / `show` 无文件 / `path`）；1 = 用法或参数错误。
- 契约锁：`../test/install-update-e2e.sh` 用例 24；挂载点：`../skills/change-workflow/SKILL.md` G3（每票收尾一行）。

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
| `--verified-sha <sha>` | 仅 `--resume-branch`；QG-5 验证时效检查（不符退 1；未提供仅警告） |
| `--list-ready` | 列出 ready-for-agent 的 open issue |
| `--help` | 打印用法 |

退出码硬约束：`--help` 退出码是 1（`usage()` 末尾 `exit 1`，`pr-automation.sh:107-109`），不是 0。

其余 4 个包装脚本的退出码契约（0/1；3 = 降级）：

| 脚本 | 0 | 1 | 3 |
|---|---|---|---|
| `cw-evidence.sh` | doctor/headless/`--help` 正常完成（`:422/:425/:426`） | 空/未知子命令（`:427-434`） | 依赖缺失降级：start/stop 显式 `|| exit $?`（`:423-424`），不依赖 `set -e` 的边角语义（`:389`） |
| `cw-greploop.sh` | 能力检测通过、协议已打印（`:357`/`:378`） | 参数错误（`:115`） | 依赖缺失降级（`:361`/`:381`） |
| `cw-update.sh` | `--help`/`-h`（`:37`） | 目标不存在/非 git 仓（`:42-43`/`:48`） | —（`exec` 透传 `update.sh` 退出码，`:126`/`:128`） |
| `decisions-log.sh` | `add` / `show` / `path` / `--help` 正常完成（`show` 无文件退 0） | 用法或参数错误（`:59-71`、`:146-153`） | —（无降级路径） |

3 是「降级未录制/未审查」的显式信号，不是失败：调用方（SKILL.md 编排）据此决定是否升级用户。

## 共享 helper（lib/render.sh）

6 个脚本装到消费仓后**不依赖 `lib/`**，但 conf 读取与写入面共用 `../lib/render.sh` 的同一批 helper —— 改这些 helper 必须连带全部消费侧副本一起看：

- `cw_refuse_symlink`（`../lib/render.sh:62`）：所有受管写入面（渲染重定向、`cp` 安装、manifest/conf 重写）必须先过这道闸，拒绝符号链接目标（C2 安全边界）。使用点：渲染目标 `:103`、cp 源/目标 `:177-178`、受管脚本 `:203`；`update.sh:132`/`:194`/`:258-259`/`:458-459`、`setup.sh:146`/`:221`。
- `cw_atomic_cp`（`:175`）/ `cw_chmod_scripts`（`:198`）：安装原子性与执行位（见下方修改清单第 4 条）。
- `cw_conf_get`（`:228`）：**B1 安全边界** —— 替代 `source "$CONF"`，杜绝值内命令注入（`:215`）。语义：跳过注释行、取首个 `key=` 后引号剥离的值、键不存在返 1；**不能截断含空格值**（如 `SKILLS_DIR="My Skills"`）。
- **`conf_get` 是刻意重复的独立副本**：`cw-greploop.sh:52` 与 `cw-update.sh:60` 各有一份（消费仓无 `lib/`，不能 source）。改 conf 读取逻辑 = `render.sh:228` + 这两处**三处一起改**，漏一处即行为漂移。
- **不 source conf（B1/RCE 边界）**：`cw-evidence.sh:45`/`:68`、`cw-greploop.sh:40`、`cw-update.sh:50`、`pr-automation.sh:43` 均显式「不 source conf」——全部改为白名单逐键解析（`conf_get`）；conf 提交进消费仓且不受管，source 即 RCE。

## 修改清单（新增/改动脚本必须连带）

1. 新增/删除受管脚本 → 改 `../lib/render.sh:153` 的 `cw_list_files`。
2. 测试侧语法检查与裸 `$VAR` 清单已改为 `scripts/*.sh` glob（`../test/install-update-e2e.sh` 用例 9），新增脚本**自动纳入**，无需手工登记——本仓的「`$VAR` 紧邻全角字符」陷阱由这组检查拦截（1.2.1 的 `test/rollout-check.sh` 与 `update.sh` 守卫都曾踩中）。
3. `../.github/workflows/ci.yml` 三处脚本清单（`:21`、`:35`、`:43`）同为 `scripts/*.sh` glob，新增脚本自动纳入，无需手改。
4. 执行位：`cw_render` 用重定向写文件，装出来的新文件不带执行位；`../setup.sh` 与 `../update.sh`（两条更新路径）在渲染后**从 `cw_list_files` 派生**对 `scripts/*.sh` 统一 `chmod +x`（1.3.0 修复：清单即名单）。新增受管脚本只要进了 `cw_list_files` 就自动获得执行位，**不需要再登记第二份 chmod 名单** —— 硬编码名单曾两次漏加（1.2.0 与 1.3.0 均致消费仓 `./scripts/<name>.sh` 报 Permission denied），这正是「清单派生」要消灭的缺陷类；回归锁在 `../test/install-update-e2e.sh` 用例 1 的新增脚本 x 位断言。
5. 行为变更 → 同步 `../VERSION` + `../CHANGELOG.md` 并发版。

## 本目录特有约定

- `pr-automation.sh` 白名单路径若被 .gitignore 匹配，`git add` 失败后自动 fallback 到 `git add -f`（`:296-299`）；路径已由 `--files` 显式限定，不违反白名单原则。
- `pr-automation.sh` 从头模式要求无已跟踪未提交改动（`:259-265`）；resume 模式允许脏工作区，但必须配 `--files`（`:247-257`）。
- 6 个脚本的 `--help` 语义：`pr-automation.sh --help` 退 1，其余 5 个（`cw-update.sh` / `cw-evidence.sh` / `cw-greploop.sh` / `cw-tickets-check.sh` / `decisions-log.sh`）均退 0（`cw-update.sh:35-37`）。
- `cw-update.sh` 除 `--target`、`--help` 外的参数原样转发给 `update.sh`（`:38`）。
