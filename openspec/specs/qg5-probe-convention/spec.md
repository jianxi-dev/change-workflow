# qg5-probe-convention Specification

## Purpose
TBD - created by archiving change qg5-probe-convention. Update Purpose after archive.
## Requirements
### Requirement: QG-5 探针形态（活代码优先）

系统 SHALL 规定 QG-5 探针的形态选择规则：优先复用仓库既有测试基建的活代码用例（e2e spec），轻量探针为降级路径。

#### Scenario: 仓库已有 e2e 基建

- **WHEN** 仓库已配置 e2e 套件（`CMD_E2E`）
- **THEN** QG-5 探针写成/扩展 e2e 用例——随代码维护、可复跑、CI 强制

#### Scenario: 无测试基建或需特定驱动

- **WHEN** 仓库无 e2e 套件，或本票验证需要特定驱动方式
- **THEN** 写轻量探针（脚本化命令/手工操作 + 原始输出），遵循 `evidence-capture.md` 证据约定（before/after 成对、原始输出、落盘 `.artifacts/<票号>/`）

### Requirement: 禁止静态验证技能副本

系统 SHALL NOT 为验证另建静态技能文档（`verify-*`）承载驱动知识（选择器、命令、特性地图）。

#### Scenario: 高频迭代仓库的腐烂风险

- **WHEN** 仓库处于功能迭代期
- **THEN** 静态技能文档必然过期且与活代码平行漂移，驱动知识只活在 e2e 用例与仓库自身文档中

