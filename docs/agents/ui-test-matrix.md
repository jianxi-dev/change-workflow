<!-- change-workflow 工具包模板 —— 由 setup.sh 安装到目标项目 docs/agents/。
     示例值（模块列表 / 看板 ID / 质量门禁命令）请按目标项目调整；
     占位符 {{REPO}} / {{PROJECT_ID}} / {{STATUS_FIELD_ID}} / {{OPT_*}} 由 setup.sh 自动替换。 -->

# UI 状态矩阵（交互面）

> 最后更新：2026-11-26
>
> 表内的测试文件路径与票号取自参考实现，按本仓实际替换。

**生效**：2026-11-03 ｜ **适用**：所有 `ui-surface` 票（label `ui-surface` 或 diff 触及前端源码与样式）

## 为什么有这份文件

2026-11-03 消费仓一次走查报出 17 条问题，而全量验证命令全绿。复盘后确认根因不是「漏跑命令」，而是**测试只覆盖了实现者想到的那一个状态**：

- 手柄只测了「块手柄」，没测空行「+」→ 悬停误弹转换菜单逃逸
- 单元格手柄只测初始态，没测「内容变化后」→ 图标不刷新逃逸
- 大纲浮层用 `locator.hover()` 瞬移进面板 → 6px 空隙导致消失逃逸
- 「每一行都有图标」的选择器恰好排除了唯一没有图标的那行

这份矩阵是**验收清单**，不是文档装饰：票面验收必须回指本文件的对应行。

## 规则

1. **每个控件必须走完自己的状态列**。缺态 = 未完成，不得以「主要路径可用」结案。
2. **每个状态必须有断言，且断言的是计算值**（`getComputedStyle` / `getBoundingClientRect` / 真实事件），不是「元素存在」。
3. 未覆盖的状态必须在票面标 `untested` 并写明原因；PR 里没有这条说明 → 不允许合并。
4. hover 类断言**禁止**一步 `locator.hover()` 到底：指针路径必须分步，关键过渡区（浮层与触发器之间的空隙）必须停顿。用 `e2e/helpers/ui-probe.ts` 的 `moveThrough`。
5. 数值锚点只从 `e2e/fixtures/editor-anchors.ts` 取，spec 里不写魔法数字。
6. **图标变更必须在字形层断言，不能只断言 `data-icon` 名**。`data-icon` 是代理属性：图标名不同≠字形不同形（#1433 旧有序图标与无序同形却名不同）。字形层断言两处：单测 `src/__tests__/editor/icon-glyphs.test.ts`（路径 SSOT 同源 + 左缘标记列形状签名）、e2e `e2e/editors/ordered-list-icon.spec.ts`（真实渲染栅格化 + 带签名）。新增 / 修改图标时同步维护这两处。

## 矩阵

状态标记：`✅` 已覆盖 ｜ `⛔` 已知缺口（已开票） ｜ `🟡` 部分覆盖（须写明未覆盖的那一段与人工验证方式） ｜ `—` 不适用

### 块手柄

| 状态 | 期望 | 覆盖 | 票 |
|---|---|---|---|
| 指针在正文块内 | 手柄淡入，锚在指针所在行 | ✅ `block-menu.spec.ts` / `ui-fidelity.spec.ts` | — |
| 手柄本体尺寸 | 42×26 药丸 | ✅ `ui-fidelity.spec.ts` | — |
| 块型 → 图标 | 标题 H1–H6 / 引用 / 分割线 / 有序·无序 / 任务 / 代码 各自图标 | ✅ `ui-fidelity.spec.ts`；**字形层** `editors/ordered-list-icon.spec.ts`（#1433） | — |
| 空行「+」悬停 | 不弹转换菜单 | ✅ `ui-fidelity.spec.ts` | — |
| 空行「+」点击 | 打开插入菜单，光标落该行 | ✅ `block-menu.spec.ts` | — |
| 拖拽 ≥4px | 整块高亮 + 松手重排 | ✅ `block-menu.spec.ts` | — |
| 键盘输入中 | 手柄隐藏 | ✅ `block-menu.spec.ts` | — |
| 切换块型后 | 图标立即刷新，不残留 | ✅ `ui-fidelity.spec.ts` | — |

### 块菜单

| 状态 | 期望 | 覆盖 | 票 |
|---|---|---|---|
| 打开 | 宽 236 / 行高 32 | ✅ `ui-fidelity.spec.ts` | — |
| 「转为」项数 | 10 项，5 列 × 2 行网格，当前型高亮 | ✅ `ui-fidelity.spec.ts` | — |
| 行内图标 | 每行 1 个 `svg[data-icon]`，18px | ✅ `ui-fidelity.spec.ts` | — |
| 「在下方添加」 | 有图标 + 右侧 chevron + 向右展开二级面板，父菜单高度不变 | ✅ `ui-fidelity.spec.ts` / `block-menu.spec.ts` | — |
| 表格块 | 标题行/标题列/均分列宽/删除 | ⛔ 菜单被清空只剩一行 | #114 |
| 结构动作（复制/剪切/上下移/缩进/删除） | 直接改源码，其余字节不变 | ✅ `block-menu.spec.ts` + `blockActions.test.ts` | — |
| 类型（高亮块） | 二级面板 13 型，切换只改 `[!type]` 标记 | ✅ `block-menu.spec.ts` | — |
| 颜色 | 二级面板（字色 + 底色） | ⛔ 未实现 | #136 |
| 表格结构项（标题行/列/均分列宽） | GFM 无法表达，暂不渲染 | ⛔ 待定（#114 评论） | #114 |
| Esc / 滚动 / 外部点击 | 收起 | ✅ `block-menu.spec.ts` | — |
| 菜单打开时移动指针 | 不 retarget、不召唤别的手柄 | ✅ `block-menu.spec.ts` | — |

