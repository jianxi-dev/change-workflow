<!-- change-workflow 工具包模板 —— 由 setup.sh 安装到目标项目 docs/agents/。
     示例值（模块列表 / 看板 ID / 质量门禁命令）请按目标项目调整；
     占位符 {{REPO}} / {{PROJECT_ID}} / {{STATUS_FIELD_ID}} / {{OPT_*}} 由 setup.sh 自动替换。 -->

# 数据面落点规范

> 最后更新：2026-11-26
>
> 机检脚本：`scripts/cw-data-surface.sh`（`new` / `tickets` / `diff` / `pr` / `signals` / `selftest`；`pr` 用于缺陷修复线，见 §五）。

## 一、为什么需要它

仓库已经有三层配置底座（defaults / user / state + 快照 + 热应用）、三个文件型扩展点（snippets / templates / theme.toml）和一条 AI 受控写通路（`patch_config`）。缺的不是机制，是**判断某次改动该不该走这条通路、以及走了之后怎么证明真落地**。

`scripts/cw-conformance.sh` 头注记录过一次代价：*门禁「有定义、无机检、靠自证」→ 实测约 20 处偏差*。同一类失败在数据面上表现为：

- 需求写了「可配置」，实现仍是 `const X = [...]` 硬编码；
- change 级写了数据文件，**没有一张票真正落地**（与 QG-3「导出 API 无接线」同构）；
- 字段加进了 `settings.json`，但没进 `validate_config`，或没接桥接，改了不生效。

所以本规范只做两件事：**给触发信号**、**给可机检的六栏契约**。

## 二、触发信号（命中任一即适用）

**信号 A — 路径**：change 的 `design.md` / `tasks.md` / `proposal.md` 出现下列任一（完整清单见 `.change-workflow.conf` 的 `DATA_SURFACE_PATHS` 覆盖；下表为参考实现的示例，按本仓实际填写）：

```
src-tauri/src/config.rs                     配置 schema 与校验
src-tauri/src/extensions.rs                 文件型扩展点扫描
src/lib/extensions/                         theme.toml / bundle 桥接
src/lib/capabilities.ts                     能力开关注册表
src/hooks/useConfig.ts                      前后端配置桥
src/ui/icons.ts | src/editors/icons.ts      两套图标表
src/editors/orchestration/roulette*.ts      轮盘几何与视图
src/editors/orchestration/floating-toolbar.ts  轮盘动作定义
src/editors/orchestration/horizontal-toolbar.ts
src/editors/orchestration/block-menu.ts
src/styles/tokens.css                       主题 token 词表
src/components/SettingsView.tsx             设置面板
```

**信号 B — 文案**：文本命中 `可配置 / 数据文件 / 配置项 / 开关 / 白名单 / 主题色 / 图标 / 快捷键 / 轮盘 / 菜单项 / 排序 / 隐藏 / 预设`（完整清单见 `DATA_SURFACE_KEYWORDS`）。

> **误报优先**：多填六栏是几分钟成本；漏报则是又一处硬编码活过整个 change。`.change-workflow.conf` 的 `UI_PATH_GLOB` 注释记着这个教训——当年为躲误报把 glob 收窄，结果 17 个 UI 修复 PR 全部旁路。不要用「意图判断」代替信号，意图不可机检。

## 三、六栏契约（写进 `design.md` 的 `## 数据面` 小节）

固定四列表头，每个落点一行，**六行齐全**：

```markdown
## 数据面

<!-- 下行为示例（取自参考实现），路径与符号按本仓实际替换 -->

| 落点 | 位置 | 载体/符号 | 判据 |
|---|---|---|---|
| 规格 | design-system:§6 | — | 新增/删除色必须先有 spec 条款 |
| 存储 | src-tauri/src/config.rs | roulette_sectors | 枚举白名单，未知值拒绝 |
| 校验 | src-tauri/src/config.rs | validate_config | 重复 id / 越界 / 与默认冲突 |
| 桥接 | src/hooks/useConfig.ts | applyRustConfig | 未知 id 忽略并聚合告警 |
| 消费 | src/editors/orchestration/floating-toolbar.ts | createRoulette | 数组顺序即显示顺序 |
| 回滚 | snapshots/ | restore_config_snapshot | 写前快照，一步恢复 |
```

字段规则：

