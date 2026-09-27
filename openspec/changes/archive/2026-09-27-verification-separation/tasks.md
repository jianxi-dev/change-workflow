## 1. SKILL.md G1 出口验证分离

- [x] 1.1 在 `skills/change-workflow/SKILL.md` G1 出口加「验证分离」段（Atlas 实施 → Sisyphus 亲自跑 QG-5 + 跨票 SHA 视图 + 两层验证互补）
- [x] 1.2 验证插入后 SKILL.md 结构完整（G0-G4 五个 gate 仍完整）

## 2. 验证

- [x] 2.1 运行 `bash -n` 静态检查所有受管 shell 脚本
- [x] 2.2 运行 `./test/install-update-e2e.sh` 确认全绿
- [x] 2.3 运行 `./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis` 确认消费仓无冲突

## 3. 发布准备

- [x] 3.1 更新 `VERSION` + `CHANGELOG.md`（新增条目含验证分离 + 两层验证互补 + 跨票 SHA 视图）
