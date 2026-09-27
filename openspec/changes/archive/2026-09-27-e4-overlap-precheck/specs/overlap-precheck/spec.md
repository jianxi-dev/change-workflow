## ADDED Requirements

### Requirement: G1 开工前 overlap 预检

系统 SHALL 在 G1 实施 gate 的建分支步骤之前，扫描当前仓库所有 open PR 的改动文件列表，与本票待改文件求交集。交集非空时 MUST 停止开工并报告冲突 PR 编号。

#### Scenario: 无 overlap时正常开工

- **WHEN** agent 准备对某票执行 G1 实施
- **THEN** 扫描所有 open PR 的 `--name-only`，与本票待改文件无交集 → 允许开工

#### Scenario: 有 overlap 时停而报告

- **WHEN** 扫描发现 open PR #N 已改本票待改文件
- **THEN** 停止开工，报告「与 #N 改同一文件（<文件列表>），等该 PR 合并后再开工」

#### Scenario: 文件级重叠判定

- **WHEN** 判定重叠
- **THEN** 以文件路径为粒度（同一文件即重叠），不做行级判定
