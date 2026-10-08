## 1.12.3 — 2026-10-08

### 新增/修复

**同步上游 mattpocock/skills 更名：`Context.md` / `CONTEXT-MAP.md` → `GLOSSARY.md` / `GLOSSARY-MAP.md`**

- `docs/agents/domain.md`：3 处 `CONTEXT.md` 引用改为 `GLOSSARY.md`，并补多上下文仓库说明（根目录存在 `GLOSSARY-MAP.md` 时按 map 定位各上下文 `GLOSSARY.md`）。上游 `domain-modeling` skill 现在只读写 `GLOSSARY.md`，旧名会让消费仓 agent 去找一个 skill 永不生成的文件（契约静默失效）。
- `docs/agents/pr-writing.md`：参考上游 `/pr` skill 增加「§七 PR 正文的两块内容：Evidence 与 Merge Danger」——Evidence 要求成对 before/after 原始输出，Merge Danger 要求声明单向门/双向门与影响半径；与既有 risk 标签（可评审强度轴）显式区分，不重复 QG-5 判据。
- `test/install-update-e2e.sh`：用例 9 新增 2 条契约锁（先红后绿）——domain.md 必含 `GLOSSARY.md`、不得含 `CONTEXT.md`，防改名漂移回旧名。
- **登记第 4 个消费仓 contentweave**：其 `docs/agents/quality-gates.md`（自建 QG-9 交付物证据表）与 `.github/workflows/evidence-check.yml`（断言判据补 Python/openspec 形态）属有意本地化，用 `--accept-local` 归一为 LOCAL 哨兵；`docs/agents/domain.md` 同步 GLOSSARY 更名。AGENTS.md 消费仓清单与 rollout-check 调用同步补入。

### 教训反思

**上游重命名只打到引用方，不会自己通知你**：CW 把「领域文档创建」外包给上游 `/domain-modeling`，只在 `domain.md` 文档化消费侧；上游改了产出文件名，引用侧不跟就静默失效。防御：凡把能力外包给外部 skill，其接口契约（产出文件名/路径）必须有本仓侧回归锁，依赖清单记录上游快照便于比对漂移。

**规范新增章节要区分轴，别造同义竞争**：Merge Danger 的单向/双向门与既有 `risk-low/medium/high` 是两条不同的轴（可逆性 vs 可评审强度），混写会造出互相打架的词汇（T10 同义词轮换）。新增内容必须显式声明与既有概念的关系。

### 验证

```
$ ./test/install-update-e2e.sh
  通过 331 · 失败 0（39 用例；用例 9 新增 2 条改名契约锁）
  先红：模板未改前，2 条新断言全红（domain.md 仍指向 CONTEXT.md，通过 329 · 失败 2）

$ bash -n / shellcheck / 占位符表 / 模板头 / 结尾换行：本地 5 项门禁全绿
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis ../contentweave
  消费仓 4 个 · 通过 12 · 失败 0（冲突 0 / LOCAL 哨兵完整 / 覆盖数 24 一致）
```

---

## 1.12.2 — 2026-10-06

### 新增/修复

**修复：1.12.1 引入的回归——`pr-automation.sh` 打坏「无 PR → 新建」路径（change-workflow#2 评论）**

- `scripts/pr-automation.sh:336` 的 PR 检测 jq 由 `'.[0]'` 改为 `'.[0] // "NO_PR"'`；`:338` 守卫扩为 `[[ -z "$PR_JSON" || "$PR_JSON" == "NO_PR" || "$PR_JSON" == "null" ]]`。
- 根因（实测 gh 2.95.0，`xxd` 原始证据）：`gh pr list --head <无匹配>` 时 `--jq '.[0]'` 输出**空串**（仅 `0a`），**不是** `null`。1.12.1 的守卫只认 `NO_PR`/`null` → 空串漏判 → 走 `else` 当作已有 PR → `_head="" != "$BRANCH"` → 「❌ 已有 PR … 拒绝接管」退 1 → **「无 PR → 新建」路径（`--role feat` 从头模式）100% 中断**，`gh pr create` 永不执行——比 1.12.0 更糟（旧代码该路径本是好的）。
- `test/install-update-e2e.sh`：新增用例 38（先红后绿）——桩**忠实模拟真 gh 2.95.0**（无匹配时 `pr list` 输出空串而非 `null`），断言走 create 新建 PR、不误判「拒绝接管」、抵达 auto-merge，并静态锁定空值归一与 `-z` 守卫。用例 37（已有 PR 路径）保留为对照。

### 教训反思

**桩必须忠实复刻真实 CLI 的行为，否则「桩上绿、真实环境红」**：1.12.1 的用例 37 桩假定 `jq '.[0]'` 无匹配 → `null`，而真 gh 2.95.0 输出空串——桩把「打坏 fresh 路径」的缺陷掩盖了。防御：凡以桩替代外部 CLI，桩的**每个返回值/退出码都必须与真 CLI 实测对齐**；一次改动触及的**两侧（有/无）都要有独立断言**，不能只锁修复面。

**修复一处须回归一处**：1.12.1 只锁了「已有 PR」用例，未给同一函数补「无 PR」对照组——改了 `PR_JSON` 的归一语义，却未锁它的另一种取值。这是本次回归的成因，用例 38 即其补丁。

### 验证

```
$ ./test/install-update-e2e.sh
  通过 329 · 失败 0（39 用例；新增用例 38「无 PR → 新建」6 条断言）
  先红：1.12.1 源码下用例 38 六条断言全红（误判「拒绝接管」退 1），用例 37 保持绿

$ bash -n scripts/pr-automation.sh test/install-update-e2e.sh：全绿
$ shellcheck --severity=warning -x scripts/pr-automation.sh test/install-update-e2e.sh：clean

$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis
  消费仓 3 个 · 通过 9 · 失败 0（冲突 0 / LOCAL 哨兵完整 / 覆盖数 24 一致）
```

---

## 1.12.1 — 2026-10-06

### 新增/修复

**修复：`pr-automation.sh` `--resume-branch` 收口路径失效（`gh pr view` 无 `--head` flag，issue #2）**

- `scripts/pr-automation.sh` 的 PR 检测由 `gh pr view --head "$BRANCH"` 改为 `gh pr list --head "$BRANCH" --state all --limit 1 --json number,headRefName,baseRefName,title,state --jq '.[0]'`。`--head` 是 `gh pr list` 的 flag，`gh pr view` 不接受它（实测 gh 2.95.0：`gh pr view --head x --json number` → `unknown flag: --head`，退 1）。
- 旧路径后果：错误 flag 让检测命令稳定失败 → `2>/dev/null || echo "NO_PR"` 恒判 `NO_PR` → 走 `gh pr create` 分支 → PR 已存在时 create 退 1 → `set -euo pipefail` 在 step 5/6 中止 → **auto-merge 永不 arm**（分支无法自动收口）。
- 保留 `:337` 的 `NO_PR`/`null` 处理：`gh pr list` 无匹配返回 `[]`，`jq '.[0]'` 输出 `null`，既有 `== "null"` 分支自然兜住。`--state all` 确保非 OPEN 的健在 PR 仍被找到并交由既有 head/base/state 校验拒绝（未弱化校验）。
- `test/install-update-e2e.sh`：新增用例 37（先红后绿）——用模拟真实 `gh` 行为的桩（`pr view --head` 复刻 `unknown flag` 退 1），断言收口退 0、命中「已存在且校验通过」、抵达 auto-merge，并以静态契约锁锁定源码无 `gh pr view --head`、恰一处 `gh pr list --head`。