| 列 | 规则 | 机检方式 |
|---|---|---|
| 落点 | 六值之一：`规格`/`存储`/`校验`/`桥接`/`消费`/`回滚` | 集合相等，缺一即违规 |
| 位置 | 文件路径、目录，或 `design-system:§N` / `D<n>` | `diff`：存储/校验/桥接/消费四行必须真实存在 |
| 载体/符号 | **可 grep 的字面符号**（函数名/字段名），不带参数与说明；`规格` 行可写 `—` | `diff`：必须在该文件里 grep 到 |
| 判据 | 一句话说明「怎么算对」，不得为空或占位 | 禁止 `TBD`/`待定`/`TODO`/`—` |

四条设计约束：

1. **不写像素值**。位置只表达落点，坐标属于设计系统条款（如 `docs/design/system/spec.md`，本仓有则引用条款号，无则写 `design-system:§N` 记号）。
2. **`消费` 行不许指向会退化为常量数组的组件**——落地时该组件应读注册表，而不是新增 `const X = [`。
3. **`回滚` 不是可选栏**。AI 可塑的三要素是「真相源唯一 + 写路径收敛 + 可逆兜底」，缺回滚等于让 AI 直改。
4. **一个 change 一张表**；票级只声明自己负责哪几行（见下节），不复制表。

## 四、票面字段（第 8 字段）

数据面票的票面在既有六字段之外加一行：

```markdown
**数据面**: 存储,桥接
```

规则：

- 值域 = 六栏落点名，逗号分隔；
- **所有数据面票的并集必须覆盖 change 表里的六行**（`tickets` 子命令机检）；
- 纯 UI 引用（例如只是把已有配置接到界面）声明 `消费` 即可；
- 无数据面的票写 `**数据面**: 无`，与 `no-ui-impact` 同构，须显式写，缺字段不等于「无」。

## 四点五、新增面步骤（参考实现脚手架）

> 本节描述的面脚手架（`scripts/surface-new.sh`）是参考实现，**不随工具包发布**（它硬编码了 Rust/Tauri 的目录布局）。本仓有等价脚手架时按下述六步办；没有时手写同样六步。

新增一个数据面（面 = `{id, 默认文件名, 项形状, 校验器}`）时，用脚手架生成三样骨架，再手写校验与接线：

```bash
bash scripts/surface-new.sh <id> --shape <menu-item|icon|capsule|toolbar> \
  --change <change名> [--dry-run]
```

`--change` 给出时把六栏表追加进 `openspec/changes/<change>/design.md` 的 `## 数据面` 小节；省略则只打印模板不落盘。

| 步骤 | 做什么 | 脚手架产物 / 手写 |
|---|---|---|
| 1 登记 | 在 `src-tauri/src/surfaces.rs` 的 `SURFACES` 表追加一行 `SurfaceSpec { id, default_file, shape }` | 脚本追加（已含同 id 行则跳过） |
| 2 默认文件 | 新增 `src-tauri/src/resources/<id>.default.json`，作为默认集合唯一来源 | 脚本生成模板（合法 JSON，字段与形状校验器对齐） |
| 3 形状校验 | 在 `surfaces.rs` 加 `validate_<shape>_item` 分支（缺字段/类型错/未知 id 过滤并聚合告警） | **手写**（脚本不生成 match 分支） |
| 4 消费端接线 | 消费端改读面（`src/lib/dataSurfaces/store.ts` 的 `getMenuItems`/`getIconSpec`/`getCapsuleItems`/`getSurfaceItems`），不留兜底常量 | **手写** |
| 5 六栏表 | 在 change 的 `design.md` 写 `## 数据面` 六栏表 | 脚本追加模板（落点值严格等于 规格/存储/校验/桥接/消费/回滚） |
| 6 回滚快照 | 沿用 `snapshots/` + `restore_config_snapshot`（写前快照 10 份） | 既有机制，无需新增 |

要点：

