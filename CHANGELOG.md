## 1.3.1 — 2026-09-25

### 修复：安全边界（A1/B1/C2）

**问题**：三个「不可信输入」路径存在越权执行风险——仓库内候选 skill 根被自动执行
（A1）、conf 被 `source` 导致命令替换注入（B1）、符号链接目标被受管写入写穿（C2）。

**改进**：
- A1：`cw-evidence.sh` 默认跳过仓库级候选根，仅 `CW_EVIDENCE_ALLOW_REPO=1` 或
  `--skill-path` 显式信任才执行（RCE 信任边界）
- B1：`update.sh` / `cw-greploop.sh` / `cw-update.sh` 全部改为白名单 `conf_get()`
  只读键值，`source "$CONF"` 彻底移除（红证：恶意 conf 不再创建哨兵文件）
- C2：`cw_refuse_symlink`（`lib/render.sh:62`）覆盖全部受管写入面（渲染目标、cp 源/目标、
  manifest/conf 重写），`cw_atomic_cp`（`:173`）temp+mv 原子写，符号链接一律拒绝

### 修复：状态机与假绿（A2/B2/C1/C4/A3/B3）

**问题**：降级路径与成功不可区分（A2/B2）、首装渲染空值（C1）、`--force` 语义缺失（C4）、
平台分支不可达（A3）、`--vcs` 平台文本未区分（B3）。

**改进**：
- A2/B2：`cw-evidence.sh` 与 `cw-greploop.sh` 降级统一退 3（与成功 0、参数错误 1 可区分），
  `--pr` 经 `gh pr view` 校验不可解析退 1
- C1：`EFFECTIVE_DATE`/`REPO_ROOT` 在渲染循环前作为 shell 变量显式设置（heredoc 内赋值
  不进当前 shell 是根因），首装产物不再缺日期/仓库根路径
- C4：`LOCAL` 哨兵 + `--force` 覆盖语义（`.bak` 保留定制内容）
- A3：屏幕捕获不可用分支可达（stub 探针验证）
- B3：`--vcs github|gitlab|perforce` 三平台文本各不相同

### 修复：安装器健壮性（C3/D1/F1/F2/附带）

**问题**：并发锁缺失（C3）、特殊字符路径被展开（D1）、chmod 循环三处重复（F1）、
候选根清单两脚本漂移（F2）。

**改进**：
- C3：仓库级锁（`.git/.change-workflow.lock`，`--dry-run` 不取锁）、manifest 原子写、
  chmod 失败即失败（不再 `|| true` 吞错）
- D1：`REPO_ROOT` 含 `&`/`|`/`{{OWNER}}`/`$HOME` 全部字面输出
- F1：`cw_chmod_scripts`（`lib/render.sh:196`）抽公共，替换 3 处逐字节重复循环
- F2：9 个候选 skill 根清单两脚本逐字节一致（互指注释防漂移）

### 新增：e2e 回归锁（E1）

`test/install-update-e2e.sh` +70 行：case 8 补 3 个 exec 位断言、case 15 退出码契约
14 断言、case 16 符号链接拒绝 3 断言、case 17 受管脚本符号链接拒绝 5 断言（含执行位
写穿断言）。全部经变异验证（DQ-3 先红后绿）：变异 `cw_chmod_scripts` → 7 红、
变异 `cmd_start` 降级 → 1 红、变异共享守卫 `cw_refuse_symlink` → 4 红，字节级还原后
全绿。

### 修复：发布前审查续轮（安全收紧 + 正确性 + CI 信号）

**问题**：修复轮自身是最大新风险面——本轮审查修复战役（T1–T6，约 24 个提交）中，
前述三节修复落地后又经两轮对抗审查，从约 23 个修复里再找出 18 项：升级壳可被 conf
换源、manifest/conf **读取端**与写入端解析语义脱节、workflow 标签提取仍是旧管道 +
source 语义。

**改进**：
- 安全：`cw-update.sh` 的 `TOOLKIT_SOURCE` 加信任门（非默认源须显式授权或与既有缓存
  来源一致，否则拒绝）；`cw_refuse_symlink` 对相对路径逐级检查组件（防父目录符号链接
  写穿）；`change-closure-signal.yml` 与 `pr-automation.sh` 去 `source` conf 改白名单
  提取（parse-time 命令替换注入收口）