### 教训反思

**参数落在错误的子命令上，被 `2>/dev/null || 默认值` 掩盖成「无 PR」**：`gh pr view` 与 `gh pr list` 的 flag 集不同，`--head` 只属于后者；错误 flag 让命令稳定失败，而 `|| echo NO_PR` 把它伪装成一个合法状态，于是收口静默走了错误分支。防御：① 关键外部命令的「失败即默认值」必须有回归测试覆盖默认值本身是否语义正确；② 子命令级 flag 差异要靠功能测试（模拟真实 CLI 行为）而非「命令存在性」检查。

**一次收口断链会吞掉后续所有步骤**：`set -e` 在 create 失败处中止，auto-merge 根本没机会执行——表象是「PR 建不出来」，真实影响是「分支永不自动合并」。功能测试必须断言**末端有效动作**（auto-merge）被抵达，而不只断言中间步骤没报错。

**测试桩必须先在正确的状态上运行**：首版用例曾用 untracked 的 `scripts/`、`stub/` 建桩，被 resume 模式的脏树护栏（`git status --porcelain` 计入 untracked）提前拒绝——测试看似「红」，却根本没走到被测行。桩、裸远端必须落在仓外，被测脚本先提交入库，工作树清空后才具判定力。

### 验证

```
$ ./test/install-update-e2e.sh
  通过 323 · 失败 0（38 用例；新增用例 37「pr-automation --resume-branch 收口」6 条断言）
  先红：坏代码下该用例 6 条断言全红（gh pr create「already exists」→ set -e 中止，未达 auto-merge）

$ bash -n scripts/pr-automation.sh test/install-update-e2e.sh：全绿
$ shellcheck --severity=warning -x scripts/pr-automation.sh test/install-update-e2e.sh：clean

$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis
  消费仓 3 个 · 通过 9 · 失败 0（冲突 0 / LOCAL 哨兵完整 / 覆盖数一致）
```

---

## 1.12.0 — 2026-10-05

### 新增/修复

**新增：conf 驱动 `{{APP_DIR}}` 占位符（消除路径本地化被迫 LOCAL 冻结）**

- `lib/render.sh:cw_substitute` 新增 `{{APP_DIR}}` 替换行：`out="${out//\{\{APP_DIR\}\}/${APP_DIR:-<APP_DIR>}}"`；缺省渲染回字面 `<APP_DIR>`，对未配置仓零变化。
- 模板 `docs/agents/{quality-gates,evidence-capture}.md`：正文所有 `<APP_DIR>` → `{{APP_DIR}}`；模板头说明改为「`{{APP_DIR}}` 由 `.change-workflow.conf` 的 `APP_DIR` 键渲染（缺省保留字面 `<APP_DIR>` 记号）；其余尖括号仍是通用记号」。
- `config.example.conf`：目录约定区新增 `APP_DIR="<APP_DIR>"`，注释说明设为实际源码目录（如 `apps/web`）后模板中的 `{{APP_DIR}}` 渲染为该值。
- `update.sh`：conf 读取白名单 14→15 键（加 `APP_DIR`），同步注释「15 个键」。
- `setup.sh`：新增 `APP_DIR` 交互提示（默认 `<APP_DIR>`），写入 conf；`set -euo pipefail` 下未设时不报错（靠 `${APP_DIR:-<APP_DIR>}`）。
- `test/install-update-e2e.sh`：新增用例 1b（先红后绿）——设 `APP_DIR=apps/web` 渲染含 `apps/web` 且 `{{APP_DIR}}` 为 0；未设时含 `<APP_DIR>` 且 `{{APP_DIR}}` 为 0；既有「无残留占位符」断言继续通过。

### 教训反思

**路径本地化本应由 conf 表达，而非手工替换**：md-bundle 的 `quality-gates.md` 因手工把 `<APP_DIR>` 替换为 `apps/web`，与模板逐字节不同 → 只能标 `LOCAL` → 该文件**永远吃不到后续新规**（现被冻在 v1.11.0）。本 change 把「路径本地化」纳入渲染管线，文件与基线一致、可持续升级，消费仓可摘 `LOCAL` 恢复正常升级通道。

**占位符设计要「缺省即现状」**：`${APP_DIR:-<APP_DIR>}` 让未配置仓的渲染产物保持原样（字面 `<APP_DIR>`），不引入破坏性变更；这也是「渲染幂等」铁律的体现——`render(x) == x` 对未做替换的文件必须成立。

### 验证

```
$ ./test/install-update-e2e.sh
  通过 317 · 失败 0（37 用例；新增用例 1b「APP_DIR 渲染」8 条断言）

$ bash -n / shellcheck --severity=warning -x / bash 3.2 静态：全绿
$ 占位符一致性 / 模板头 / 结尾换行 / 无仓库特有值：全绿
```

---

## 1.11.1 — 2026-10-05

### 新增/修复

**调整：全风险 PR 自动合并（移除 risk-high 人工合并门）**

- `pr-automation.sh` auto-merge 逻辑不再按风险分档：`low`/`medium`/`high` 均尝试启用 auto-merge；仓库未启用 auto-merge 时仍 fail-open（提示手动 `gh pr merge`，退出 0）。
- `review`（pre-landing 结构审查，risk≥medium）语义**不变**——审查与合并是两回事。
- 净效果：任务级「唯一人工介入」由「risk-high PR 合并确认」收窄为「跨 change 切换的队列盘点」；**无仓库级人工合并门**。
- 同步更新：`scripts/cw-greploop.sh`、`scripts/AGENTS.md`、`skills/change-workflow/SKILL.md`、`skills/change-workflow/agents-quick-reference.md`、`docs/agents/task-tracking.md` 的相关表述。

### 教训反思

**自动化边界要敢于收窄**：v1.11.0 把 medium 纳入 auto-merge 后，人工介入面只剩 high 一处；本版直接把 high 也纳入，彻底移除「仓库级人工合并门」。把「边界」写进脚本逻辑（无条件尝试 auto-merge）比散落的文档表述更难漂移——脚本即事实来源。

**文档同步要一次到位**：本次改动涉及 6 个文件的 10 处引用，若分批改极易漏。用「先红后绿」锁定 e2e 断言（auto-merge 无风险分档），再一次性改完所有引用，跑绿即全同步。

### 验证

```
$ ./test/install-update-e2e.sh
  通过 307 · 失败 0（36 用例；受管数断言 23→24；新增用例 36「cw-conformance.sh 契约锁」6 条断言）

$ bash -n / shellcheck --severity=warning -x / bash 3.2 静态：全绿
$ 占位符一致性 / 模板头 / 结尾换行 / 无仓库特有值：全绿
```

---

## 1.11.0 — 2026-10-05

### 新增/修复

**新增：一致性制品生成器 `scripts/cw-conformance.sh`（受管数 23 → 24）**

v1.10.0 把「一致性制品」写进约定层（`evidence-capture.md` §八），但生成仍靠人手——实现者仍可手填/反填 `conformance.json`（投毒源未堵）。本版补上 G0 生成器，把「不由实现者手填」从文字变为机检机制：

