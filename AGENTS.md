# PROJECT KNOWLEDGE BASE

**Generated:** 2026-09-22
**Commit:** 05b47a2
**Branch:** main
**语言**：本仓库全部注释/文档/commit/回复用户均用中文（de facto，无显式声明处）

## OVERVIEW

bash 工具包（无编译、无运行时依赖，需 `bash` + `gh` + `git` + `python3`）：把 agent 的**变更生命周期**编码为 G0-G4 强制 gate + fix-first 自愈回路，安装到任意 GitHub 仓库。
本仓是**工具包源**；它的产物是「装进消费仓的 20 个受管文件」，不是可运行的 app。

消费仓：`md-bundle`（含架构图 `docs/diagrams/change-workflow.architecture.html`）、`mdpkg`、`clairis`。

## STRUCTURE

```
change-workflow/
├── AGENTS.md                 # 本文件（根知识库）；子级：scripts/AGENTS.md、docs/agents/AGENTS.md
├── setup.sh                  # 首装向导：渲染安装 → 写 conf/manifest → 追加目标仓 AGENTS.md 索引段
├── update.sh                 # 升级向导 + 退出码契约主体（基线判定 → 覆盖/.new/LOCAL）
├── lib/render.sh             # 渲染唯一实现 + 受管文件清单（改受管面只改这里）
├── scripts/                  # 模板源 → 装到目标仓 scripts/
├── skills/change-workflow/   # 模板源 → 装到 <SKILLS_DIR>（默认 .opencode/skills）
├── docs/agents/              # 模板源 → 装到 <DOCS_DIR>（12 份规范）
├── workflows/                # 模板源 → 装到 .github/workflows/change-closure-signal.yml
├── test/install-update-e2e.sh # 25 用例 / 222 断言（CI 第 9 步全量跑；唯一权威验证）
├── test/rollout-check.sh     # 消费仓滚动验证（发布前本地门禁；CI 无消费仓检出，跑不了）
├── .opencode/                # openspec init 产物：6 个 opsx-* 命令 + 6 个 openspec-* 技能
├── openspec/                 # openspec 项目数据（config.yaml / changes / specs）
├── .github/workflows/ci.yml  # 本仓自身 CI（9 步）
├── config.example.conf       # conf 键值清单（不受管，升级不覆盖）
└── VERSION / CHANGELOG.md    # 发版必须同步的两处
```

**最易误解**：根级 `skills/`、`docs/agents/`、`workflows/` 是**模板源**，其安装目标在消费仓的 `.opencode/skills/`、`docs/agents/`、`.github/workflows/`。改这里的文件名/路径即改变消费仓布局。

## WHERE TO LOOK

| 任务 | 位置 | 备注 |
|---|---|---|
| 新增/删除受管文件 | `lib/render.sh:153` `cw_list_files` | 连带改：模板、`test` 计数断言；`ci.yml` 三处与 test 语法清单已为 `scripts/*.sh` glob（自动纳入），`rollout-check` 为动态计数无需改 |
| 新增占位符 | `lib/render.sh:29-46` | 替换表唯一位置；`ci.yml:55` 校验一致性 |
| 升级/冲突/基线语义 | `update.sh` | 语义教训见 `CHANGELOG.md:308-309` |
| 安装流程 | `setup.sh` | 与 update 共用 `lib/render.sh`，勿各写一套 |
| 门禁判据（票内容与完成） | `docs/agents/quality-gates.md` | QG-1..7 / DQ-1..8 单一事实来源 |
| gate 编排与外部 skill 调用 | `skills/change-workflow/SKILL.md` | |
| 设计理由（为什么这样约束） | `DESIGN.md:114-134` | |
| 受管/不受管边界 | `DESIGN.md:105`、`INSTALL.md:134-136` | |

## CODE MAP

LSP 不可用（bash server 未安装）、无 codegraph → 下表 Refs 为**文本引用次数**（近似热度，非调用图）。