- 正确性：受管写入面模式保持全覆盖（mktemp 恒 0600 → mv 前调回应有模式）；manifest
  读取兼容空格路径 / CRLF / 反斜杠（awk 经 ENVIRON 传路径字面量）；LOCAL 哨兵生命周期
  补全（`--force` 归一「内容已等于上游」文件的哨兵 + 「本地保留」计数与 manifest 的
  LOCAL 行数一致，恢复 rollout-check 发布契约）；四份 conf 解析器（`cw_conf_get` +
  三个脚本副本）统一为引号优先 / 空白#注释 / 剥 CR / 「引号值 + 行尾注释」组合；
  `cw_atomic_cp` 失败路径清理临时文件；`--accept-local` 归一 `./` 前缀；
  `cw-greploop.sh` 候选根加符号链接围栏
- CI 信号：workflow 标签提取对齐统一解析语义（去 `grep -q` 管道的 pipefail SIGPIPE
  假失败 + 注释/CR 处理）；SKILL.md 标注标签名可由 conf 改写
- e2e：101 → 164 断言（+63），每项修复均先红后绿回归锁

### 教训反思

**降级路径的退出码必须与成功可区分。** 调用方（CI/agent）无法感知「降级但成功」，
统一 0/1/3 契约后失败才可被断言捕获。

**heredoc 内计算的变量不会进入当前 shell。** 渲染前必须存在的值，一律在渲染循环
之前作为 shell 变量显式设置，否则 setup 与 update 两条路径渲染结果不一致，违反
渲染幂等铁律。

**变异点必须选「断言真正依赖的代码路径」。** 多个调用点共享同一守卫时，变异任一
调用点都测不出守卫失效；要变异共享 helper 本身，让所有依赖它的断言同时暴露。
`evidence stop 降级退 3` 尚未被变异证明，如实标注「仅 start 被证明」。

**内容相等 ≠ 未被写穿。** CURRENT 跳过使内容永不重写，但 chmod 类收尾操作会穿透
符号链接改权限位；断言权限位变化必须用 `[[ -x ]]`，`cmp` 只能证明内容。

**修复轮自身是最大新代码风险面，对抗审查必须在修复轮之后重跑。** 首轮修复落地后，
两轮对抗审查从约 23 个修复里又找出 18 项——审查对象必须覆盖「修复本身」，而不是
只盯原始缺陷；一轮审查通过 ≠ 当前代码树可发布。

**契约型计数必须与持久状态同步。** 汇总里的「本地保留」计数与 manifest 实际 `^LOCAL`
行数背离（等值路径被一律计为「已最新」）→ rollout-check 的 `kept == grep -c '^LOCAL'`
发布契约误报「不可发布」。凡对外承诺的计数，必须与它所引用的持久状态一起加回归锁。

**统一解析语义必须覆盖同一文件的全部读取方。** conf 解析统一了四处实现，manifest
读取端却漏网（CRLF 与空格路径下基线查询、哨兵保留双双失真）。统一语义时要先枚举
文件面的**全部**读取方（manifest/conf 的每一处 awk、grep、重定向），逐处核对，
漏一处即行为漂移。

### 验证

```
$ ./test/install-update-e2e.sh
 通过 164 · 失败 0            # 76 → 164：+88 断言（case 8 exec 位 +3、case 15 退出码契约 +14、case 16 符号链接 +3、case 17 受管脚本符号链接 +5、case 12 恶意源信任门 +2、case 18 父目录符号链接 +3、case 1/5 模式保持 +5、case 15 ALLOW_REPO +3 与 greploop 穿越 +3、case 19 空格 manifest +9、case 20 conf 末行守卫 +1、case 21 accept-local 符号链接闸 +3、case 21 accept-local 模式保持 +1、case 11 ./ 前缀归一 +3 与 --force 清 LOCAL 哨兵 +3、case 22 conf 解析器四实现一致 +7、case 15 greploop 符号链接围栏 +2、case 22 引号+注释组合 +4、case 19 CRLF 清单 +4、case 11 force 等值路径 +3、case 22 workflow 标签提取 +3、case 11 LOCAL+等值计数 +4）
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis
 消费仓 3 个 · 通过 9 · 失败 0
```