- 四子命令：`scaffold`（生成 `anchors.md` 骨架）/ `generate`（解析 `anchors.md` → 四规则校验 → 原子写 `conformance.json`）/ `lock`（对 `conformance.json` + `baseline/*.png` 逐文件 sha256 → 写 `conformance.lock` 哈希锁）/ `verify`（重投影语义比对 + 哈希核验）。
- `anchors.md` 人写一次、任意 markdown 查看器可读；JSON 永远是投影（规格双形态的人读层不可丢）。确定性文法：`^## (R-\d+) (.+)$` 开启 requirement、裸 markdown 表列名恰为 `id|kind|claim|assert|source`；对无 openspec 消费仓同样成立。
- 四规则（完备 / 无孤儿 / 可断言 / 来源非空）与 `cw-tickets-check.sh:check_conformance` **刻意重复、同词汇报错**（防「生成通过、检查失败」的静默漂移）。
- 退出码 0/1/3 对齐 `cw-evidence.sh`：内容错 → 1（fail-closed），环境缺（python3 缺失 / 未锁定 / 无制品）→ 3（降级，调用方决定）。
- **自举 dogfood**：本 change 自身的 `anchors.md` → `generate` → `lock` → `verify` 全绿（openspec change `cw-conformance-generator`）。

**调整：中风险（risk-medium）PR 也自动合并**

- `pr-automation.sh` auto-merge 条件由「仅 risk-low」扩为「risk-low/medium」；仅 **risk-high** 保留人工合并确认。`review`（pre-landing 结构审查，risk≥medium）语义不变——审查与合并是两回事。
- 净效果：任务级「唯一人工介入」由「risk-medium/high 合并确认」收窄为「risk-high 合并确认」。

### 教训反思

**「约定」到「机制」还差一个生成器**：v1.10.0 定义了制品与四规则机检，但生成动作仍可人工——只要产物由实现者落笔，投毒面就还在。生成器把人写面收窄到「人读的 `anchors.md`」，机读 JSON 全由脚本产出并锁哈希，实现期只消费。

**自动化边界要显式收窄**：中风险自动合并后，人工介入面只剩高风险合并确认一处；把「边界」写进 SKILL 与规范，比散落的「medium/high」表述更难漂移（本版一并统一了脚本/规范/速查卡五处 medium 合并引用）。

### 验证

```
$ ./test/install-update-e2e.sh
  通过 307 · 失败 0（36 用例；受管数断言 23→24；新增用例 36「cw-conformance.sh 契约锁」6 条断言）

$ bash -n / shellcheck --severity=warning -x / bash 3.2 静态：全绿
$ openspec validate cw-conformance-generator --strict：valid
$ ./scripts/cw-conformance.sh verify cw-conformance-generator（自举 dogfood）：全绿
```

---

## 1.10.0 — 2026-10-04

### 新增：机制层门禁加固（双形态规格 / 验收锚点 / 一致性制品 / CI 三层核验 / §八 三指标）

**背景**：v1.9.0 把保真/生命周期门禁写进**定义层**（QG-1/4/5/8 文字 + SKILL 指令），并显式「不改 bash 脚本行为」。24 小时后消费仓 md-bundle 证伪：其 `editor-fidelity` change **16/16 勾选、CI 全绿、已归档**，用户打开即见约 20 处与原型不符——**10/11 票零证据产物**（#327–#336 无 `.artifacts`）、QG-5 证据写成「测试通过数 + 文字描述」（QG-5 自认无效的形式）、已有测试把实现偏差写成预期（同义反复）、空断言两分支皆过。根因：**门禁有定义、无机器强制、靠自证**。

**改动（机制层；不新增 QG/DQ 条目，兼容 §八）**：

- **规格双形态 + 验收锚点**（QG-1 前置定义）：规格须同时产出人读层（主产物，不可丢）与机读层 `conformance.json`（具体值 + 来源 + 断言类型），双向链接；G0 机检四项——完备 / 无孤儿 / 可断言 / 来源非空。`quality-gates.md` 新增定义段；`task-tracking.md` §3 增「验收锚点」字段。
- **一致性制品 + baseline**：有原型时 G0 程序化生成 `conformance.json` + `baseline/*.png` + e2e 骨架并**锁哈希**；实现只消费、禁篡改。`evidence-capture.md` 新增 §八。
- **CI 三层自动核验（全自动无人）**：新增受管 `evidence-check.yml`（**受管数 22 → 23**）——ui-surface 票（label ∪ diff 路径）跑 **T1 确定量 / T2 感知 / T3 状态机**；验证分离靠**跨模型自动复核**，非人工审批。
- **证据 manifest 机检**：`cw-evidence.sh` 增 `record-state` 子命令（写/合并 `state-coverage.json`；exit-3 收紧为须附机器可核验理由）；`pr-automation.sh` G2 出口对 ui-surface 票校验 manifest（≥4 态，fail-open）；`cw-tickets-check.sh` C3/C4 增 `conformance.json` 锚点机检。
- **§八 三指标**：退役判据由单一「捕获次数」改为**执行率 / 阻断数 / 下游归因缺陷数**，并识别关键词门禁「高捕获零价值」。
- **SKILL.md / 速查卡**：G0 锚点门 + 制品生成；G1/G2 自动核验与 manifest 校验；G4 baseline 校验。

### 教训反思

**教训必须落到机制，不能只写成文字**（pstack `encode-lessons-in-structure`）：v1.9.0 把规则写进定义层，在无人盯守的 agent 运行里静默失效。本轮把两条硬约束落进设计——**不依赖人工兜底**（保真核验改为 CI 三层自动 + 跨模型复核，撤销原「人审复核包 + PR 审批」路线）、**规格双形态**（人读散文是主产物，机读锚点是其投影，人读层不可丢）。

**§八 有自我否定缺陷**：良好执行的机检门禁合规率高 → 零阻断，恰会被现行「零捕获即退役」退役；故改三指标。关键词门禁则相反——高捕获、零预防价值。

**本地证据环境已具备**：Playwright + chromium + ffmpeg 齐全，「无截图环境」不再构成降级理由。

### 验证

```
$ ./test/install-update-e2e.sh
  通过 286 · 失败 0（35 用例；新增用例 35「机制化门禁契约锁」；受管数断言 22→23）

$ bash -n / shellcheck --severity=warning -x / bash 3.2 静态：全绿
$ 占位符一致性 / 模板头 / 结尾换行 / 无仓库特有值：全绿
```

---

## 1.9.0 — 2026-10-03

### 新增：保真/生命周期门禁加固（QG-1 三分类 AC、QG-4 断言阶梯、QG-5 视觉探针、QG-8 发现闭环门、需求输入门）

**背景**：editor-v2 实测 29/29 勾选、CI 全绿，用户仍见 D1–D10——callout 标题重复「注释 注释」、代码围栏残留反引号、斜杠菜单点外部不关、取消后 `/` 残留、表格点一下塌成裸源码、空态无「新建文档」入口、React 重复 key。根因在四层：**L-1 需求输入无证据、L0 设计→规格翻译损耗、L3 断言停在「元素存在」、L4 验收用存在性自证**。

**改动**（6 项）：

