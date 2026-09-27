## Why

当前 CW 有 `Blocked by` 依赖序（DAG），但没有「扫 open PR 改动文件、重叠即停」的预检。两个并行 change 改同一文件时，当前机制无法阻止冲突——只有 merge 时才发现。软件工厂的 `new-feature` 开工前 `gh pr list` + 查未提交工作，有重叠就停而报告，补这个前篇遗漏的缺口。

## What Changes

- 新增 G1 第 0 步 overlap 预检（在 SKILL.md G1 实施 gate 开头）：
  - 扫 open PR 的 `--name-only`，与待改文件交集非空即停
  - 停而报告「与 #N 改同一文件」，等该 PR 合并后再开工
  - 纯 `gh` 命令，无新脚本、无新依赖
- 不改变现有 G0-G4 流程语义——只在 G1 开工前加一道预检

## Capabilities

### New Capabilities
- `overlap-precheck`: G1 开工前 overlap 预检的触发条件、扫描逻辑、停报行为

### Modified Capabilities
<!-- 无现有 spec 的需求变更 -->

## Impact

- **修改文件**：`skills/change-workflow/SKILL.md`（G1 实施 gate 开头加第 0 步）
- **无新增文件**：纯文档规则，无新脚本
- **消费仓影响**：无（SKILL.md 是受管文件，升级自动获得）