---

## 1.3.0 — 2026-09-23

### 新增：证据驱动测试 + 服务层架构 + PR 写作规范（3 份 docs 模板）

**问题**：G1 实施 gate 缺少「如何写证据」「如何描述服务层」「如何写去 AI 味的 PR」的
具体模板，agent 每次靠即兴发挥，产出质量参差不齐。

**改进**：新增 3 份 `docs/agents/` 规范模板：
- `evidence-capture.md`（280 行）：证据驱动测试规范，规定原始证据的录制、存档、引用格式
- `code-structure.md`（95 行）：服务层架构描述模板，统一分层边界的表达方式
- `pr-writing.md`（164 行）：PR 写作规范，消除 AI 常见措辞、固定描述结构

### 新增：证据录制 + Greptile 审查闭环（2 个 scripts 脚本）

**问题**：证据录制与外部审查工具（Greptile）的调用参数散落在 agent 对话里，无法复用、
无法版本化。

**改进**：新增 2 个 `scripts/` 包装脚本：
- `cw-evidence.sh`：证据录制包装，子命令 `doctor` / `start` / `stop` / `headless`
- `cw-greploop.sh`：Greptile 审查闭环包装，标准化审查触发与结果解析

### 新增：G1/G2/G3 挂载新规范与脚本

**问题**：`skills/change-workflow/SKILL.md` 的 G1/G2/G3 阶段没有引用新增的 3 份规范与
2 个脚本，装了也不会被编排调用。

**改进**：在 SKILL.md 的 G1（实施）、G2（提交/PR）、G3（收尾）挂载上述规范与脚本，
使编排器在对应阶段自动触发。

### 配套：受管文件 13 → 18

`lib/render.sh` 的 `cw_list_files` 清单、`ci.yml` 的脚本列表与静态检查、
`test/install-update-e2e.sh` 的期望值同步（断言数 74 → 74，无净新增）、`docs/agents/AGENTS.md` 索引同步
更新。

### 教训反思

**抽取集成而非整包部署。** 软件工厂 skill 集合（michaelshimeles/skills）提供了完整的
规范体系，但整包部署会引入与本仓无关的编排层。最终只抽取 3 份规范 + 2 个脚本，按本仓
现有 G0-G4 结构挂载，避免重复造轮子也避免耦合。

**worktree 模型冲突。** 抽取过程中发现上游的 worktree 假设与本仓的「单仓单分支」模型
冲突，最终通过剥离 worktree 逻辑、只保留规范内容与脚本接口解决。

**降级不改变门禁判据。** 新增规范是「补充」而非「替换」，QG/DQ 的最小充分集不变
（QG-1 + QG-2 + QG-5 + DQ-1 + DQ-3 + DQ-5），避免因规范膨胀抬高门禁基线。

### 验证

```
$ ./test/install-update-e2e.sh
 通过 74 · 失败 0            # v1.2.1 实测 74 → fd31579 实测 74：无净新增断言（仅把期望值同步到 18 个受管文件）；原条目「通过 76 / 59 → 76：新增 17 断言」系失实计数，1.3.1 按 `git archive` 离线复跑校正
```

---

## 1.2.1 — 2026-09-22

### 新增：消费仓滚动验证（`test/rollout-check.sh`）

**问题**：工具包改动的影响面只在「消费仓升级之后」才显形 —— 1.1.5 静默覆盖用户定制、
1.2.0 接管模式永不归一，都是从消费侧暴露的。但发布前没有任何自动断言，全靠人在三个
消费仓手敲 `--dry-run` 肉眼看输出。

**改进**：一条命令验证「本工具包 HEAD 装到每个消费仓」的结果，三项断言：
- `冲突 0`
- `本地保留 N` == manifest 里 `LOCAL` 行数（哨兵全部被识别）
- `更新 + 新增 + 已最新 + 冲突 + 本地保留` == 受管文件总数（覆盖无遗漏）

只读（内部走 `--dry-run`），退出码 0/1，可直接当发布门禁。CI 跑不了（CI 没有消费仓
检出）→ 本地发布前手动跑；e2e 用例 14 用临时仓覆盖它的正/负两条路径。

