# conformance-generator capability

## Overview

一致性制品生成器能力：从人读 `anchors.md` 程序化生成机读 `conformance.json` + 哈希锁 `conformance.lock`，四规则机检（完备/无孤儿/可断言/来源非空），verify 语义比对 + 哈希核验，退出码 0/1/3 契约。

## ADDED Requirements

### Requirement: R-1 生成器四子命令契约

**验收叙述**：`cw-conformance.sh` **MUST** 提供 `scaffold` / `generate` / `lock` / `verify` 四子命令，退出码 **SHALL** 严格遵循 0=成功、1=内容错、3=环境缺（降级）契约，与 `cw-evidence.sh` 对齐。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-1.1 | exact | 四子命令均存在且可调用 | `cw-conformance.sh scaffold|generate|lock|verify --help` 均退 0 | design.md D2 |
| A-1.2 | exact | 退出码契约：内容错→1、环境缺→3 | `generate` 无 python3 退 3；`verify` 无 lock 退 3；篡改/缺文件退 1 | design.md D2 |

#### Scenario: 四子命令可调用

Given 用户运行 `cw-conformance.sh scaffold|generate|lock|verify --help`
When 子命令存在且可调用
Then 均退出码 0 并输出用法

#### Scenario: 退出码契约

Given 用户运行 `cw-conformance.sh generate` 且无 python3
When 环境缺 python3
Then 退出码 3 并打印降级提示

Given 用户运行 `cw-conformance.sh verify` 且无 conformance.lock
When 未锁定
Then 退出码 3

Given 用户篡改 conformance.json 后运行 verify
When 制品被篡改
Then 退出码 1 并列出篡改文件

### Requirement: R-2 anchors.md 确定性文法

**验收叙述**：`anchors.md` **SHALL** 为唯一解析面，采用裸 markdown 表，列名顺序 **MUST** 恰为 `id|kind|claim|assert|source`；requirement **MUST** 以 `^## (R-\d+) (.+)$` 开启；anchor id **MUST** 匹配 `^A-<n>\.\d+$` 且 `<n>` 回指 requirement。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-2.1 | exact | requirement 标题模式 | `^## R-1 .+$` 匹配 | design.md D1 |
| A-2.2 | exact | 表列名与顺序 | `id|kind|claim|assert|source` 逐字一致 | design.md D1 |
| A-2.3 | exact | anchor id 回指 | `A-1.1` 回指 `R-1` | design.md D1 |
| A-2.4 | exact | kind 取值域 | `exact|state-machine|perceptual` 三值之一 | design.md D1 |

#### Scenario: requirement 标题解析

Given anchors.md 含 `## R-1 验收叙述`
When generate 解析
Then 识别 requirement R-1 且 text 为 "验收叙述"

#### Scenario: 表列名顺序校验

Given anchors.md 表头为 `| id | kind | claim | assert | source |`
When generate 解析表格
Then 列名顺序逐字一致，否则退 1

#### Scenario: anchor id 回指校验

Given anchor A-1.1 存在但 requirement R-1 缺失
When generate 解析
Then 退 1 报「无孤儿」

#### Scenario: kind 取值域校验

Given anchor kind 为 "invalid"
When generate 解析
Then 退 1 报 kind 非法

### Requirement: R-3 四规则机检（完备/无孤儿/可断言/来源非空）

**验收叙述**：`generate` 与 `verify` **MUST** 内嵌同一套四规则 python，与 `cw-tickets-check.sh:check_conformance` **SHALL** 同词汇报错、同序解析。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-3.1 | state-machine | 完备性：每 requirement ≥1 anchor | 缺 anchor 退 1 报「完备性」 | design.md D3 |
| A-3.2 | state-machine | 无孤儿：anchor 回指存在 requirement | 孤儿退 1 报「无孤儿」 | design.md D3 |
| A-3.3 | exact | 可断言性：assert 含具体值 token | 无数字/引号/#hex/状态迁移词退 1 | design.md D3 |
| A-3.4 | exact | 来源非空：source 非空 | source 空退 1 报「来源非空」 | design.md D3 |

#### Scenario: 完备性检查

Given requirement 无 anchor
When generate 校验
Then 退 1 报「完备性」

#### Scenario: 无孤儿检查

Given anchor A-2.1 存在但 requirement R-2 缺失
When generate 校验
Then 退 1 报「无孤儿」

#### Scenario: 可断言性检查

Given assert 为 "渲染正确"（无具体值 token）
When generate 校验
Then 退 1 报「可断言性」

#### Scenario: 来源非空检查

Given source 为空
When generate 校验
Then 退 1 报「来源非空」

