## Context

- CW 是**编排层**：`docs/agents/*.md` 是**受管模板**（安装到消费仓），非 openspec main spec；`scripts/*.sh` 与 `workflows/*.yml` 同装到消费仓。
- 约束：无编译、无运行时依赖（bash + gh + git + python3）；bash 3.2 兼容；降级友好；受管面变更必须同步 `lib/render.sh` / `test/install-update-e2e.sh` / `ci.yml`。
- 前序：v1.10.0 `cw-mechanized-quality-gates` 建立了锚点机检、一致性制品约定、CI 三层核验、证据 manifest、§八 三指标退役判据；本 change 是其**生成器**补齐。
- **两条硬约束（用户裁定）**：① **不依赖人工兜底**——质量靠机制与措施；② **规格双形态**——既有机读制品，也有能读懂的文字。
- **§八**（`quality-gates.md` §八）减法审计：门禁只增不减 → 本 change **不新增门禁条目**，只给现有机制装生成器。

## Goals / Non-Goals

**Goals:**

1. 把「一致性制品生成」在 G0 编码为**可执行机制**（`cw-conformance.sh` 四子命令），而非约定。
2. `anchors.md` 为**唯一解析面**（人写一次、任意 markdown 查看器可读）；JSON 永远是投影。
3. 四规则（完备性/无孤儿/可断言性/来源非空）与 `cw-tickets-check.sh:check_conformance` **刻意重复、同词汇报错、同序解析**。
4. `lock` 只锁制品层（`conformance.json` + `baseline/*.png`），不含 `anchors.md`（改它被 verify 投影比对抓住）。
5. 退出码 0/1/3 对齐 `cw-evidence.sh`：内容错→1，环境缺→3。
6. 受管面 +1（`scripts/cw-conformance.sh`），受管数 23→24。
7. **自举 dogfood**：本 change 自己的制品由生成器产出并通过 verify。

**Non-Goals:**

- ✗ 不采集截图（baseline png 由外部原型采集，生成器只校验存在性）
- ✗ 不生成 e2e 断言骨架（留待后续）
- ✗ 不解析自由格式原型文档（如 `functional-spec.md` 原样表）
- ✗ 不调用/改 `cw-tickets-check.sh`（独立、不调用）
- ✗ 不做 T1-T3 与跨模型（`evidence-check.yml` 职责）
- ✗ 不做 `--force`、不读 conf、无网络

## Decisions

### D1 —— `anchors.md` 确定性文法（唯一解析面）

**决策**：`anchors.md` 采用裸 markdown 表，列名与顺序**恰为** `id|kind|claim|assert|source`；requirement 以 `^## (R-\d+) (.+)$` 开启；其后至表头之间非空行 = `text`（合并为单段，折叠空白）。anchor id 匹配 `^A-<n>\.\d+$` 且 `<n>`==所在 R-`<n>`；`kind` ∈ `exact|state-machine|perceptual`；`source` 非空。

**理由**：人读层不可丢（QG-1 前置定义）；无 fenced block、不嵌 spec.md —— 对无 openspec 消费仓同样成立；确定性文法使解析器可靠、报错可定位。

**备选**：YAML/JSON 前置（否决——人读层丢失）；fenced code block（否决——解析脆弱、渲染器差异）。

### D2 —— 生成器四子命令与退出码契约

