## 1. 受管文件清单更新

- [x] 1.1 在 `lib/render.sh` 的 `cw_list_files` 函数中加入 `agents-quick-reference.md`（受管文件 20 → 21）
- [x] 1.2 更新 `test/install-update-e2e.sh` 中受管文件计数断言 20 → 21
- [x] 1.3 运行 `./test/install-update-e2e.sh` 确认全绿（226+ 断言）

## 2. 四拍速查卡模板创建

- [x] 2.1 创建 `skills/change-workflow/agents-quick-reference.md` 模板，首行加 `<!-- change-workflow 工具包模板` 头
- [x] 2.2 编写 G0 规一段（spec 归一化 → 拆票 → 分支创建 + DQ-1 检查 + 出口条件）
- [x] 2.3 编写 G1 实施段（每票实现 → QG-5 探针 → 先红后绿 + 出口条件）
- [x] 2.4 编写 G2 提交段（PR body 逐条写 `QG-x: 具体决策` + 出口条件）
- [x] 2.5 编写 G3/G4 收尾段（frontier 推进 → 归档 → 减法审计 + 出口条件）
- [x] 2.6 编写质量门禁索引表（QG-1..7 / DQ-1..8 各一句话，两列表格）
- [x] 2.7 每拍末尾加「详见 SKILL.md §<段名>」引用标注
- [x] 2.8 验证文件行数 ≤ 80 行

## 3. SKILL.md 顶部指引

- [x] 3.1 在 `skills/change-workflow/SKILL.md` 顶部（标题下方）加 ≤ 5 行指引段：「日常执行照 `agents-quick-reference.md` 四拍跑，细节回本文对应段」
- [x] 3.2 验证指引段在渲染安装后仍存在（剥模板头时不被误删）

## 4. 验证与发布准备

- [x] 4.1 运行 `bash -n` 静态检查所有受管 shell 脚本
- [x] 4.2 运行 shellcheck（如可用）确认无新警告
- [x] 4.3 运行 `./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis` 确认消费仓无冲突
- [x] 4.4 更新 `VERSION` + `CHANGELOG.md`（新增条目含四拍速查卡 + 行数上限 + 受管文件计数变更）