- **QG-1 升级为三分类 AC**：存在 / 生命周期（六态：打开·切换·取消·外部点击·空态·关闭，含取消后无残留）/ 保真（文本/像素严格等于、不含伪影）。§四 AC 模板替换为三行格式；§五补三条正反例（callout 重复 / 围栏反引号 / 取消残留）。
- **QG-4 新增断言强度阶梯**：存在→可见→文本相等→状态往返→视觉。渲染/浮层类 ≥ 文本相等；可取消类 ≥ 状态往返。
- **QG-5 增视觉探针 + 禁伪造手动 QA**：明确「元素存在/count>0」非有效证据、「同类探针自证」不算证据、禁止把手动 QA 写成 `qa-*.spec.ts`。
- **新增 QG-8 发现闭环门**：findings 每条缺陷须转 tracked issue 或规格条目，否则 change 不得完成。
- **需求输入门（L-1，挂 G0-PRE）**：对标/学习类 change 的需求输入包须满足五条契约——来源可追溯 / 空白显式化（`open-question` 阻断引用）/ 一手证据 / 冲突显式 / 验收锚点；纯重构/文档/基建票 `no-ui-impact` 豁免。
- **G4 收尾加生命周期黑盒巡检 + QG-8 前置**：按六态真机走查，发现问题不得收尾；发现闭环门机检（findings 行数 vs issue 数）。
- **配套**：`evidence-capture.md` §3.2 补状态覆盖矩阵（六态 + `state-coverage.json` 约定 + ≥4 态机检）、§三增视觉探针；`SKILL.md` G0-PRE 加需求输入门、G1 出口 QG-5 同步多态截图、G4 加巡检与 QG-8；`cw-tickets-check.sh` C3/C4 同步三分类 AC 机检；§七收紧 `no-ui-impact`（浮层/插入/渲染类不得豁免生命周期与保真）；§八为新/改门禁加 expected capture 行。
- **跨文件引用同步**：`task-tracking.md`、`agents-quick-reference.md`（速查卡 QG 索引补 QG-8 + QG-1/4/5 更新 + G0 输入门/G4 巡检）、`docs/agents/AGENTS.md`（QG 范围 / 证据类数）三处漂移一并修正；e2e 新增**用例 34 跨文件引用一致性契约锁**防再漂移。

### 教训反思

**门禁架构压缩是必要的**：提案原为 4 新 + 3 修订，压成 1 新 + 3 修订 + 1 契约门（学习层证据并入需求输入门、设计→规格保真并入 QG-1 第③类），兼容 `quality-gates.md` §八减法审计的「门禁只增不减」约束。

**多态证据必须绑定活代码**：状态覆盖矩阵截图由 QG-4 第 4 级状态往返断言驱动产生（副产物），而非独立手工产物；`state-coverage.json` 与 e2e spec 状态断言双管，使「是否多态」可机检。

**需求输入门合并了学习层证据**：CW 编排图已把四类输入源视为同一漏斗；拆两门=分裂同一漏斗、徒增门禁面，直接对抗 §八。

### 验证

```
$ ./test/install-update-e2e.sh
  先红 237/33（用例 30-33 全红）→ 修复后绿 274/0（34 用例）

$ ./test/rollout-check.sh ../clairis ../contentweave ../md-bundle ../mdpkg ../video-learning-html
  消费仓 5 个 · 通过 15 · 失败 0

$ bash -n 全受管 shell 脚本：OK
$ shellcheck --severity=warning -x 全受管 shell 脚本：OK
```

---

## 1.8.3 — 2026-09-27

### 新增：任务级自动执行（零询问）+ change 收口「剩余队列盘点」；修复：单行头模板渲染归零

**背景**（消费仓实测两处断点 + 一个潜伏缺陷）：① 同一 change 内每个任务完成后被询问「是否进行下一个任务」——SKILL 仅有「单 agent 会话内自动循环」弱约束，跨会话无任务级接力，且「接手进行中 change → 确认后继续」反而主动要求询问；② change 收口（G4）后无任何「剩余 issue 盘点」，完成后不提醒 GitHub 中的剩余工作；③ 排查中发现速查卡在消费仓为**空文件**——`cw_strip_header` 的闭合规则 `/-->/` 只对多行头成立，**单行头**（`<!-- …模板 -->`）在第 1 条规则被 `next` 掉后永不闭合 → 全文件被吞、渲染 0 字节；0 字节又与空基线相等 → 升级判「已最新」静默存活。

**改动**（4 项）：

- **会话启动·自动接力**：「进行中 change 自动接力（零询问）」——新会话扫描 `[change=<名>/` 子票，有可开工 frontier 票（Blocked by 全 closed）→ 直接进入 G1，不询问；多个 change 取最近推进者并一句话说明。
- **G3·任务级零询问 + 阻塞等待**：frontier 推进改为「立即进入下一票 G1，禁止以『是否继续下一票』结束回合」；新增「阻塞等待（有界轮询）」——frontier 为空的唯一原因是前序票 PR 未合并时，轮询合并状态（20s / 上限 10 分钟）→ 合并后自动继续。
- **G4·剩余队列盘点**：收口后 `gh issue list --state open` 分类盘点（其他 change 子票 / 决策研讨类 / 其他）→ 列出剩余清单 + 下一项建议 + 询问是否继续（change 边界 = 全局唯一停点；空则报告「无剩余 issue」）。
- **修复 `cw_strip_header` 单行头归零**：单行头自身含 `-->` 即完成剥离；e2e 新增用例 29（全模板渲染非空 + 速查卡剥头干净）作回归锁。连带同步：速查卡 G3/G4 段、task-tracking §8.3 人工介入点描述。

### 教训反思

**自动化条款必须同时回答「会话内怎么连」和「会话间怎么接」**：只写「单 agent 会话内自动循环」默认了任务连跑发生在同一会话，而真实执行天然跨会话（改天继续、等合并后重开）——断点无承接机制，agent 只能退回询问。同理「change 收尾后做什么」此前只写到归档为止，缺「之后呢」——收口即失联。停点要显式：任务级零询问，change 边界停一次并盘点，「不停」与「该停」都有落点。

**「与基线一致」不等于「内容正确」**：空文件与空基线相等 → 升级把 0 字节判为「已最新」，缺陷静默存活。基线是**变更检测**工具而非**内容正确性**工具——正确性必须另有独立断言（用例 29 全模板渲染非空）。

### 验证

```
$ ./test/install-update-e2e.sh
  用例 28 先红 229/5、用例 29 先红（⚠️ 空渲染 + 断言差）→ 修复后绿 237/0（29 用例）

$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis ../contentweave
  消费仓 4 个 · 通过 12 · 失败 0

$ ./update.sh --target ../contentweave
  更新 4 · 冲突 0 · 本地保留 3；速查卡 0B → 3353B（空文件修复落地）
```

---

## 1.8.2 — 2026-09-27

### 修订：撤销静态验证技能方案，改为 QG-5 探针形态约定

**背景**：v1.7.3 按 pstack G1 反哺生成 `verify-md-bundle` 静态验证技能并完成端到端自证。随后在功能迭代语境下评估其成立性，识别三条结构性问题：① 静态文档装不下高频变化的知识（特性地图/选择器几天到几周过期；腐烂的文档比没有文档更糟——agent 会信任它、被误导）；② pstack 自身触发条件「无脚本化验证路径」不成立（消费仓均有 UI 且已有 e2e 基建）；③ 与 e2e 活代码平行漂移（QG-2 已要求 e2e 绑定，两边都要维护而只有活代码一边被 CI 约束）。

**改动**（1 项）：

- **撤销 + 替代**：删除消费仓的 `verify-md-bundle` 技能（SKILL.md + 5 特性文件 + 特性地图索引）与试点产物；`SKILL.md` G1 出口 3.5 条款重写为「**探针形态（活代码优先）**」——有 e2e 基建 → 探针写成/扩展 e2e（随代码维护、`CMD_E2E` 可复跑）；无基建或需特定驱动 → 轻量探针 + `evidence-capture.md` 证据约定；禁止静态技能副本。`evidence-capture.md` 新增「四、探针形态（活代码优先）」节（四段式：规则/理由/实证案例/如何验证）；后续节号顺延（四→五、五→六、六→七），§五→§六 跨节引用同步。