### Requirement: R-4 conformance.json 幂等投影

**验收叙述**：`generate` 两次运行 **SHALL** 产出字节完全相同的 `conformance.json`（键序固定 IC-1，`json.dumps(indent=2, ensure_ascii=False)`+结尾换行）。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-4.1 | exact | 幂等字节相等 | 两次 generate sha256 相等 | design.md IC-1 |

#### Scenario: 幂等性验证

Given 相同 anchors.md 运行两次 generate
When 对比两次产出的 conformance.json sha256
Then 两次 sha256 完全相等

### Requirement: R-5 conformance.lock 哈希锁

**验收叙述**：`lock` **MUST** 对 `conformance.json` + `baseline/*.png` 逐文件 sha256，写 `conformance.lock`（首行注释 + `sha256sum` 兼容格式，两空格，排序稳定）；perceptual 锚点但 baseline/ 无 png **SHALL** 退 1。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-5.1 | exact | lock 文件格式 | 首行注释 + `<hash>  <rel-path>` 两空格 | design.md IC-2 |
| A-5.2 | state-machine | perceptual 无 png 拒退 | baseline/ 空时 lock 退 1 | design.md D2 |

#### Scenario: lock 文件格式

Given conformance.json 和 baseline/cols-3.png 存在
When 运行 lock
Then conformance.lock 首行为注释，后续每行 `<hash>  <rel-path>` 两空格

#### Scenario: perceptual 无 png 拒退

Given 存在 perceptual 锚点但 baseline/ 目录无 .png
When 运行 lock
Then 退 1 并报错

### Requirement: R-6 verify 语义比对 + 哈希核验

**验收叙述**：`verify` **MUST** ①重投影 anchors.md 与 conformance.json 语义比对（JSON 相等，非字节）→漂移退 1；②lock 缺失 **SHALL** 退 3；③重算哈希，篡改/缺失/多出 **SHALL** 退 1 逐文件列出。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-6.1 | state-machine | 漂移检测 | anchors.md 改动未重跑 generate → verify 退 1 | design.md D2 |
| A-6.2 | exact | 无 lock 退 3 | 删 lock → verify 退 3 | design.md D2 |
| A-6.3 | exact | 篡改/缺失/多出检测 | 逐文件列出退 1 | design.md D2 |

#### Scenario: 漂移检测

Given anchors.md 修改后未重跑 generate
When 运行 verify
Then 退 1 并报「漂移」

#### Scenario: 无 lock 退 3

Given conformance.lock 不存在
When 运行 verify
Then 退出码 3

#### Scenario: 篡改/缺失/多出检测

Given conformance.json 被篡改一字符
When 运行 verify
Then 退 1 并列出篡改文件

Given baseline/cols-3.png 缺失
When 运行 verify
Then 退 1 并列出缺失文件

### Requirement: R-7 受管清单与安装

**验收叙述**：`scripts/cw-conformance.sh` **MUST** 纳入 `lib/render.sh:cw_list_files`，受管数 **SHALL** 为 24；安装/升级 **SHALL** 自动获得执行位（`cw_chmod_scripts` 从清单派生）。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-7.1 | exact | 受管清单含新脚本 | `cw_list_files` 输出含 `scripts/cw-conformance.sh` | design.md D5 |
| A-7.2 | exact | 受管数 24 | `manifest` 行数 = 24 | design.md D5 |

#### Scenario: 受管清单包含新脚本

Given 运行 `cw_list_files`
When 输出包含 `scripts/cw-conformance.sh|scripts/cw-conformance.sh`
Then 受管清单正确包含新脚本

#### Scenario: 受管数 24

Given 全新安装
When 统计 manifest 行数
Then 等于 24

### Requirement: R-8 降级契约（python3 缺失→退 3）

**验收叙述**：`generate`/`lock`/`verify` 缺 python3 时 **MUST** 打印 `⚠️ 降级：python3 不可用` 并退 3，**SHALL NOT** 静默当通过。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-8.1 | exact | 无 python3 退 3 | `PATH="/bin" cw-conformance.sh generate ...` 退 3 | design.md D2 |

#### Scenario: 无 python3 降级

Given PATH 不含 python3
When 运行 generate
Then 退出码 3 并打印 "⚠️ 降级：python3 不可用"

## Non-Goals

- 不采集截图（baseline png 由外部原型采集，生成器只校验存在性）
- 不生成 e2e 断言骨架
- 不解析自由格式原型文档
- 不调用/改 `cw-tickets-check.sh`
- 不做 T1-T3 与跨模型
- 不做 `--force`、不读 conf、无网络