### 表格

| 状态 | 期望 | 覆盖 | 票 |
|---|---|---|---|
| 悬停表格 | 不出现左上角圆点 | ✅ `ui-fidelity.spec.ts` | — |
| 单元格编辑面 | 支持 `/` 插入 + 行内格式 | ⛔ 仅 `input[type=text]` | #112 |
| 单元格手柄 | 空→「+」，有内容→转换 | ✅ `ui-fidelity.spec.ts` | — |
| 单元格工具条 | 单格不出现；≥2 行才出现合并；无背景色 | ⛔ 单格即出现，含背景色 | #115 |
| 新增行/列后 | 结构正确、源码单行约束保持 | ✅ `table-decorations.spec.ts` | — |

### 大纲浮层

| 状态 | 期望 | 覆盖 | 票 |
|---|---|---|---|
| 无标题文档 | 不渲染大纲入口 | ✅ `ui-fidelity.spec.ts` | — |
| 悬停按钮 | 展开 | ✅ `ui-fidelity.spec.ts` | — |
| 穿过按钮→面板空隙 | 保持展开 | ✅ `ui-fidelity.spec.ts` | — |
| 点击钉住 / Esc / 外部点击 | 钉住 / 收起 / 收起 | ✅ `ui-fidelity.spec.ts` | — |
| 离开整体 | 200ms 后收起（延迟不粘住） | ✅ `ui-fidelity.spec.ts` | — |
| 列表 | 跳过 ``` 与 ~~~ 围栏（含未闭合） | ✅ `src/__tests__/components/Sidebar/Outline.test.ts` | — |
| 多页签 | 跟随当前页签 | ✅ `outline-menu.spec.ts` | — |

### 输入

| 状态 | 期望 | 覆盖 | 票 |
|---|---|---|---|
| 列表回车 | 续写标记，有序自增 | ✅ `smart-input.spec.ts` | — |
| 任务项回车 | 续写 `- [ ] `，`[x]` 新项不继承勾选 | ✅ `smartInput.test.ts` / `smart-input.spec.ts` | — |
| 空列表项回车 | 退出列表 | ✅ `smart-input.spec.ts` | — |
| 全角 `，`/`／` | 落成半角；代码块与行内代码内不转；单事务 | ✅ `smartInput.test.ts` / `smart-input.spec.ts` | — |
| 中文 composition | 不丢字、不提前提交 | ⛔ 未覆盖 | #112 / #113 |
| 媒体插入（图片/视频） | 桌面端弹系统选择器，文件落到文档同级 `assets/`，源码写相对引用 | 🟡 取文件后全链路有单测（`mediaPicker.test.ts` 6 条 + Rust `import_media` 2 条）；**系统对话框本身无法 headless 驱动**，需 `npm run tauri dev` 人工点一次 | #103 |

### 弹层（悬停打开类）

规则来源：`docs/design/approved/popup-lifecycle/spec.md`。三次同源缺陷（`#328` / `#374` / 1.1）都穿过了「瞬移 hover」用例。

| 状态 | 期望 | 覆盖 | 票 |
|---|---|---|---|
| 悬停触发器 | 面板出现 | ✅ `status-bar-visibility.spec.ts` | — |
| 跨间隙（停顿 ≥200ms） | 面板保持可见 | ✅ `status-bar-visibility.spec.ts` | — |
| 面板内停留 ≥500ms | 面板保持可见 | ✅ `status-bar-visibility.spec.ts` | — |
| 面板内点选 | 设定并关闭 | ✅ `status-bar-visibility.spec.ts` | — |
| 外部点击 | 关闭、无残留节点 | ✅ `status-bar-visibility.spec.ts` | — |
| `Esc` | 关闭、无残留节点 | ✅ `status-bar-visibility.spec.ts` | — |
| 滚动 / 尺寸变化 | 关闭 | 🟡 代码已接监听；e2e 未构造滚动容器，人工验证一次 | 1.1 |
| 父级卸载（隐藏态状态栏） | 面板不随父级消失 | ✅ `status-bar-visibility.spec.ts` | — |
| 卸载清理 | 定时器与监听器清除 | 🟡 无 e2e；靠 `useEffect` 返回清理函数，人工复核 | 1.1 |
| 可访问性 | `aria-haspopup` / `aria-expanded` / `role="menu"` / `menuitemradio` + `aria-checked` | ✅ `status-bar-visibility.spec.ts` | — |
| 点击语义 | 单击触发器按固定次序循环，面板保持并高亮新项 | ✅ `status-bar-visibility.spec.ts` | — |

## 怎么用

票面写：

```
状态覆盖：见 docs/agents/ui-test-matrix.md#表格
untested：<状态> —— <原因>
```

G1 出口检查：本票涉及的控件，其矩阵行从 ⛔ → ✅（或写明为何留 ⛔）。修掉的缺口必须把对应 `test.fixme` 改成正式用例——**改选择器绕过不算**。