**连带**：e2e 新增用例 27（3 断言：SKILL 条款存在 / SKILL 零 verify 残留 / 规范节存在）——先红 226/3 → 绿 **229/0**（27 用例）；无受管文件增删（受管仍 22）；rollout-check 4 消费仓 12/0。

### 教训反思

**静态文档与高频变化知识是结构性错配**：驱动知识（选择器、命令、特性地图）的变化速率决定它只能活在随代码维护的载体里（e2e 用例）。写进静态文档 = 必然腐烂 + 平行漂移。以后评估「知识放文档还是放代码」时，先问变化速率。

**「免费基建」也要过存在性检验**：pstack 方案的触发条件是「无脚本化验证路径」——落地前应先对每个候选仓问「它的前提成立吗？」。本次试点依赖外部报告的分类（「仅 md-bundle 有 UI」）而未独立验证三个消费仓，直到试点后才确认真相（均有 UI + e2e 基建）——这正是本仓 DQ-2 禁止的「把假设当结论」。

**撤销也是交付**：试点自证通过 ≠ 方案成立。花数十 K tokens 生成 + 端到端自证后判断不成立并撤销恢复，比留下腐烂基建便宜；及时止损优于沉没成本执念。

### 验证

```
$ ./test/install-update-e2e.sh
  先红 226/3（用例 27 三条全红）→ 绿 229/0
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis ../contentweave
  消费仓 4 个 · 通过 12 · 失败 0
$ bash -n 全受管 shell 脚本：OK
```

---

## 1.8.1 — 2026-09-27

### 修复：Makefile target 改名 `update` → `cw-update` 避免通用名冲突

**背景**：`make update` 是通用 target 名，消费仓将来自己加 Makefile 或有 `update` target 时会冲突。改为 `cw-update` / `cw-check` 更具体。

**改动**（1 项）：

- **Makefile 模板**：`update:` → `cw-update:`，`cw-check:` 不变。

**连带**：无受管文件变更（仅 Makefile 内容）；e2e 226 断言全绿；rollout-check 4 消费仓 12/0。

### 教训反思

**通用 target 名是公共 Makefile 的冲突源**：`make update` 简洁但承担将来冲突风险。`cw-update` 稍长但语义明确、不会与其他 `update` 目标碰撞。

### 验证

```
$ ./test/install-update-e2e.sh
   通过 226 · 失败 0
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis ../contentweave
   消费仓 4 个 · 通过 12 · 失败 0
$ bash -n 全受管 shell 脚本：OK
```

---

## 1.8.0 — 2026-09-27

### 新增：Makefile 快捷入口——消费仓 `make update` 一行升级

**背景**：消费仓运行 `./scripts/cw-update.sh` 路径长、首次要等 clone 缓存，用户常不知道命令在哪。加 Makefile 提供 `make update` / `make cw-check` / `make help` 三个快捷入口。

**改进**（1 项）：

- **Makefile 模板**：新增受管文件 `Makefile`（`make update` → `./scripts/cw-update.sh`，`make cw-check` → `./scripts/cw-update.sh --check`，`make help` → 列出可用命令）。受管文件数 20 → 21。

**连带**：`lib/render.sh` cw_list_files 加 `Makefile|Makefile`；test 断言 21 → 22；e2e 226 断言全绿；rollout-check 3 消费仓 9/0。

### 教训反思

**快捷入口是消费仓体验的关键**：`./scripts/cw-update.sh` 虽然自包含，但路径长、首次慢。Makefile 把更新操作从「知道路径」变成「知道命令」，降低使用门槛。

**受管文件新增必须同步测试断言**：cw_list_files 加一行，test 中 4 处 "21" 断言必须同步改 "22"，否则 CI 红。

### 验证

```
$ ./test/install-update-e2e.sh
   通过 226 · 失败 0
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis
   消费仓 3 个 · 通过 9 · 失败 0
$ bash -n 全受管 shell 脚本：OK
```

---

## 1.7.3 — 2026-09-27

### 新增：verify-md-bundle 验证技能生成器——QG-5 探针可复跑基建

**背景**：QG-5 探针每次随手写、不可复跑；同一功能在不同票上探针质量随心情波动。pstack 的 `create-verification-skill` 把验证做成一等基建：采访代码库 → 生成 `verify-<app>` → 交付前自证。md-bundle 有真实页面，适合作为首个试点。

**改进**（1 项）：

- **verify-md-bundle 技能**：在 md-bundle 的 `.opencode/skills/verify-md-bundle/` 创建验证技能（SKILL.md + 5 个特性文件）——Launch（`pnpm dev` → 端口 4173）/ Doctor（进程存活 + 端口占用 + 页面可加载）/ Drive（Playwright + 真实 data-testid）/ Evidence（截图 + DOM 快照 → `.artifacts/<票号>/`）/ Cleanup（杀进程 + 保留证据）/ Helpers（无）。特性地图覆盖：文件打开、编辑、导出、预览、分享。`SKILL.md` G1 出口加「验证技能调用」条款：对 md-bundle 仓，Sisyphus 优先调用 `verify-md-bundle` 技能跑探针。

**连带**：无受管文件变更（纯文档规则）；e2e 226 断言全绿；rollout-check 3 消费仓 9/0。

### 教训反思

**验证技能是验证基建化的有效模式**：从「随手写」到「可复跑基建」，消除「心情波动」。特性地图是验证技能的「知识库」，需要随应用演进而维护（P2 维护循环）。

**仅对 md-bundle 生成 verify-***：纯库仓收益低，保持轻量探针。md-bundle 有真实页面，QG-5 探针可固化。

### 验证

```
$ ./test/install-update-e2e.sh
  通过 226 · 失败 0
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis
  消费仓 3 个 · 通过 9 · 失败 0
$ bash -n 全受管 shell 脚本：OK
```

---

## 1.7.2 — 2026-09-27

### 新增：验证分离——G1 出口编排器独立跑 QG-5

**背景**：SKILL.md:183 声称「验证者（orchestrator，非实施者）」，但单会话模型下该规则**无机制保障**——同一 agent 既实施又验证。Omo 的 Atlas 已有委派机制（Sisyphus → Atlas），但 Atlas 既执行又验证（自证），没有解决验证者≠实施者。

**改进**（1 项）：

- **验证分离**：`SKILL.md` G1 出口 QG-5 段重写为「验证分离」机制——Atlas（执行者）完成 G1 实施后返回摘要（diff 统计 + 出口条件结果）；Sisyphus（编排器）**亲自跑 QG-5 探针**，不依赖 Atlas 的自证。**两层验证互补**：Atlas 的 `lsp_diagnostics` 作为最低门槛（语法/类型），Sisyphus 的 QG-5 作为应用专属验证（业务逻辑）。Sisyphus 持有跨票 SHA 视图，收口时 `--verified-sha` 拦截过期验证。

**连带**：无受管文件变更（纯文档规则）；e2e 226 断言全绿；rollout-check 3 消费仓 9/0。

### 教训反思

**验证分离是验证者≠实施者的机制保障**：E3 的闭环退出条件只解决了「验证要验证到什么程度」，没有解决「谁来验证」。验证分离通过「Atlas 实施 + Sisyphus 亲自跑 QG-5」真正分离了验证者≠实施者。

