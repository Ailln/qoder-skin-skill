---
name: qoder-skin
description: 给 Qoder / Qoder CN 编辑器做自定义皮肤——生成并安装 VS Code 颜色主题 VSIX，再通过本地 CDP 注入背景图和毛玻璃材质。当用户说「给 Qoder 换肤」「做一套 Qoder 主题」「Qoder 加背景图 / 二次元皮肤 / 壁纸」「改 Qoder 配色」，或要修改、验证、卸载已有 Qoder 皮肤时使用。不适用于 VS Code、Cursor 等其他编辑器的换肤。
---

# Qoder 换肤

在**不修改应用安装包、不动 `app.asar`、不重新签名**的前提下，为 Qoder 做一套完整皮肤。

## 两层结构

| 层 | 做什么 | 怎么装 | 稳定性 |
|---|---|---|---|
| 一、颜色主题 | 编辑器、语法高亮、侧栏、终端、Diff、Qoder 私有 `aicoding.*` 槽位 | VSIX 扩展 | 从 Dock 正常启动也生效 |
| 二、运行时注入 | 全窗口背景图、半透明、`backdrop-filter`、Quest 页面背景 | 启动时开 `127.0.0.1` CDP 端口注入 CSS | 只在用脚本启动时生效 |

VS Code 主题机制不能设置窗口背景图，Quest 又是 Qoder 自己的独立 renderer，所以背景图必须走第二层。**用户只点 Dock 图标时看到新配色但没有背景图，是预期行为，不是安装失败。**

## 前置条件

- macOS，已安装 Qoder（默认 `/Applications/Qoder CN.app`，英文版用 `QODER_APP_PATH` 指定）
- `jq`、`node`、`zip`、`unzip`、`sips`（系统自带）
- 可选 `cwebp`（`brew install webp`）压缩背景图；没有会自动退回 PNG
- **一张用户提供的背景图**，见下

## 背景图必须由用户提供

**不要假设自己能生成图片。** 大多数编码智能体（包括 Qoder 自带的）没有生图能力，凭空往下走会卡在这一步或者编造一个不存在的文件。

正确做法是在流程开始时就问用户要图，三条路：

1. **用户给一张**（默认路径）——本地图片路径或让他拖进来。格式随意，`prepare-background.sh` 会统一处理。
2. **你确实具备生图能力**——可以提议生成，但要先说明构图要求并让用户确认，别直接开画。
3. **用户暂时没有图**——那就**只做第一层颜色主题**，明确告诉他缺的是背景图和毛玻璃，以后补一张图随时可以加上。不要因为没图就停在原地什么都不交付。

## 流程

### 1. 先和用户确认设计，再动手

生成任何文件前，把这几件事说清楚并等确认：

- **主题名与 slug**：slug 只能是小写字母、数字、连字符，会进 DOM id、CSS 选择器和 VSIX Identity。建议 `qoder-` 前缀。
- **核心配色**：至少给出 base / surface / accent 三个颜色和整体氛围。
- **背景图**：按上一节要到图，或者确认只做第一层。拿到图后先看一眼构图——主体在右侧最好，在左侧可以用 `--flip` 镜像救回来，在正中间就得换图。详见 `references/background-art.md`。

不同皮肤必须用不同 slug，否则 VSIX 互相覆盖、注入的 style 节点互相打架。

### 2. 脚手架

```bash
./scripts/new-skin.sh <slug> "<显示名>" --desc "<描述>"
```

生成 `skins/<slug>/`，主题 JSON 从 `skins/qoder-moonlit-sakura` 继承**完整且已验证的 203 个颜色键**（含 34 个 `aicoding.*`），色值仍是月夜樱的，下一步整体改写。

### 3. 改写颜色主题

编辑 `skins/<slug>/extension/themes/<slug>-color-theme.json`。

先定义配色角色再逐组映射，不要全局搜色替换。角色定义、键分组、`aicoding.*` 键含义、语法高亮建议见 `references/color-system.md`。