**决策**：
- `scaffold <change>`：生成 `anchors.md` 骨架（含 1 注释示例行 `# 示例：...`）；已存在→拒退 1
- `generate <change>`：解析 `anchors.md`→四规则校验→原子写 `conformance.json`（键序固定 = IC-1：`{change, requirements:[{id,text,anchors:[{id,claim,kind,assert,source}]}]}`，`json.dumps(indent=2, ensure_ascii=False)`+结尾换行→幂等字节）；目标是符号链接→退 1
- `lock <change>`：对 `conformance.json` + `baseline/*.png` 逐文件 sha256 → 写 `conformance.lock`（首行注释 `# change-workflow 制品哈希锁 v1…`，其后每行 `<hash>  <rel-path>` 两空格，排序稳定）；perceptual 锚点但 baseline/ 无 png→退 1
- `verify <change>`：①重投影 `anchors.md` 与 `conformance.json` **语义比对**（JSON 相等，非字节）→漂移退 1；②lock 缺失→退 3；③重算哈希，篡改/缺失/多出→退 1 逐文件列出
- 退出码：0=成功；1=内容错（解析失败/四规则违规/篡改/缺文件/目录不存在/符号链接）；3=环境缺（python3 缺失/未锁定/无制品）

**理由**：内容错必须拦截（fail-closed），环境缺必须可区分（不静默当通过）；对齐 `cw-evidence.sh` 契约，调用方（SKILL.md 编排）据此决定是否升级用户。

**备选**：统一退 1（否决——降级与失败不可区分，A2 修正的真实缺陷）；退 2 表示降级（否决——无语义增益，增加认知负担）。

### D3 —— 四规则刻意重复（与 checker 同源同序）

**决策**：`generate/verify` 内嵌**刻意重复**的同一套四规则 python；脚本头注与 `cw-tickets-check.sh:check_conformance` 互指，标「语法/规则改动须 checker+generator+e2e 三处同步」。

**理由**：checker 在消费仓运行（G0-POST 门禁），generator 在工具包源/消费仓 G0 运行。两者**必须**同词汇报错、同序解析，否则「生成通过、检查失败」的静默漂移不可接受。仓库既有 `conf_get` 式「刻意重复」惯例（lib/render.sh 与三份消费侧副本）。

**备选**：共享库（否决——消费仓无 lib/，脚本装过去后不依赖 lib/）。

### D4 —— `conformance.lock` 仅锁制品层

**决策**：lock 内容仅 `conformance.json` + `baseline/*.png`（**不含 anchors.md**）；首行注释 `# change-workflow 制品哈希锁 v1（cw-conformance.sh lock 生成；禁止手改）`；其后每行 `sha256sum` 兼容格式 `<hash>  <path>`（两空格，路径相对 change-dir，排序稳定）。

**理由**：改 `anchors.md` 会被 verify 的投影比对（语义比对，非字节）抓住；lock 只锁「制品层」，避免「改源文件→lock 也要改」的循环依赖。

**备选**：lock 含 anchors.md（否决——源文件变更会导致 lock 失效，需额外机制同步）。

### D5 —— 受管数 23 → 24

**决策**：`lib/render.sh` 的 `cw_list_files` 在 `cw-tickets-check.sh` 行后追加 `echo "scripts/cw-conformance.sh|scripts/cw-conformance.sh"`。

**理由**：新增受管脚本必须进清单，安装/升级自动获得执行位（`cw_chmod_scripts` 从清单派生），避免 1.2.0/1.3.0 两次同因缺陷。

**备选**：硬编码 chmod 名单（否决——曾两次漏加，清单派生是唯一可靠策略）。

### D6 —— e2e 契约锁（先红后绿）

**决策**：新增用例 `[36] cw-conformance.sh 一致性制品生成器契约锁`，覆盖：
1. 五处受管计数断言 23→24
2. scaffold+最小合法 anchors.md→generate 退 0，`conformance.json` 含 `A-1.1` 且 schema 字段齐全
3. 删 source 值→generate 退 1
4. generate 两次 sha256 相等（幂等）
5. lock→verify 退 0；篡改 conformance.json 一字符→verify 退 1；删 lock→verify 退 3
6. PATH 去 python3→generate 退 3

**理由**：DQ-3 先红后绿；最小集锁定生成器核心契约。

## Risks / Trade-offs