| Symbol | Type | Location | Refs | Role |
|---|---|---|---|---|
| `cw_list_files` | fn | `lib/render.sh:153` | 11 | 20 个受管文件的**唯一清单**（8 硬编码 + 12 docs glob；globs 在 `:162-168`，跳过 `AGENTS.md`） |
| `cw_render` | fn | `lib/render.sh:90` | 11 | 模板 → 目标文件（剥头 + 替换占位符） |
| `cw_sha` | fn | `lib/render.sh:108` | 9 | sha256（macOS/Linux 双实现） |
| `cw_substitute` | fn | `lib/render.sh:29` | 2 | 占位符替换表 |
| `cw_strip_header` | fn | `lib/render.sh:50` | 2 | 剥 `<!-- change-workflow 工具包模板` 头 + 前导空行 |
| `cw_is_self_target` | fn | `lib/render.sh:143` | 3 | 目标仓 == 工具包源自身 → setup/update 拒绝（防自装清空模板）；`cw_render` 在 `:98` 另有一道同文件护栏 |
| `install_rendered` | fn | `setup.sh:184` | 2 | 首装渲染安装循环 |
| `toolkit_source` / `upsert_conf` | fn | `update.sh:177` / `:192` | 3 / 3 | conf 写 `TOOLKIT_SOURCE`（供项目自升级） |
| `is_in_list` | fn | `update.sh:168` | 3 | 数组遍历（**禁止 nameref** 的产物） |
| `baseline_of` / `is_conflicted` | fn | `update.sh:334` / `:444` | 2 / 2 | 基线查询 / 冲突文件跳过基线重写 |
| `needs_bootstrap` | fn | `update.sh:206` | 2 | 无基线 → 接管模式 |
| `validate_whitelist` / `in_files` | fn | `scripts/pr-automation.sh:225` / `:218` | 2 / 3 | G2 显式白名单（禁 `git add -A`） |
| `run_gate` / `usage` | fn | `scripts/pr-automation.sh:112` / `:107` | 4 / 7 | 四件套门禁 / 用法（**`--help` 退 1**） |

调用关系：`setup.sh`→source `lib/render.sh`(:19)；`update.sh`→source `lib/render.sh`(:28) + conf(:82-87)；`scripts/cw-update.sh`→读 conf(:93) → **exec** 缓存副本的 `update.sh`(:126/:128，退出码透传)；`pr-automation.sh` 与上述无 shell 关系，仅被 SKILL.md G2 文档化调用。

## CONVENTIONS

- **bash 3.2 兼容（硬）**：禁 `local -n`、`declare -A`、`mapfile`、`readarray`。CI 静态拦截在 `ci.yml:43`；`is_in_list` 曾因 `local -n` 静默失效（`CHANGELOG.md:401`）。
- **渲染幂等铁律**：`render(x) == x` 必须对未做替换的文件成立 —— `cw_render` 用 `awk print` **无条件补结尾换行**，故每个受管模板必须自身以换行结尾（`ci.yml:80` 门禁；`CHANGELOG.md:247-268` 是一次「接管模式永不归一」的真实事故）。任何「渲染改变字节」的路径都会伪装成「本地定制」。
- **模板头**：13 个模板（12 docs + SKILL.md）首行必须是 `<!-- change-workflow 工具包模板`，安装时剥除（`ci.yml:67`、`test:210`）。
- **模板内禁出现仓库特有值**：`jianxi-dev/md-bundle|mdpkg|clairis`、`/Users/mason`、`PVT_kwDO`、`PVTSSF_`（`ci.yml:92`）。
- **注释写「为什么 + 历史教训」**，不是复述代码；`quality-gates.md` 每条规则固定四段：规则 / **理由** / 实证案例 / 如何验证（`DESIGN.md:52`）。shellcheck 抑制必须附中文理由（`setup.sh:40`）。
- **输出格式**：`❌`+stderr+exit 1 错误；`⚠️` 警告；`==>` 进度（`log()`）；`[dry-run]` 预演标记；`✅` 成功。
- **缩进 2 空格，无 tab**；公共 helper `log`/`warn`/`act`/`ask`。
- **commit**：Conventional Commits 前缀 + **中文** 标题（如 `fix(update): 接管模式静默覆盖本地定制`）；升级/首装固定文案见 `README.md:96`、`INSTALL.md:53`。
- **发版**：`VERSION` + `CHANGELOG.md` 同步（每版结构：`### 新增/修复` → `### 教训反思` → `### 验证`（贴 e2e 通过数））→ tag → push。

## ANTI-PATTERNS (THIS PROJECT)

- **禁止把「当前内容哈希」记为基线**：基线只有一个含义 = 工具包上次写入的内容；「永不触碰」用 `LOCAL` 哨兵表达（`CHANGELOG.md:308-309`、`update.sh:118-122`）。混用会导致下次升级静默覆盖用户定制（1.1.5 真实损害）。
- **禁止覆盖本地已改文件**：写 `<file>.new` + exit 1（`update.sh:19`）。
- **禁止给接管模式下的「不同」文件写基线**：否则 `.new` 未处理就被冲掉（`update.sh:249-251`）。
- **禁止把 `LOCAL` 哨兵重写回真实哈希**（`update.sh:486-491`；`test:273/:280` 回归锁）。
- **禁止 `git reset --hard` / `git clean` / `git checkout -- <path>` 处理共享工作区**（`docs/agents/incident-uncommitted-work-loss.md:156-165`）；收尾后禁止切回任务前分支（`incident-merge-local-workspace.md:27-32`）。
- **门禁不可豁免项**：QG-3/4/5、DQ-1/2/3/4/5/8；可豁免的 QG-1/QG-2 必须**票作者显式声明**，不得默认（`quality-gates.md:328-343`）。
- 「测试通过」「已修复」「冒烟正常」是**结论不是证据**，不予采信（`quality-gates.md:321`）。
- **1 task = 1 ticket = 1 分支 = 1 PR**，分支绝不复用（`pr-automation.sh:31`）；N 票同根因才能 1 PR 关 N 票且须逐票 `fixes #N`（DQ-6）。parent = 源 spec issue，其 PR 必须 `--refs-only`（`Refs #N`）。
- 禁止 `pr-automation.sh --skip-checks`（逃生舱，`SKILL.md:190`）。
- **禁止 `--target` 指向工具包源自身**（自我安装）：20 个受管文件里 18 个的模板源与安装目标同路径，渲染会**先截断再读取 → 文件归零**（实测 11913 字节 → 0）。由 `cw_render:98` 与 `cw_is_self_target:143` 双重拒绝。**本仓不是自己的消费者** —— 流程依据直接读 `docs/agents/` 与 `skills/change-workflow/SKILL.md`。

