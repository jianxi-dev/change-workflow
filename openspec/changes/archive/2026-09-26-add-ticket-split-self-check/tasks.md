## 1. 先红：e2e 断言先行

- [x] 1.1 在 `test/install-update-e2e.sh` 增加断言：新脚本随安装落地、可执行、`--help` 退出码契约（照既有脚本断言风格，约 `:216`/`:223` 处）——此时断言应为红
- [x] 1.2 新增夹具与断言：对账不符 → 退 1；禁入信号票 → 退 1；expand–contract 角色声明票 → 豁免通过（退 0）
- [x] 1.3 运行 `./test/install-update-e2e.sh` 并记录红色输出（DQ-3 先红证据，贴入实施记录与 CHANGELOG 反思）

## 2. 实现自检脚本

- [x] 2.1 创建 `scripts/cw-tickets-check.sh` 骨架：参数解析、退出码（0 全过 / 1 违规或用法错误）、日志风格（照 `pr-automation.sh` / `cw-evidence.sh`）
- [x] 2.2 实现 C1 对账双射（`gh issue list --json number,title` + tasks.md 解析，脚本化 `SKILL.md:151`）
- [x] 2.3 实现 C2 六字段 + C6 豁免显式声明
- [x] 2.4 实现 C3 QG-1 形态 + C4 禁入信号（复用 `quality-gates.md:50` 正则原样）
- [x] 2.5 实现 C5 Blocked by DAG 校验（集合内 / 无自环与环 / 拓扑序存在）
- [x] 2.6 实现 C7 规模钩子（票数 ≥6 须含 checkpoint 计划声明）
- [x] 2.7 实现 C8 粒度声明 + 票间 `What` 重叠检测 + expand–contract 角色豁免（重叠阈值实施时定为脚本常量）
- [x] 2.8 `bash -n` + shellcheck（warning）+ bash 3.2 静态检查通过；手工四种场景验证 0/1 行为

## 3. 受管面与 CI/e2e 清单同步

- [x] 3.1 `lib/render.sh:153` `cw_list_files` 注册新脚本（x-bit 由清单派生，不手改）
- [x] 3.2 更新 e2e 计数断言与脚本清单相关断言（受管文件数 18→19 等）
- [x] 3.3 更新 `.github/workflows/ci.yml` 脚本清单（`:21`/`:35`/`:43` 三处）——实施核验：三处均已是 `scripts/*.sh` glob，新脚本自动纳入，无需改动（证据：ci.yml 全步本地复现含新脚本全过）
- [x] 3.4 全量 `./test/install-update-e2e.sh` 转绿（先红后绿闭环）

## 4. 编排与规范改写

- [x] 4.1 `SKILL.md:140`：quiz 语义 → 自检协议（跑脚本 → 三项书面自答落款 spec issue 评论 → 全绿自动发布；升级仅保留 `:211` 三类）
- [x] 4.2 `SKILL.md:102` 表格行更新（去「含 quiz 用户确认」）；`SKILL.md:151` 对账自证改为调用脚本
- [x] 4.3 `quality-gates.md` QG-7「如何验证」(`:147`) 补可执行命令；§四(`:271`) 反向验收判据呼应
- [x] 4.4 `task-tracking.md` §2 补「过粗/过细」声明制定义；§4 模板补回「接线归属」「标签」两字段（漂移修复）
- [x] 4.5 核对 `SKILL.md:195` / `task-tracking.md:215` / `DESIGN.md:112` 三处「唯一人工介入」表述复真

## 5. 消费仓预演与发布

- [x] 5.1 本地逐条复现 CI 门禁全绿（9 步：语法/shellcheck/3.2 静态/占位符/模板头/换行/禁串/qa-ship 锁/e2e）
- [x] 5.2 `./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis`——实测：三仓冲突 0、LOCAL 哨兵完整、覆盖 19/19（md-bundle 的 `quality-gates.md` 为 LOCAL 哨兵 → 计「本地保留」跳过，无 `.new`、无需手动合并——优于任务预期，原「出 .new」假设有误）
- [x] 5.3 `VERSION` + `CHANGELOG.md` 同步（结构：新增/修复 → 教训反思 → 验证（贴 e2e 通过数）；config.example.conf 版本漂移一并对齐 1.5.0）
- [x] 5.4 显式 `git add` 目标文件提交（中文 Conventional Commit）×2（feat + docs-sync）；`git tag -a v1.5.0` 并推送 main/tag