- **baseline 投毒（最大风险）** → ①程序化解析规格表（非手填）；②条目带 `source`（原型截图#/URL+时间戳）；③baseline 变更走**独立模型复核 + 哈希锁**。
- **生成器与 checker 漂移** → 刻意重复 + 头注互指 + e2e 三处同步回归锁。
- **受管面 +1 的连带破碎** → `cw_list_files` / e2e 计数断言（23→24）/ 模板头计数 / `ci.yml` 三处同步；先红后绿锁定。
- **消费仓 LOCAL 哨兵** → md-bundle 的 `quality-gates.md` 是 `LOCAL`，升级只写 `.new` + 退 1，须人工合并（这本身强制审查语义变更）。

## Migration Plan

1. 实现 → 全 CI 门禁本地复现 → 发版（`VERSION` + `CHANGELOG.md` + `config.example.conf:12` 三处）→ tag → push。
2. 消费仓升级：`update.sh` → 新增 `cw-conformance.sh` 直接安装；`quality-gates.md` / `evidence-capture.md` 等若有 LOCAL 哨兵 → 写 `.new` + 退 1，须人工合并。
3. `test/rollout-check.sh` 确认冲突 0、LOCAL 哨兵完整、覆盖数一致。
4. 回滚：revert 合并提交即可。
5. 自举验证：本 change 自己的 `anchors.md` → `generate` → `lock` → `verify` 全绿，作为回归锁。

## Open Questions

1. e2e 断言骨架生成（留待后续 change，当前 Non-Goal）。
2. `perceptual` 锚点的 baseline png 采集自动化（当前只校验存在性，采集留人工/外部工具）。

## Implementation Contract（冻结 2026-10-05，实施阶段不得偏离）

### IC-1 `conformance.json`（机读锚点层）

位置：`openspec/changes/<change>/conformance.json`（无 openspec 的消费仓：`docs/requirements/<change>/conformance.json`）。

```json
{
  "change": "<name>",
  "requirements": [
    {"id": "R-<n>", "text": "<人读验收叙述>", "anchors": [
      {"id": "A-<n>.<m>", "claim": "<可判真伪一句>",
       "kind": "exact | state-machine | perceptual",
       "assert": "<可执行断言描述，须含具体值>",
       "source": "<原型§/截图#/决策#/一手观察>"}
    ]}
  ]
}
```

G0 机检（`cw-tickets-check.sh` C3/C4 扩展）：**完备性**（每 requirement ≥1 anchor）、**无孤儿**（anchor 回指存在 requirement）、**可断言性**（assert 非空且含具体值 token：`[0-9]` 或引号串或 `#hex` 或状态迁移关键词）、**来源非空**。

### IC-2 `conformance.lock`（哈希锁）

位置：`openspec/changes/<change>/conformance.lock`。

首行注释：`# change-workflow 制品哈希锁 v1（cw-conformance.sh lock 生成；禁止手改）`。

其后每行：`<sha256>  <rel-path>`（两空格，路径相对 change-dir，排序稳定）。仅含 `conformance.json` + `baseline/*.png`。

### IC-3 解析目录优先级

`openspec/changes/<n>/` 优先，回退 `docs/requirements/<n>/`；均不存在→generate/verify 退 1。

### IC-4 写盘原子性 + 符号链接拒绝

统一 `mktemp` + `mv` 原子替换；目标是符号链接→退 1（C2 对齐 `lib/render.sh:cw_refuse_symlink`）。

### IC-5 sha256 双实现

`shasum -a 256` 回退 `sha256sum`（与 `lib/render.sh:cw_sha` 同构）。

### IC-6 e2e 契约锁（先红后绿）

新增：受管数断言 23→24；用例 36 六条核心断言。

### IC-7 非目标（本票不做）

不采集截图；不生成 e2e 断言骨架；不解析自由格式原型文档；不调用/改 `cw-tickets-check.sh`；不做 T1-T3 与跨模型；不做 `--force`、不读 conf、无网络。