## 本仓的开发方式（决策 2026-09-22）

**本仓不以消费仓身份跑 G0-G4。** 理由：G0-G4 的编排（issue / 看板 / 分支 / PR / frontier / 归档）是为「多票并行、跨会话推进」的**应用交付**设计的；而本仓的失败模式是「CI 绿但只在 macOS 炸」「渲染不幂等」这类**契约与回归**问题，防护重心在 `test/` + CI，不在票据仪式。本仓真正的 dogfooding 面是**三个消费仓的升级结果**。

替代纪律（轻量，零安装成本）：

1. **先红后绿**（DQ-3）：改行为先在 e2e 加断言、确认它红，再改到绿
2. **要原始证据**（QG-5）：不接受「测试通过 / 已修复」，贴命令输出
3. **发布前必跑** `test/rollout-check.sh`（消费侧契约：冲突 0 + LOCAL 哨兵完整 + 覆盖数一致）
4. 发布仍走 `VERSION` + `CHANGELOG`（`### 新增/修复` → `### 教训反思` → `### 验证`）+ tag
5. `openspec/` **只用于大重构的提案**（`/opsx-propose` → 归档进 `openspec/specs/`），不做日常流程

**何时才值得上 G0-G4**：多票并行 + 跨会话推进 / 出现第二个人或 agent 协同 / 对外开放贡献。

## COMMANDS

```bash
# 唯一权威验证：25 用例 / 222 断言（CI 第 9 步跑的就是它）
./test/install-update-e2e.sh

# 发布前本地门禁：本工具包 HEAD 装到每个消费仓都不冲突（CI 无消费仓检出，跑不了）
./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis

# 预演升级（不落盘），<dir> 为消费仓
./update.sh --target <dir> --check
./update.sh --target <dir> --dry-run

# 静态检查（本地 /bin/bash 即 3.2，能真跑到 3.2 路径）
for s in setup.sh update.sh lib/render.sh scripts/*.sh test/*.sh; do bash -n "$s" || echo "FAIL $s"; done
shellcheck --severity=warning -x setup.sh update.sh lib/render.sh scripts/*.sh test/*.sh

# 本地复现全部 CI 门禁（9 步逐条见 .github/workflows/ci.yml）
```

## NOTES

- **本机 `bash` 只有 `/bin/bash` = 3.2.57**（无 Homebrew bash）。CI runner 是 bash 5 → **3.2 问题在 CI 永远绿，只在 macOS 炸**，故 CI 的「bash 3.2 兼容性（静态）」与 e2e 的裸 `$VAR` 检查**不可删**。
- **三个已踩过的 shell 陷阱**（`test/install-update-e2e.sh` 内有对应写法）：
  1. `$VAR` 紧邻全角字符 → 被吞进变量名 → `unbound variable`（应写 `${VAR}）`）。测试断言在 `test:230-242`。
  2. `cmd | grep -q` 在 `set -o pipefail` 下：`grep -q` 命中即关管道 → 上游 SIGPIPE(141) → 判失败。改用 `case "$out" in *pat*`。
  3. `cmd; ok "$?"` 会被 `set -e` 在 `ok` 之前中止 → 必须 `rc=0; cmd || rc=$?`。
- **`update.sh` 退出码 1 是正常语义**（有冲突/有差异），不是失败；`cw-update.sh` 经 `exec` 继承。`pr-automation.sh --help` 也退 1。risk-low auto-merge 不可用时 **fail-open 退 0**。
- `.gitignore` 只忽略 `.omo/`（harness 产物）；`.opencode/` 与 `openspec/` **纳入版本控制**（与消费仓一致）。提交时仍只加目标文件，别用 `git add -A`。
- **版本一致性**：`VERSION` 是唯一源 —— 发版时 `CHANGELOG.md` 顶部条目与 `config.example.conf:12` 的 `TOOLKIT_VERSION` 必须同步。曾两次漂移（`1.1.0` 落后于 `1.2.0`；本行自己也过期过一次），改版本时三处一起看。
- 消费仓升级后**只提交工具包文件**（`scripts/cw-update.sh`、`.change-workflow.conf`、`.change-workflow.manifest`），勿碰其自身 WIP。