**两层验证互补是正确的设计**：Atlas 的 lsp_diagnostics 抓语法/类型错误（静态、与业务无关），Sisyphus 的 QG-5 抓业务逻辑错误（动态、与业务相关）。两层验证互补，不冲突。

### 验证

```
$ ./test/install-update-e2e.sh
  通过 226 · 失败 0
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis
  消费仓 3 个 · 通过 9 · 失败 0
$ bash -n 全受管 shell 脚本：OK
```

---

## 1.7.1 — 2026-09-27

### 新增：E4 overlap 预检——G1 开工前并行冲突拦截

**背景**：软件工厂续篇（`AI-doc/软件工厂-精华反哺CW.md` §二 E4）指出 CW 有 `Blocked by` 依赖序，但没有「扫 open PR 改动文件、重叠即停」的预检。两个并行 change 改同一文件时，当前机制无法阻止冲突——只有 merge 时才发现。

**改进**（1 项）：

- **overlap 预检**：`SKILL.md` G1 实施 gate 开头新增「第 0 步·overlap 预检」——扫 open PR 的 `--name-only`，与本票待改文件求交集；交集非空 → 停而报告「与 #N 改同一文件（<文件列表>），等该 PR 合并后再开工」。文件级判定（同一文件即重叠），不做行级判定。纯 `gh` 命令，无新脚本、无新依赖。

**连带**：无受管文件变更（纯文档规则）；e2e 226 断言全绿；rollout-check 3 消费仓 9/0。

### 教训反思

**文件级判定是正确的第一版**：行级判定需要 diff 分析，复杂且可能误报。文件级已经能覆盖大多数冲突场景，且确定性强。如果未来出现「同一文件不同区域」的真实冲突，再考虑行级增强。

**停报而非自动解决**：自动 rebase/merge 可能引入新问题。停报让人决策，符合「唯一人工介入 = risk-medium/high PR 合并确认」原则。

### 验证

```
$ ./test/install-update-e2e.sh
  通过 226 · 失败 0
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis
  消费仓 3 个 · 通过 9 · 失败 0
$ bash -n 全受管 shell 脚本：OK
```

---

## 1.7.0 — 2026-09-27

### 新增：E5 四拍速查卡——对抗 G8 process rot

**背景**：软件工厂续篇（`AI-doc/软件工厂-精华反哺CW.md` §二 E5）指出 SKILL.md 已膨胀至 280 行且持续增长（G8 风险）。agent 日常执行时不需要每次读完 280 行——他们需要一张「四拍速查卡」快速定位当前阶段的关键动作与出口条件。软件工厂用单文件 `AGENTS.md`（Isolate → Build → Prove → Ship）证明：把纪律压成一张纸，轻量、易读、易移植。

**改进**（1 项）：

- **四拍速查卡**：新增受管文件 `skills/change-workflow/agents-quick-reference.md`（79 行，≤80 行上限）——G0 规一 → G1 实施 → G2 提交 → G3/G4 收尾，每拍含关键动作 + 出口条件 + 「详见 SKILL.md §」引用；附质量门禁索引表（QG-1..7 / DQ-1..8 各一句话，两列表格）。`SKILL.md` 顶部（frontmatter 之后）加 3 行指引段：「日常执行照速查卡跑，细节回本文对应段」「单一事实来源：本文是完整参考」「同步规则：修改本文时同步检查速查卡」。不删除 SKILL.md 任何内容——速查卡是入口，SKILL.md 仍是完整参考。

**连带**：受管文件 20→21（+1 技能模板）；`lib/render.sh` 的 `cw_list_files` 加入 `agents-quick-reference.md`；e2e 受管文件计数断言 20→21（8 处）；`docs/agents/AGENTS.md` 模板行数表无需改（速查卡不在 `docs/agents/` glob 内）。

### 教训反思

**速查卡与完整参考的双层结构是抗 process rot 的有效模式**：SKILL.md 280 行中大量是「为什么」和「历史教训」——这些是设计文档，不是执行指令。速查卡只需要「做什么 + 出口条件 + 去哪查」。80 行限制迫使信息密度最大化，避免速查卡变成第二个 SKILL.md。

**同步规则必须显式声明**：速查卡只写关键动作，不复制详细规则；详细规则只在 SKILL.md 维护，速查卡通过「详见 SKILL.md §」引用。修改 SKILL.md 时同步检查速查卡——这个规则必须写在指引段里，否则内容漂移是必然的。

### 验证

```
$ ./test/install-update-e2e.sh
  通过 226 · 失败 0        # 受管文件计数 20→21，全部断言更新
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis
  消费仓 3 个 · 通过 9 · 失败 0    # 三仓冲突 0 · LOCAL 哨兵完整 · 覆盖 21/21
$ bash -n 全受管 shell 脚本：OK
$ shellcheck --severity=warning：无警告
```

---

## 1.6.0 — 2026-09-27

### 新增：pstack 反哺 P0——引用纪律 / 决策日志 / 验证时效 / 减法审计

**背景**：pstack 反哺方案（`AI-doc/pstack-feedback-change-workflow.md` §五）把质量管理的 8 处薄弱点按成本分档，P0 = 近乎免费的纪律层（Markdown 规则 + 小脚本，token 增量可忽略）。本版落地 P0 全部 4 项；「单文件编排」（E 系列）经用户裁示不在本轮，P1/P2（子代理委派、验证技能生成器、对抗式复审、盲测演进）亦不在。

**改进**（4 项）：

- **门禁引用纪律**：应用/豁免任何 QG/DQ，PR body 必须逐条写 `QG-x / DQ-x: <它改变了哪个具体决策>`（例：`QG-5: 用真实按键探针替代测试摘要`）；只提编号 = **空引用**，不予合并。挂载：`SKILL.md` G2 + `quality-gates.md` §七 + `pr-automation.sh` PR 模板新增「质量门禁引用」段
- **决策日志**：新增受管脚本 `scripts/decisions-log.sh`（157 行）——`add <阶段> <决策> <理由> <证据指针> <结果>` / `show [N]` / `path`；TSV 六列 `ts/phase/decision/why/evidence/result`，UTC 时间戳；单元格消毒（tab/换行/CR 折空格）+ 公式注入前缀防护（首字符 `= + - @` → `'`），与 pstack `show-me-your-work/log.sh` 逐语义对齐。`--file` > `DECISIONS_LOG` > 默认 `./.artifacts/decisions.tsv`（cwd 相对；本地不入库）。挂载：`SKILL.md` G3（frontier 循环每票一行）
- **验证时效（rebase 检测）**：QG-5 结论须标注「验证基于 `<sha>`」（`quality-gates.md` §六 + `SKILL.md` G1 出口）；`pr-automation.sh` 新增 `--verified-sha`（仅 `--resume-branch` 生效）——与分支 HEAD 前缀不符（rebase/追加提交后未重验）→ **拒收退 1**；未提供 → 仅警告（降级不阻塞）。检查置于 gh 前置校验之前：纯本地判定、可确定性测试（e2e 用例 25）
- **减法审计**：`quality-gates.md` 新增 §八——每季度（或 ≥6 票 change 收口后）统计「门禁捕获统计」表；连续两周期零捕获的门禁提案合并/退役（留痕+数据，不得凭印象删除）；最小充分集免退役