### 修复（阻断性）：自撞渲染会清空模板 —— 新增双重护栏

**发现**：研究「让本仓跑 G0-G4」时发现，13 个受管文件里有 **11 个的模板源与安装目标
同路径**（9 份 `docs/agents/*.md` + `scripts/pr-automation.sh`、`scripts/cw-update.sh`）。
把工具包自身作为 `--target` 时，`cw_render` 的
`cw_strip_header < "$src" | cw_substitute > "$dst"` 会**先截断目标、再由左侧读取**，
同文件时读到空 → 输出 0 字节。实测：1131 / 11913 字节 → 全部归零。

**修复**（两道，互为纵深）：
1. `cw_render` 拒绝 `src` 与 `dst` 为同一文件（`-ef` 判定）
2. `setup.sh` / `update.sh` 在动任何东西之前，用 `cw_is_self_target` 拒绝
   `--target` 指向工具包源自身

`INSTALL.md` 的「手动安装」同样不适用于自我安装（步骤 2 是同路径 `cp`、步骤 4 是同
文件渲染），已在文中标明。

### 教训反思

**「读 A 写 B」的渲染函数必须先断言 A 与 B 不是同一文件。** 这里不是逻辑判断错，而是
shell 重定向语义：`> file` 先截断，管道左侧再打开同一个 file 就只剩空。

附带暴露：本次新增的 `test/rollout-check.sh` 自己就踩了「`$VAR` 紧邻全角字符」——
说明这条静态断言必须覆盖**每个新脚本**，而不是只覆盖历史清单。已把新脚本纳入 e2e 的
语法检查与裸变量检查列表。

### 验证

```
$ ./test/install-update-e2e.sh
 通过 74 · 失败 0            # 59 → 74：新增用例 13（自撞护栏，8 断言）、用例 14（滚动验证，7 断言）
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis
 消费仓 3 个 · 通过 9 · 失败 0
```

---

## 1.2.0 — 2026-09-22

### 新增：项目自升级（`scripts/cw-update.sh`）

**问题**：工具包升级器（`update.sh`）一直只存在于外部 clone，项目自身无法自升级
—— 换机器 / 新同事必须知道「工具包 clone 在哪」，项目无法自述来源。

**改进**：

1. **`update.sh` 向 conf 写入 `TOOLKIT_SOURCE`** —— 记录工具包仓库 URL
   （优先取 clone 的 origin remote，缺省为 `https://github.com/jianxi-dev/change-workflow.git`）
2. **新增 `scripts/cw-update.sh`**（作为受管文件随 `update.sh` 装进每个项目）：
   - 读本项目 conf 的 `TOOLKIT_SOURCE` 定位工具包
   - 复用 `~/.change-workflow`（若存在）或克隆到 `~/.cache/change-workflow`，随后 `pull`
   - 用该副本的 `update.sh` 对自身执行升级

**用法**（项目内）：

```bash
./scripts/cw-update.sh              # 自升级
./scripts/cw-update.sh --check      # 只看版本
./scripts/cw-update.sh --dry-run    # 预览
```

**意义**：项目从此"自包含" —— 来源记录在项目自己的 conf 里，不依赖外部约定位置。

### 修复（阻断性，e2e 用例 12 抓到）：模板缺结尾换行 → 接管模式**永不归一**

**现象**：`scripts/cw-update.sh` 装进项目后再升级，`manifest` 始终缺它的基线，
每次升级都报冲突（`proj/scripts/cw-update.sh` vs 源模板渲染结果差 1 字节）。

**根因**：`cw_render` 用 `awk` 的 `print` 输出，**无条件补一个结尾换行**。
而工具包有 5 个受管模板自身**没有**结尾换行
（`SKILL.md` / `pr-automation.sh` / `cw-update.sh` / `project-board.md` / `task-tracking.md`）。
于是：

- 直接 `cp` 安装的项目文件（无结尾换行）≠ `cw_render` 渲染结果（有结尾换行）
- 接管模式判为「不同」→ **不写基线**（1.1.3 的正确语义）→ 但差异来自渲染而非本地定制
  → 每次都「不同」，**收敛不了**

**修复**：

