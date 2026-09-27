## ADDED Requirements

### Requirement: G1 出口验证分离机制

系统 SHALL 在 G1 出口实施验证分离：Atlas（执行者）完成 G1 实施后返回摘要，Sisyphus（编排器）亲自跑 QG-5 探针，不依赖 Atlas 的自证。

#### Scenario: Atlas 完成后 Sisyphus 亲自验证

- **WHEN** Atlas 完成 G1 实施并返回摘要
- **THEN** Sisyphus 亲自跑 QG-5 探针，把原始输出粘贴到票上

#### Scenario: Sisyphus 持有跨票 SHA 视图

- **WHEN** Sisyphus 跑 QG-5 探针
- **THEN** 记录「验证基于 `<sha>`」，收口时 `--verified-sha` 拦截过期验证

#### Scenario: Atlas 自证作为最低门槛

- **WHEN** Atlas 完成 G1 实施
- **THEN** Atlas 先跑 lsp_diagnostics（通用验证），作为最低门槛；Sisyphus 的 QG-5 探针作为应用专属验证，是更高门槛
