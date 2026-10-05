# 验收锚点 — cw-conformance-generator

## R-1 生成器四子命令契约

`cw-conformance.sh` 提供 `scaffold` / `generate` / `lock` / `verify` 四子命令，退出码严格遵循 0=成功、1=内容错、3=环境缺（降级）契约，与 `cw-evidence.sh` 对齐。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-1.1 | exact | 四子命令均存在且可调用 | `cw-conformance.sh scaffold/generate/lock/verify --help` 均退 0 | design.md D2 |
| A-1.2 | exact | 退出码契约：内容错→1、环境缺→3 | `generate` 无 python3 退 3；`verify` 无 lock 退 3；篡改/缺文件退 1 | design.md D2 |

## R-2 anchors.md 确定性文法

`anchors.md` 为唯一解析面，采用裸 markdown 表，列名顺序恰为 `id|kind|claim|assert|source`；requirement 以 `^## (R-\d+) (.+)$` 开启；anchor id 匹配 `^A-<n>\.\d+$` 且 `<n>` 回指 requirement。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-2.1 | exact | requirement 标题模式 | `^## R-1 .+$` 匹配 | design.md D1 |
| A-2.2 | exact | 表列名与顺序 | `id/kind/claim/assert/source` 逐字一致 | design.md D1 |
| A-2.3 | exact | anchor id 回指 | `A-1.1` 回指 `R-1` | design.md D1 |
| A-2.4 | exact | kind 取值域 | `exact/state-machine/perceptual` 三值之一 | design.md D1 |

## R-3 四规则机检（完备/无孤儿/可断言/来源非空）

`generate` 与 `verify` 内嵌同一套四规则 python，与 `cw-tickets-check.sh:check_conformance` 同词汇报错、同序解析。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-3.1 | state-machine | 完备性：每 requirement ≥1 anchor | 缺 anchor 退 1 报「完备性」 | design.md D3 |
| A-3.2 | state-machine | 无孤儿：anchor 回指存在 requirement | 孤儿退 1 报「无孤儿」 | design.md D3 |
| A-3.3 | exact | 可断言性：assert 含具体值 token | 无数字/引号/#hex/状态迁移词退 1 | design.md D3 |
| A-3.4 | exact | 来源非空：source 非空 | source 空退 1 报「来源非空」 | design.md D3 |

## R-4 conformance.json 幂等投影

`generate` 两次运行产出字节完全相同的 `conformance.json`（键序固定 IC-1，`json.dumps(indent=2, ensure_ascii=False)`+结尾换行）。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-4.1 | exact | 幂等字节相等 | 两次 generate sha256 相等 | design.md IC-1 |

## R-5 conformance.lock 哈希锁

`lock` 对 `conformance.json` + `baseline/*.png` 逐文件 sha256，写 `conformance.lock`（首行注释 + `sha256sum` 兼容格式，两空格，排序稳定）；perceptual 锚点但 baseline/ 无 png→退 1。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-5.1 | exact | lock 文件格式 | 首行注释 + `<hash>  <rel-path>` 两空格 | design.md IC-2 |
| A-5.2 | state-machine | perceptual 无 png 拒退 | baseline/ 空时 lock 退 1 | design.md D2 |

## R-6 verify 语义比对 + 哈希核验

`verify` ①重投影 anchors.md 与 conformance.json 语义比对（JSON 相等，非字节）→漂移退 1；②lock 缺失→退 3；③重算哈希，篡改/缺失/多出→退 1 逐文件列出。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-6.1 | state-machine | 漂移检测 | anchors.md 改动未重跑 generate → verify 退 1 | design.md D2 |
| A-6.2 | exact | 无 lock 退 3 | 删 lock → verify 退 3 | design.md D2 |
| A-6.3 | exact | 篡改/缺失/多出检测 | 逐文件列出退 1 | design.md D2 |

## R-7 受管清单与安装

`scripts/cw-conformance.sh` 纳入 `lib/render.sh:cw_list_files`，受管数 23→24；安装/升级自动获得执行位（`cw_chmod_scripts` 从清单派生）。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-7.1 | exact | 受管清单含新脚本 | `cw_list_files` 输出含 `scripts/cw-conformance.sh` | design.md D5 |
| A-7.2 | exact | 受管数 24 | `manifest` 行数 = 24 | design.md D5 |

## R-8 降级契约（python3 缺失→退 3）

`generate`/`lock`/`verify` 缺 python3 时打印 `⚠️ 降级：python3 不可用` 并退 3，不静默当通过。

| id | kind | claim | assert | source |
|---|---|---|---|---|
| A-8.1 | exact | 无 python3 退 3 | `PATH="/bin" cw-conformance.sh generate ...` 退 3 | design.md D2 |