1. 5 个模板补结尾换行 —— 使「模板字节 == 渲染字节」，`cp` 安装与渲染安装取得一致
   （已复核：4 个既有模板的**渲染产物哈希不变**，存量安装零 churn）
2. 新增 CI 门禁「受管模板以换行结尾」（用 `cw_list_files` 驱动，新增模板自动纳入）

**教训**：渲染必须是**幂等**的 —— `render(x) == x` 对所有未做替换的文件成立。
任何「渲染会改变字节」的路径，都会在接管模式里伪装成「本地定制」。

### 修复：受管脚本装完没有执行位

`cw_render` 用重定向写文件，新文件不带执行位；`update.sh` 原本只 `chmod +x
scripts/pr-automation.sh`。新增的 `scripts/cw-update.sh` 因此装进项目后
`./scripts/cw-update.sh` 直接 `Permission denied`。现两条路径（接管 / 正常更新）
统一对受管脚本 `chmod +x`。

### 验证

```
$ ./test/install-update-e2e.sh
 通过 59 · 失败 0
```

用例 1 新增「cw-update 可执行」断言；语法/裸变量检查纳入 `scripts/cw-update.sh`。

---

## 1.1.6 — 2026-09-20

### 修复（严重）：`--accept-local` 的实现与意图相反，反而导致覆盖

1.1.5 的 `--accept-local` 把**当前内容哈希**记为基线。但基线的语义是
「自上次同步以来**未改动**，可安全更新」—— 于是下次更新
`current == baseline` 成立 → **覆盖该文件**，与「保留本地」的意图正好相反。

**实际损害**：clairis 的 `domain.md` / `issue-tracker.md` / `triage-labels.md`
在被 `--accept-local` 之后**又被覆盖**（已从 `.bak` + git 恢复，零损失）。

**修复**：改为记录**哨兵基线 `LOCAL`**：

- 更新循环遇 `LOCAL` → 永久跳过（不更新、不报冲突）
- manifest 重写保留 `LOCAL`，不覆盖回真实哈希
- 汇总新增「本地保留 N」计数

### 根因反思

这与 1.1.3 修的 adopt 缺陷**同源** —— 都是把「用户内容」误当作「工具包基线」。
教训：**基线只有一个含义（工具包上次写入的内容），不能挪作他用**；
「永不触碰」需要独立的表达（哨兵值）。

### 验证

```
$ ./test/install-update-e2e.sh
 通过 51 · 失败 0
```

用例 11 现覆盖：`LOCAL` 哨兵写入 / 内容不被覆盖 / **多次更新后仍保留** / 哨兵不被重写。

---

## 1.1.5 — 2026-09-20

### 新增：`--accept-local <path>` —— 解决冲突的第三条路

1.1.3 之后，「不同」文件不写基线 → **有意保留本地**的文件会被**永久标记**，
导致 `update.sh` 永远 exit 1，**退出码作为 CI 信号的价值归零**。

原设计只给了两条路（取新版 / 保留但继续报），缺「**我已审阅、确认保留本地、别再报**」。

```bash
./update.sh --accept-local docs/agents/domain.md   # 可重复传多个路径
```

把该文件**当前内容**记为基线，此后不再报告冲突。

### 提示文案更新

冲突提示现在给出三条清晰路径：

```
1. 保留本地：./update.sh --accept-local <file>   （记为新基线，此后不再报告）
2. 采用新版：mv <file>.new <file>                （下次升级自动写基线）
3. 人工合并：diff <file> <file>.new → 合并 → rm <file>.new
4. 全部采用新版：./update.sh --force
```

### 验证

```
$ ./test/install-update-e2e.sh
 通过 48 · 失败 0
```

---

## 1.1.4 — 2026-09-20

### 修复：接管模式输出文案与 1.1.3 的新语义不符

1.1.3 改为「不同文件不写基线」，但输出仍称「当前内容已被接管为基线」——
**文案与实际行为矛盾**，会误导用户以为 `.new` 可以放着不管。

改为准确描述，并给出**逐个文件**的处理方式：

