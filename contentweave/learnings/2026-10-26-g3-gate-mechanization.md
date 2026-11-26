---
type: learning
title: G3 三项为何形同虚设：断点不在事故现场，而在脚本退出之后（2026-10-26）
captured_at: '2026-10-25T23:53:01.203Z'
captured_via: capture-cli
---

# G3 三项为何形同虚设：断点不在事故现场，而在脚本退出之后（2026-10-26）

**来源**：jianxi-dev/change-workflow v1.13.2（commit c59feba）

## 事故

2026-10-25 一晚五个 change 全部只做 `push + merge`，G3 三项一项没跑：

| 项 | 实际状态 |
|---|---|
| sync-gbrain | 索引停在 10-21，落后 150 文件 / 1145 chunks |
| decisions-log | `.artifacts/decisions.tsv` 停在 10-21 |
| learn | 写进了 `.omo/notepads/learnings.md` —— 该目录在 `.gitignore`，gbrain 走 git 索引，根本读不到 |

## 两层根因（都不是「忘了」）

**第一层：判据无机检。** `pr-automation.sh` 在 push **前**跑四件套门禁，G3 在 push **后**，天然没人拦；`.change-workflow.conf` 里只有 `CMD_TYPECHECK/LINT/TEST/E2E`，没有任何 G3 相关命令。这与仓库里 QG-1、QG-5 的来历完全一致——**写进文档的判据，不机械化就等于没有**。

**第二层（更隐蔽）：流程断在「以提问结束回合」上。** SKILL.md 把 G4 收口写成「列出剩余清单 + 给出下一项建议 + **询问是否继续**」。agent 提问 → 回合终止 → 用户以为流程在等自己 → 实际流程已经走完。**没有东西在用户回答之后唤醒下一票**。这一层的杀伤力在于它看起来是设计，不是 bug。

## 修法

1. `scripts/cw-g3-check.sh`（三项新鲜度机检：gbrain `last_sync_at` ≥ HEAD、`decisions.tsv` mtime ≥ HEAD、`--change` 时 tasks.md 不比决策日志新）。退 1 不得进 G4。
2. `scripts/cw-next-change.sh`（下一 change 自动选取：`[change=<名>/` 归组 + Blocked by 解析 + 按子票最近更新倒序）。只在并列(<1h)/只剩研讨类/队列空三种情形停。
3. `pr-automation.sh` 退出前打印实测 G3 结果 + 三条补齐命令 + 下一票推荐。**提示语会把代理引向追问，命令不会**——这是判断「该写文档还是该写脚本」的分界线。
4. 删除文档矛盾：明写两处人工停点（risk-high 合并是设计性停点、跨 change 切换），不再声称「全流程唯一停点」。

## 可迁移的四条

- **「必调」+ 无脚本 = 可不调**。给任何「必做」条款配一条可执行判据，否则它只是愿望。
- **流程断线优先看「回合在哪终止」**，而不是看 agent 忘了什么。以提问结尾的自动化流程，等于在提问处 `exit 0`。
- **提示（prompt）与命令（script）的选择标准**：需要判断力的留给 prompt，需要确定性的写进脚本并在退出路径打印。少判一次就少一次漂移。
- **同一机制被两次反转时，配套文本往往只改了一半**。1.11.1 全风险 auto-merge → 1.13.0 改回 high 人工，但 `SKILL.md` 的「唯一人工点」是 v1.11.1 遗留句子且从未回滚。改语义时用 `grep` 扫受管面里旧语义措辞，比通读文档可靠。

## 验证

```
./test/install-update-e2e.sh        → 通过 360 · 失败 0（新增用例 41）
./test/rollout-check.sh <四仓>       → 受管 29 · 冲突 0 · LOCAL 哨兵完整
./scripts/cw-g3-check.sh            → 在本仓判红（缺 decisions.tsv），判据有效
./scripts/cw-next-change.sh         → 在 contentweave 退 1（子票全关闭 → 该走 G4）
```