**连带**：受管文件 19→20（+1 脚本；docs 技能模板无新增）；`lib/render.sh:140` 陈旧计数注释（18/16）修正为 20/18；e2e **23 用例/194 断言 → 25 用例/222 断言**（新增用例 24：decisions-log 契约；用例 25：验证时效护栏五路径）；全仓文档行号引用重扫同步（含 quality-gates §八 插入后旧 §八 → §九）；`docs/agents/AGENTS.md` 模板行数表校对（quality-gates 362→402，另 5 处既存漂移一并对齐）。

### 修复

- **E2 呈现残留**：`docs/agents/evidence-capture.md` 两处上游 `before-and-after` CLI 引用改为既定品相「两列对比表格（| 修复前 | 修复后 |）或媒体链接，复用 E1 录制产物、不引 CLI 不引上传链」——与集成契约 §2.2 对齐
- **E2 PR 条款**：`SKILL.md` G2 补「成对证据（UI/行为变更）」显式条款——旧缺口：成对协议只在采集规范里，编排层无强制
- **E3 闭环退出**：`SKILL.md` G1 出口 `code-review` 补「闭环退出条件」语句（未解决项未清零→回修，至零问题或达上限 10，与 `cw-greploop.sh --max-iterations` 同款）
- **元数据校对**：`docs/agents/AGENTS.md` 模板行数表（quality-gates 362→402，另 5 处既存漂移一并对齐）

### 教训反思

**先红后绿在纪律层同样必要**：28 条新断言中，红相里 21 条失败、7 条「意外通过」（用例 24 的 3 条因「命令缺失 127 折叠为 1」、用例 25 的 4 条因旧参数拒收路径碰巧命中）——若不先跑红相，就分不清「新断言真的在守新行为」还是「碰巧通过」。红相 194/28 → 绿相 222/0。

**「验证过期」是最安静的失效：rebase 不改变「完成度」的外观，只作废证据。** 结论仍躺在票上、仍「看起来有效」——pstack 记录过「一次运行 21 条判定被静默作废」。机制选择「记录验证时 SHA + 收口比对」：一个判据同时覆盖 rebase（HEAD 重写）与追加提交（HEAD 前移）；检查放在 gh 校验之前，使其可离线确定性断言（用例 25 全离线）。

**降级语义要区分「缺失」与「不符」**：未提供 `--verified-sha` → 仅警告（不阻断既有流程）；提供了且不符 → 拒收（拦截确定失效）。把「没传」也当失败会把降级友好变成破坏性变更——门禁扩张时，兼容面同样要过红绿。

### 验证

```
$ ./test/install-update-e2e.sh
  通过 226 · 失败 0        # 首轮 222/0；缺口修复先红 222/4（4 条新断言首红）→ 绿 226/0
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis
  消费仓 3 个 · 通过 9 · 失败 0    # 三仓冲突 0 · LOCAL 哨兵完整 · 覆盖 20/20
$ ci.yml 9 步本地逐条复现：全过（语法 / shellcheck / bash 3.2 静态 / 占位符 / 模板头 / 换行 / 禁串 / qa-ship 锁 / e2e 226）
```

---

## 1.5.0 — 2026-09-27

### 新增：拆票自检脚本——quiz 人工确认退役，拆票质量可机检

**问题**：拆票（G0-POST）此前依赖外部 `to-tickets` 的「Quiz 用户确认」——它与本仓三处
「唯一人工介入 = risk-medium/high PR 合并确认」声明（`SKILL.md` / `task-tracking.md` /
`DESIGN.md`）自相矛盾；且拆票质量机检为零：QG-7 是 7 条 QG 中唯一「如何验证」没有可执行
命令的，「过细」在全仓无操作化定义。

**改进**：

- 新增受管脚本 `scripts/cw-tickets-check.sh`（733 行；发布前门禁，退 0 才放行）：C1 对账双射
  （草稿 / `--live` gh 双源）、C2 七字段、C3 QG-1 形态、C4 禁入信号、C5 Blocked by DAG
  （越界/自环/环 + 环路径）、C6 豁免显式、C7 规模钩子（≥6 票须 checkpoint 声明）、
  C8 粒度声明 + 票间 `What` 重叠（字符二元组 Jaccard ≥80，常量）；python3 缺失 fail-closed
- `SKILL.md`：G0-POST 拆票改为「票面草稿 → 脚本自检（C1-C8）→ 三项书面自答落款 spec issue
  评论 → 全绿自动发布 → `--live` 对账复核」；拆票环节零人工询问（升级仍限既有三类）
- `quality-gates.md`：QG-7「如何验证」补可执行命令——7 条 QG 的验证空缺全部收口；§四呼应
- `task-tracking.md`：§2 补「过粗/过细」声明制定义（下界机检 + 上界定性）；§3/§4 补回
  「接线归属」「标签」并新增「粒度」字段

### 修复

- `task-tracking.md` §4 子票模板与 §3 必含清单的字段漂移（漏「接线归属」「标签」，拆票机检
  无从执行）
- `config.example.conf` 的 `TOOLKIT_VERSION` 漂移（停留在 1.4.1，落后 VERSION 一个版本；本次对齐 1.5.0）
- 仓库文档计数同步：受管文件 18→19、e2e 22 用例/176 断言→23 用例/194 断言、ci.yml 步号 8→9、
  `scripts/AGENTS.md` 的「新脚本手工登记两处清单」说明修正（两处已是 glob，自动纳入）

### 教训反思

**「人工确认」若判据大部分可机检，就是继承性 holdover，不是 gate。** quiz 三问里的对账、
字段、形态、结构全部可由既有 QG/DQ 判据机械判定；无法机检的只剩三项语义判断——那应走
「声明制留痕 + 下游捕获」，而不是在唯一时机拦一个确认询问。退役后三处「唯一人工介入」
声明复真。

**仪式的替代品不是删除，而是判据机械化。** 直接删 quiz 会让拆票质量无人把关；本机制的
形状是「机检（脚本）+ 声明（落款 spec issue）+ 逃逸闭环（DQ-7 反查）」。C8「过细」只拦
明显形态（重叠 ≥80% 的重复切票），完整经济性判断显式留给审计与下游——能力边界写进脚本
头注，不假装有全量判据。

**bash 3.2 测试陷阱（实测，已写进 e2e 用例 23 头注）**：`set -e` 下【直调】不存在的命令 +
`|| rc=$?` 会把 127 折叠为 1，使「脚本缺失」与「正确拒收（退 1）」在断言层不可区分。
新断言一律用命令替换形态（保留 127）+ 输出内容断言——红相 16 条全部以 127 正确判红。

### 验证

```
$ ./test/install-update-e2e.sh
 通过 194 · 失败 0        # 先红证据：通过 178 · 失败 16（16 条新断言全部以 127 判红）
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis
 消费仓 3 个 · 通过 9 · 失败 0    # 三仓冲突 0 · LOCAL 哨兵完整 · 覆盖 19/19
$ ci.yml 9 步本地逐条复现：全过（新脚本自动纳入 scripts/*.sh glob；含 shellcheck / bash 3.2 静态）
```

---

## 1.4.2 — 2026-09-26

### 修复：受管模板残留源项目（md-bundle）特有值

**问题**：v1.4.1 及之前的受管模板/脚本/配置内嵌了源项目（一个编辑器应用）的特有值——
`apps/web`、`packages/editor|renderer`、`pnpm -r …` 门禁命令、`@md-bundle/web`、
`.spec.ts` 硬编码、md-bundle 标签表（landing/tabs/fsa/save/share + wave-4/5/6）、
ADR 文件名 `0002-editing-paradigm-*` 等。消费仓安装后得到指向错误目标的值：
接线归属指向不存在的目录、setup.sh 默认门禁命令在非 pnpm 仓直接失败。

