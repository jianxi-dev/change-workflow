## 1. 撤销静态技能试点（消费仓）

- [x] 1.1 删除 md-bundle 的 `verify-md-bundle` 技能目录（SKILL.md + 5 特性文件 + README）
- [x] 1.2 清理试点产物（`apps/web/drive-temp.mjs`、`.artifacts/e2e-self-proof/`）

## 2. 探针形态约定（本仓）

- [x] 2.1 e2e 新增用例 27（3 断言：SKILL 探针形态条款 / SKILL 零 verify 引用 / evidence-capture 探针形态节）→ 先红
- [x] 2.2 `SKILL.md` G1 出口 3.5 条款重写为「探针形态（活代码优先）」
- [x] 2.3 `evidence-capture.md` 插入「四、探针形态（活代码优先）」节（原四/五/六顺延为五/六/七，§五→§六 引用同步）→ e2e 转绿

## 3. 验证

- [x] 3.1 运行 `bash -n` 静态检查所有受管 shell 脚本
- [x] 3.2 运行 `./test/install-update-e2e.sh` 确认全绿（27 用例 / 229 断言）
- [x] 3.3 运行 `./test/rollout-check.sh ../md-bundle ../mdpkg ../clairis ../contentweave` 确认消费仓无冲突

## 4. 发布准备

- [x] 4.1 更新 `VERSION`（1.8.1→1.8.2）+ `CHANGELOG.md`（修订条目）+ `config.example.conf` 三处对齐