- **形状是闭集**：`menu-item` / `icon` / `capsule` / `toolbar`，与 `surfaces.rs` 的 `SurfaceShape` 枚举一一对应；脚本拒绝未知 shape 与非法 id（`[a-z][a-z0-9-]*`）。
- **幂等**：同一 id 重复运行不覆盖既有非空默认文件或既有登记行，命中即打印「已存在，跳过」并退 0；写盘走临时文件 + `mv`，无半成品。
- **保真**：六栏落点值由脚本硬编码，与 `cw-data-surface.sh` 的 `REQUIRED_LABELS` 逐字一致；模板不含占位字段名。
- **自检**：`bash scripts/surface-new.test.sh`（转调 `--self-test`）验证形状解析、六值精确、幂等、非法入参拒绝；CI 可直接跑。
- 脚手架只生成模板，**不生成校验器与消费端接线**——那是面作者的手写部分（D8「面作者只填形状与校验」）。

## 五、何时跑

| 时点 | 命令 | 失败处理 |
|---|---|---|
| G0 阶段二（propose 产出 design.md 后） | `./scripts/cw-data-surface.sh new <change>` | fix-first：回 propose 补齐六栏，不得进入拆票 |
| G0-POST（拆票自检，紧接 `cw-tickets-check.sh`） | `./scripts/cw-data-surface.sh tickets <change>` | 就地重切票，补齐落点归属 |
| G1 出口（code-review 之后） | `./scripts/cw-data-surface.sh diff <change>` | 未落地 → 回修，不得 commit |
| 缺陷修复线（`defect-workflow.md` 数据面门） | `./scripts/cw-data-surface.sh pr <基线ref>` | 命中 → 修复须走既有数据链路或升级 change，禁止新增硬编码常量 |

`pr` 模式针对缺陷修复：缺陷没有 change 目录可挂信号，直接对 `git diff <基线>..HEAD`（含未提交改动）的文件名单做路径交集（全路径或同名文件）。`selftest` 含 `pr` 三个用例，可在无 git 历史的消费仓自证。

退出码沿用工具包约定：`0` 通过或未命中信号（打印 `SKIP`）/ `1` 契约违规 / `3` 环境缺失（change 目录或草稿缺失，降级不判失败）。

## 六、与既有门禁的关系

| 既有 | 管什么 | 本规范补什么 |
|---|---|---|
| L-1 需求输入门 | 「对标/学习某产品」类 change 的**来源**质量 | 来源合格之后的**落点**分配 |
| QG-3 接线归属 | 新导出 API 由哪张票接线 | 配置字段→校验→桥接→消费这条链的归属 |
| QG-7 纵向切片 | 每票用户可见 | 数据面票的可见性来自「改 JSON 即生效」，AC 应写成「改文件后页面变化」 |
| C1–C8 票面机检 | 票形态 | 第 8 字段与六栏覆盖（本规范 C10） |
| `cw-conformance.sh` | UI 断言锚点 | 数据面不产生像素断言，故不进 `conformance.json` |

编号说明：**C9 已被视觉锚点预留**（见 `AGENTS.md` 设计段），数据面检查在本仓称 **C10**。

## 七、明确不该文件化的

沿用此类数据文件化盘点已有的边界，仍有效：

| 数据 | 去处 | 理由 |
|---|---|---|
| API key | OS 钥匙串 | 密钥不进配置文件 |
| 编辑器/视图实例 | 内存 Map | 实例不是可序列化状态 |
| 运行时缓存 / 索引 | 应用支持目录 | 可重建的生成态 |
| 派生状态（最近文件/滚动位置） | `state/state.json` | 用户行为产物，AI 不直写 |
| 会执行代码的扩展 | 不进数据文件 | 保持无执行面；代码级插件另设信任门 |

另外两条通用判据：

- **没有消费者的目录不建**（不要提前造空目录）；
- **同一概念的多张注册表必须同时覆盖**（例如两套图标表），否则不同入口会漂移。

## 八、归属与升级

本规范与 `scripts/cw-data-surface.sh` **已随工具包发布**（属 `cw_list_files` 的 `docs/agents/*.md` 与显式脚本条目），消费仓在 `.change-workflow.conf` 里只保留 `DATA_SURFACE_PATHS` / `DATA_SURFACE_KEYWORDS` 两个具体值。

历史：本规范起初先在单个消费仓落地（判据需要真实拦截样本），跑满两个 change、判据无实质改动后才整包上游化。**新出现的门禁/规范建议走同一条路**：先在消费仓验证，稳定后再进模板，避免给所有消费仓加未经检验的负担。

修改本规范时注意：脚本的 `REQUIRED_LABELS`（六栏落点名）与本文 §三 必须逐字一致，否则 `new` / `tickets` 子命令与文档对不上。