```
以下文件与 X.Y.Z 模板不同…
**这些文件未写基线** —— 在你解决之前，每次升级都会继续报告它们（不会被静默覆盖）。

处理方式（每个文件任选其一）：
  1. 保留本地：rm <file>.new
  2. 采用新版：mv <file>.new <file>   （下次升级会自动写入基线）
  3. 人工合并：diff <file> <file>.new → 合并 → rm <file>.new
  4. 全部采用新版：./update.sh --force

全部解决后再次运行 ./update.sh 即归一（退出码 0）。
```

> 教训：**改了行为必须同步改文案** —— 否则「不静默覆盖」的保障会被错误的提示语抵消。

---

## 1.1.3 — 2026-09-20

### 修复（严重）：接管模式会静默覆盖本地定制

**症状**：`--adopt` 接管后，若用户尚未处理 `.new` 旁路文件就再次运行 `update.sh`，
本地定制文件会被**静默覆盖**。

**根因**：接管模式把**当前内容**（含本地定制）记为基线。下次更新时
`current == baseline` 被判为「未修改」→ 安全覆盖 → 定制丢失。

**实际损害**：clairis 升级时 `domain.md` / `issue-tracker.md` / `triage-labels.md`
被覆盖（已从 `.bak` + git 恢复，零损失）。

**修复**：接管模式下**与模板不同的文件不写基线** → 持续被标记为冲突，
直到用户显式解决（`mv .new → file` 或 `--force`）。

### 修复：`is_in_list` 使用了 bash 4+ 特性

`local -n`（nameref）需 bash 4.3+，而 macOS 自带 `/bin/bash` 是 **3.2** →
函数静默失效（`local: -n: invalid option`）→ 修复逻辑完全没生效。

改为可移植写法（`shift` + `"$@"` 遍历），并把定义移到首次调用之前。

### 新增防线

- **CI**：bash 3.2 兼容性静态检查（排除注释）。CI runner 是 bash 5，
  这类缺陷在 CI 上**永远绿**，只在 macOS 暴露 —— 属「CI 绿、本机红」的反向形态。
- **e2e 用例 10**：接管 → 再次更新，定制不得被覆盖（回归锁）。

### 验证

```
$ ./test/install-update-e2e.sh
 通过 43 · 失败 0
 全部通过 ✅
```

---

## 1.1.2 — 2026-09-20

### 修复

- **`scripts/pr-automation.sh`：`--refs-only` 时 commit message 使用 `refs #N`**
  此前 commit message 恒为 `fixes #$ISSUE`，**无视 `--refs-only`**。
  该 flag 用于 parent/spec issue 的 PR（防止合并时提前关闭其生命周期），
  PR body 已正确使用 `Refs #N`，但 **commit message 仍写 `fixes #N`** ——
  而 GitHub 对两者**都会**触发自动关闭，故 `--refs-only` 实际被**部分破坏**。
  来源：clairis 的修复（其 HEAD commit），此前**从未回灌上游**。

### 说明

这是升级 mdpkg / clairis 时通过 `.new` 旁路暴露的**第三个上游缺口**：

| # | 缺口 | 来源仓库 | 版本 |
|---|---|---|---|
| 1 | `git add -f` 回退（.gitignore 匹配路径） | mdpkg PR #24 | 1.1.1 |
| 2 | 看板常量改为从 conf 读取（+ option ID 泄漏） | mdpkg 升级暴露 | 1.1.1 |
| 3 | `--refs-only` 的 commit message | clairis HEAD commit | 1.1.2 |

**三个都印证了接管模式「不静默覆盖」的价值** —— 若直接 `--force`，这些下游改进会被静默丢弃。

---

## 1.1.1 — 2026-09-20

### 修复

- **`scripts/pr-automation.sh`：补 `git add -f` 回退**
  白名单路径若被 `.gitignore` 匹配（如 force-tracked 的 `.omo/notepads/**`），`git add` 会失败。
  现在自动 fallback 到 `git add -f`（路径已由 `--files` 显式限定，故安全）。
  来源：mdpkg PR #24 的成果，此前**从未回灌上游**。

- **`skills/change-workflow/SKILL.md`：看板常量改为从 conf 读取**
  模板原本**烘焙字面量 option ID**（`a50766ca` / `4cbd348f` / `8c7f2979` / `a7011ca0`），
  把安装源仓库的值泄漏给所有消费者；且与 `DESIGN.md` 矛盾 ——
  DESIGN 明确「脚本 `source` 该文件；**skill 读取它取看板常量**」。
  改为读取 `.change-workflow.conf`，与设计一致、无漂移、无泄漏。