**编辑器正文的对比度优先级高于背景图表现。**

### 4. 背景图

把用户给的图交给脚本处理，不要手工转格式：

```bash
./scripts/prepare-background.sh <slug> <用户的图片路径> [--flip]
```

它会统一格式（png / jpg / heic / tiff 都吃）、按需水平镜像、缩放到 1672 宽、压成 WebP 放进 `skins/<slug>/assets/`，并**丢掉 EXIF 元数据**——用户的手机照片可能带 GPS 坐标，这一步是必要的。

只做第一层（用户没给图）时跳过本步和第 5、8 步，交付到第 7 步为止，并说清楚少了什么。

构图要求和挑图标准见 `references/background-art.md`。

### 5. 调运行时 CSS

编辑 `skins/<slug>/skin.css`，主要改顶部六个变量。透明度经验值、选择器为什么这么写、Quest 页面用的 `--color-*` 设计变量见 `references/runtime-layer.md`。

`--qoder-skin-image` 由注入器写入，变量名固定不能改；`html::after` 的 `pointer-events: none` 不能删。

### 6. 静态校验

```bash
./scripts/validate.sh <slug>
```

查 JSON / Node / Shell 语法、字段一致性、`aicoding.*` 键白名单、CSS 关键约束、与基线配色的重复度、VSIX 可解压。必须全绿再往下走。

### 7. 安装颜色主题

```bash
./scripts/install-theme.sh <slug>
```

装完**要用户手动选一次**：文件 → 首选项 → 主题 → 颜色主题 → 新主题名。

### 8. 启动完整皮肤

这一步需要用户配合，**先请用户用 ⌘Q 完全退出 Qoder**（含 Quest 窗口），确认退出后再执行：

```bash
./scripts/launch-themed-qoder.sh <slug>
```

Electron 单实例机制会让已有实例吞掉 `--remote-debugging-port`。判断成功的标准不是窗口打开了，而是 `logs/<slug>-qoder.log` 里出现 `DevTools listening on ws://127.0.0.1:...`，且 `logs/<slug>-injector.log` 出现 `[已应用]`。

### 9. 实机验证

不要只声称完成。至少逐项确认：主编辑器代码可读性、文件树、终端、Diff、搜索框与建议框、AI 侧栏 / Chat、**Quest 独立窗口**、背景不拦截点击和输入。

完整清单和常见故障见 `references/troubleshooting.md`。

### 10. 恢复

```bash
./scripts/restore.sh [slug]
```

移除注入的 style 节点并停掉注入器。配色需要用户在 Qoder 里切回内置主题（如 Qoder Dark）。

## 安全边界（不可突破）

- 不修改 Qoder 应用包内任何文件，不改 `app.asar`，不重新签名。
- CDP 只绑 `127.0.0.1`，绝不绑 `0.0.0.0`。
- 注入器只连 URL 含 `vscode-app` / `vscode-file` 的 page target，不对任意网页注入。
- 图片和 CSS 只从皮肤目录读取。
- 恢复时只移除自己创建的 `qoder-skin-*-style` 节点、CSS 变量和注入器进程，不删用户配置、扩展或工作区文件。

## 目录结构

```
runtime/      cdp.mjs / injector.mjs / restore.mjs —— 皮肤无关的共享运行时
scripts/      new-skin / prepare-background / validate / package-vsix
              install-theme / launch-themed-qoder / restore
templates/    新皮肤的 skin.css、skin.json、扩展清单模板
skins/<slug>/ skin.json + skin.css + extension/ + assets/ + dist/ + screenshots/
references/   按需查阅的详细资料
```

## 版本说明

已在 **Qoder CN 1.8.1（VS Code 1.103 基础）** 上实机验证。Qoder 升级后 DOM 结构和 `aicoding.*` 键可能变化，升级后应重新跑一遍验证清单，必要时更新 `references/aicoding-keys.txt`。