**改进**：

- 模板全面去源项目化：`apps/web` → 「应用层」/`<E2E_DIR>` 占位符；`pnpm -r …` →
  「本仓门禁命令（`.change-workflow.conf` 的 `CMD_*`）」；标签表/ADR 树 → 按本仓填写的
  占位示例；incident 文档的命令与目录树改写为通用形态（教训保留）
- `setup.sh`：CMD_TYPECHECK/LINT/TEST 默认值由 `pnpm -r …` 改为空（留空 = 跳过该步）；
  `config.example.conf` 同步置空并注明「按本仓填写」
- CI 回归锁：「无仓库特有值残留」步骤的禁串清单追加
  `apps/web` / `packages/editor` / `packages/renderer` / `pnpm` / `@md-bundle`，
  检查范围扩至 `setup.sh` + `config.example.conf`；`test/install-update-e2e.sh`
  一致性用例同步镜像
- `SKILL.md` 的 `allowed-tools` 移除 `pnpm:*`（工具包自身不依赖 pnpm，门禁命令来自配置）

### 验证

```
$ ./test/install-update-e2e.sh
 通过 178 · 失败 0
$ bash -n setup.sh update.sh lib/render.sh scripts/*.sh test/*.sh   # 全过
```

---

## 1.4.1 — 2026-09-25

### 修复：升级后 .bak 累积成 untracked 噪音

**问题**：`update.sh` 对「未修改文件」的安全覆盖会先写 `<file>.bak`（回滚备份），但从不清理。
消费仓每次升级都攒一批 untracked `.bak`（三仓实测 13 个），污染 `git status`，并可能被
误卷进提交。

**改进**：

- `update.sh`：安全覆盖的 `.bak` 改为**收尾清理**（只清本类备份）。依据：该文件
  `current == baseline`，`.bak` 内容即基线、可由 git 追溯；且 `cw_atomic_cp` 是 temp+mv
  原子写，中途失败不留半截文件，`.bak` 对崩溃安全也无贡献
- `update.sh`：`--force` 覆盖的 `.bak` **保留** —— 它承载本地定制，是唯一副本
- 清理与其它文件是否冲突无关：每条 `.bak` 只对应一个已成功安全覆盖的文件；有冲突时
  消费仓目录反而更需要干净（冲突项已由 `.new` 标注）
- e2e：+2 断言。新增「安全覆盖不留 .bak（已清理）」「force 备份不被清理」；模式回归锁
  从安全覆盖路径迁到 `--force` 路径（`.bak` 仍须 644，防 mktemp 0600 泄漏）

### 教训反思

**备份文件的价值取决于内容是否可复现。** 安全覆盖的 `.bak` == 基线，git 里有；`--force`
的 `.bak` == 本地定制，别处没有。把两者一视同仁「都留着保平安」，代价是每次升级都往消费仓
丢一批噪音。区分「可复现」与「唯一副本」，才对得起清理动作。

**「仅无冲突时清理」这个第一版规则被 e2e 抓出。** 直觉是「有冲突说明用户正在人工解决，
保守点别动」，但冗余性是**逐文件**的，与其它文件状态无关。该规则会让存在任一冲突的仓永远
清不掉噪音 —— 恰好是噪音最难消的场景。红证由用例 5 给出（它本就带一个遗留冲突）。

### 验证

```
$ ./test/install-update-e2e.sh
 通过 178 · 失败 0
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis
 消费仓 3 个 · 通过 9 · 失败 0
```

---

## 1.4.0 — 2026-09-25

### 变更：移除 qa/ship 依赖（与逐票合 main 模型对齐）

**问题**：`qa`/`ship`（gstack）被列为流程编排的一部分，但两者与「1 task = 1 ticket = 1 分支
= 1 PR 逐票合 main」不兼容——`qa` 需要可运行的实例、`ship` 需要发版分支 + 发版 PR；而本流程的
浏览器验证已有 QG-5/QG-6 承担，发版只需 `VERSION`/`CHANGELOG`/tag。门禁唯一事实来源
`quality-gates.md` 从未引用这两个 skill。后果是文档留下无法回答的问题（「发版前 qa 在哪个分支跑」），
每轮交付多付一份与 gate 无关的 token。

**改进**：

- `skills/change-workflow/SKILL.md`：删除 `qa`/`ship` 全部引用（术语表、编排路线图第 ⑫⑬ 边、
  skill 调用总表两行、G3 措辞、明确不做）；「明确不纳入」改为显式说明外部 QA/发版 skill 不进入流程
- `docs/agents/task-tracking.md`：§7.2 删 qa/ship 行与 ship-测试重复 note，更名「执行后（提交前自审）」；
  §7.3/§7.4 去掉 ship 措辞；§7.5 闭环示意 `git-master`→`pr-automation.sh`（该残留早于脚本化实现）；
  **新增 §7.6「浏览器验证与发版」**：QG-5/QG-6 如何承担浏览器验证 + tag 发版流程
- `README.md`：gstack 依赖行去掉 `qa`/`ship`/`git-master`

### 教训反思

**门禁的唯一事实来源是 `quality-gates.md`，不是 skill 调用表。** `qa`/`ship` 被编排表列了半年，
门禁文档零引用——它们从未承重。判断一个依赖是否必需，先看它有没有对应的门禁条目，而不是看它
有没有被写进流程表。移除后 QG/DQ 判据一字未动，e2e 与消费仓滚动验证均全绿，反证了这一点。

**外部 skill 的模型假设必须与本流程对齐后才能纳入。** gstack 的 `qa`/`ship` 假设「工作累积在
长命分支、收尾时一次性 ship」；本流程是「逐票合 main」。模型不匹配时硬塞进流程，只会产生
「在哪个分支跑」这类无法回答的问题。落点放不对就该移除，而不是继续为它编解释。

**文档里的孤儿引用是负债。** `task-tracking.md` 的 `git-master` 早于 `pr-automation.sh`
脚本化实现，却留了半年——它会让人以为提交走的是 git skill 而非脚本。清理受管面时要连带扫
「同义但过期」的引用，别只删本次点名的那个。

### 验证

```
$ ./test/install-update-e2e.sh
 通过 176 · 失败 0
$ ./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis
 消费仓 3 个 · 通过 9 · 失败 0
```

---

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
- e2e：101 → 176 断言（+75），每项修复均先红后绿回归锁

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
 通过 176 · 失败 0            # 76 → 176：+100 断言（case 8 exec 位 +3、case 15 退出码契约 +14、case 16 符号链接 +3、case 17 受管脚本符号链接 +5、case 12 恶意源信任门 +2、case 18 父目录符号链接 +3、case 1/5 模式保持 +5、case 15 ALLOW_REPO +3 与 greploop 穿越 +3、case 19 空格 manifest +9、case 20 conf 末行守卫 +1、case 21 accept-local 符号链接闸 +3、case 21 accept-local 模式保持 +1、case 11 ./ 前缀归一 +3 与 --force 清 LOCAL 哨兵 +3、case 22 conf 解析器四实现一致 +7、case 15 greploop 符号链接围栏 +2、case 22 引号+注释组合 +4、case 19 CRLF 清单 +4、case 11 force 等值路径 +3、case 22 workflow 标签提取 +3、case 11 LOCAL+等值计数 +4、case 11 缺失+LOCAL 计数 +6、case 11 强制覆盖缺失+LOCAL 哨兵 +6）
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