### 说明

两项均通过 **mdpkg 升级时的 `.new` 旁路**暴露 —— 这正是接管模式「不静默覆盖、交回人工核对」的价值：
若当初直接 `--force` 覆盖，mdpkg 的 `git add -f` 修复会被**静默丢弃**。

---

# CHANGELOG

本工具包遵循语义化版本。安装后可用 `./update.sh --check` 查看是否有新版本。

## 1.1.0 — 2026-09-20

### 新增：开发与测试质量门禁（QG / DQ）

来源：一次真实交付失败的复盘 —— 某 change 的 9 个 PR 中 8 个对应用层与 e2e **双双零改动**，12 张票全打勾、CI 全绿，而用户打开页面**看不到任何变化**；随后的缺陷修复期又抓出 4 个「自测全绿但实际无效」的假修复（4/4 由独立探针推翻）。

- **新增规范** `docs/agents/quality-gates.md`：QG-1..QG-7（变更开发侧）+ DQ-1..DQ-8（缺陷处理侧），每条含「规则 / 理由 / 实证案例 / 如何验证」四小节
- **`docs/agents/task-tracking.md`**：§3 票内容加 QG-1/QG-3 与禁入信号；§7 加 QG-2/QG-4/QG-5/QG-6 硬门禁
- **`docs/agents/defect-workflow.md`**：新增「修复质量门禁」章节（DQ-1..DQ-8）
- **`skills/change-workflow/SKILL.md`**：G0 切片约束加 QG-7/QG-3；G1 加第 0.5 步 QG 前置校验、QG-2 e2e 硬门禁、QG-6 集成 checkpoint；G1 出口加 QG-5 独立验证；缺陷处理机制章节每环节标注 DQ 编号
- **`setup.sh` 的 AGENTS.md 索引段**：补 Quality gates 段（QG/DQ 核心条目）

### 新增：更新机制

此前 `setup.sh` 只能首装（已存在文件一律跳过），无任何升级路径。

- **`VERSION`**：工具包版本号；安装时写入目标仓库 `.change-workflow.conf` 的 `TOOLKIT_VERSION`
- **`update.sh`**：增量更新已安装仓库
  - `--check` 仅比对版本、不落盘
  - `--dry-run` 打印将执行的动作
  - `--force` 忽略本地改动强制覆盖（先备份）
  - **冲突保护**：以安装/上次更新时记录的基线哈希判断文件是否被本地修改；未修改 → 安全覆盖；已修改 → 写 `<file>.new` 旁路文件并报告，不覆盖
  - 覆盖前一律写 `.bak`
- **`.change-workflow.manifest`**：记录每个受管文件安装时的基线 sha256，供 update 判定本地改动
- **`lib/render.sh`**：抽取共享的占位符替换逻辑，供 setup/update 共用（防两处逻辑漂移）
- **新增占位符**：`{{REPO_ROOT}}`（目标仓库根绝对路径）、`{{EFFECTIVE_DATE}}`（安装日期）

### 修复：模板硬编码其它仓库的路径

`docs/agents/*.md` 模板中残留 `cd /Users/mason/ToHighs/md-bundle` 等硬编码路径，安装到其它仓库后会指向错误目录。已改为 `{{REPO_ROOT}}` 占位符，由安装/更新时替换为目标仓库真实根路径。

> **已安装仓库注意**：若你的仓库此前安装过 1.0.0，其中的 `cd <其它仓库路径>` 是错的；升级到 1.1.0 会自动修正。

---

## 1.0.0 — 初始版本

- `skills/change-workflow/SKILL.md`：G0-G4 五 gate + fix-first 自愈回路 + 缺陷机制
- `scripts/pr-automation.sh`：issue 驱动分支/PR 自动化
- `workflows/change-closure-signal.yml`：CI 合并信号
- `docs/agents/*.md`：7 份规范模板（task-tracking / issue-tracker / project-board / triage-labels / defect-workflow / domain / incident-*）
- `setup.sh`：安装向导
