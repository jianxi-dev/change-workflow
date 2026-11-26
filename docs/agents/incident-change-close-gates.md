<!-- change-workflow 工具包模板 —— 由 setup.sh 安装到目标项目 docs/agents/。
     示例值（模块列表 / 看板 ID / 质量门禁命令）请按目标项目调整；
     占位符 {{REPO}} / {{PROJECT_ID}} / {{STATUS_FIELD_ID}} / {{OPT_*}} 由 setup.sh 自动替换。 -->

# 事故复盘：change 收口两道门禁陷阱（锚点可断言性口径 / .artifacts 证据污染）

> 最后更新：2026-11-26

> 适用：本仓库所有走 change-workflow 的 change，尤其在 G0-POST 拆票与 G2 收口提交两个节点。
> 案例来源：`editor-refine-batch1`（#1397–#1404，2026-11-23 归档）。

两道门禁各拦过一次以上，都是「前置校验通过、后置校验拒收」的静默漂移。目标：后来者一次过。

---

## 陷阱一：锚点 assert 的两套口径不一致（G0-POST 拆票被拦）

### 现象

同一份 `anchors.md`，生成器放行、检查器拒收：

```text
$ ./scripts/cw-conformance.sh generate editor-refine-batch1
（退 0，conformance.json 已写出）

$ ./scripts/cw-tickets-check.sh --change editor-refine-batch1
[C3/C4] 可断言性: anchor A-1.2 的 assert 空或不含具体值 token（数字/引号串/#hex/状态迁移关键词）
... 共 10 条
```

纯中文断言（如「严格不相等」「裁剪态保持」「键名相同」）能过 `generate`，过不了 `tickets-check`。

### 根因

两个脚本对「可断言」的实现不同，且刻意重复（`cw-conformance.sh` 头注第 3 条声明两者必须同词汇报）。

- `scripts/cw-conformance.sh` 的 generate 只校验 `assert` **非空**（第 205 行 `if not assert_val`），不看内容。
- `scripts/cw-tickets-check.sh` 的 `check_conformance` 走 `has_token()`（第 680-692 行），要求 assert 命中下列任一 token：
  - `[0-9]` 数字
  - `"` 或 `'` 引号串
  - `#[0-9a-fA-F]{3,8}` 十六进制色值
  - 状态迁移关键词：`→` `->` `变为` `进入` `迁移到` `切换到` `回到` `恢复`

两个口径都叫「可断言性」，但严格程度不同。`generate` 宽松，`tickets-check` 严格，于是出现「生成通过、检查失败」。

### 处置

给被拦的 assert 补具体值 token，且**不改语义**：

```text
严格不相等          → 两者 data-icon 不同（相同数 0）
裁剪态保持          → 拖动 1 次后裁剪态保持 → 不弹回普通选中态
```

改完 `anchors.md` 必须按顺序重跑三者，缺一不可：

```bash
./scripts/cw-conformance.sh generate <change>
./scripts/cw-conformance.sh lock    <change>
./scripts/cw-conformance.sh verify  <change>
```

`verify` 会重投影 `anchors.md` 与 `conformance.json` 做语义比对，只改 `anchors.md` 而不重跑 `generate` 会被抓出投影漂移；`lock` 只锁制品层（`conformance.json` + `baseline/*.png`），不锁 `anchors.md`。

### 预防

写 `anchors.md` 时直接按 `tickets-check` 的严格口径写 assert（含数字 / 引号串 / `#hex` / 状态迁移关键词之一）。G0-POST 自检前先跑一次草稿模式的 `cw-tickets-check.sh`，别等发布前才发现。

---

## 陷阱二：`.artifacts/` 证据被 git exclude，G2 白名单反复拒收

### 现象

收口提交源码时，白名单校验报「白名单外工作区改动」，被点名的却是**别的票**的历史证据：

```text
$ ./scripts/pr-automation.sh --resume-branch <branch> --files <源码...>
❌ 白名单外工作区改动，拒绝提交:
   M .artifacts/1349/crop-coordinate-01.png
   M .artifacts/1349/state-coverage.json
   M .artifacts/1391/image-edit-quiet-01.png
   ...
```

源码一个没提，拒收的全是 `.artifacts/` 下旧票的截图与 `state-coverage.json`。

### 根因

- `.artifacts/` 在 `.git/info/exclude` 第 14 行（`.artifacts/`），验证：

  ```bash
  git check-ignore -v --no-index .artifacts/
  # .git/info/exclude:14:.artifacts/    .artifacts/
  ```

  注意：因为目录内有已跟踪文件，不带 `--no-index` 时 `git check-ignore .artifacts/` 会退 1（报未忽略），必须加 `--no-index` 才能看到 exclude 命中。
- 证据文件是 `git add -f` 入库的已跟踪文件（`git ls-files .artifacts` 约 954 条）。已跟踪文件不受 ignore 规则保护，照样进入 `git status --porcelain`。
- 任何一次回归 e2e 都会重写这些证据：`crop-coordinate.spec.ts` 写 `.artifacts/1349/`，`image-edit-quiet.spec.ts` 写 `.artifacts/1391/`。重写后历史证据变成 `M`，收口时 `validate_whitelist` 逐个比对 `git status --porcelain` 与 `--files`，白名单里没有它们，于是拒收。
- `validate_whitelist` 的 `in_files` 是**逐路径精确匹配**（`scripts/pr-automation.sh` 第 225-229 行，`[[ "${p#./}" == "$rel" ]]`）。`--files .artifacts/<票号>` 只匹配目录路径本身，不覆盖目录内的已跟踪文件，所以传目录名无效。

### 处置

收口前复位历史证据，再立刻提交：

```bash
# 复位全部历史证据（或只复位被点名的票号目录）
git checkout -- .artifacts/

# 立即跑收口（其门禁只跑 tsc / eslint / vitest，不含 e2e，不会再污染 .artifacts/）
./scripts/pr-automation.sh --resume-branch <branch> \
  --files <源码...> .artifacts/<本票号>/<证据1>.png .artifacts/<本票号>/state-coverage.json
```

本票自己的证据目录要在 `--files` 里**逐个文件列出**，只传目录名对已跟踪文件不生效。

### 预防

- UISurface 票的 e2e 用独立 `ART = .artifacts/<票号>`，把证据圈在本票目录内。
- 收口前半步固定执行 `git checkout -- .artifacts/`，把别的票的历史证据复位。
- 不要用「跑一遍全量 e2e」替代「跑本票 e2e」：全量 e2e 会顺带重写历史票的证据目录，直接把收口卡死。

---

## 相关

- `scripts/cw-conformance.sh`（四规则生成器，头注第 3 条声明与 checker 同词）
- `scripts/cw-tickets-check.sh`（`check_conformance` / `has_token`，G0-POST 门禁）
- `scripts/pr-automation.sh`（`validate_whitelist` / `in_files`，G2 收口提交）
- `docs/agents/quality-gates.md`（QG-1..QG-10 质量门禁）
- 同类事故：`docs/agents/incident-merge-local-workspace.md`、`docs/agents/incident-uncommitted-work-loss.md`
