# 运行时注入层

## 为什么需要这层

VS Code 颜色主题只能填色，不能设置全窗口背景图，也管不到 Qoder 自己的独立渲染页面。所以背景图和毛玻璃必须在 Qoder 启动时打开本地 CDP 端口，再往渲染页面注入 CSS。

代价是：这层只在用 `launch-themed-qoder.sh` 启动时存在，从 Dock 点开的 Qoder 只有第一层配色。

## Qoder 的渲染页面

至少两个页面要分别处理：

```text
编辑器：.../out/vs/code/electron-browser/workbench/workbench.html
Quest： .../out/lingma/agents-window/electron-browser/agents-window.html
```

CDP 的 `/json/list` 会把它们列成 page target。Quest 不是普通 VS Code Webview，而是 Qoder 自己的 renderer——这也是为什么只做 VS Code 主题时 Quest 界面跟不上。

`runtime/cdp.mjs` 只接受 URL 含 `vscode-app` 或 `vscode-file` 的 target，其他一律不注入。这条白名单不要放宽。

注入器每 2.5 秒轮询一次，所以后开的 Editor、Chat、Quest 窗口都会自动补上，不需要重启。

## 注入契约

`runtime/injector.mjs` 对每个 target 做三件事：

1. 建（或更新）一个 `id="qoder-skin-<slug>-style"` 的 `<style>` 节点，内容是皮肤的 `skin.css`。
2. 把背景图编成 data URL 写进 `--qoder-skin-image`（这个变量名固定，CSS 里必须引用它）。
3. 打上 `data-qoder-skin="<slug>"` 标记。

`restore.mjs` 只移除 `qoder-skin-*-style` 前缀的节点，不会碰 Qoder 自己或其他扩展的样式。

因为背景图是整段 base64 塞进 CSS 变量的，图片体积直接决定注入负担——控制在几百 KB。

## skin.css 怎么调

顶部六个变量是全部调色入口：

```css
--qoder-skin-editor   编辑器正文区
--qoder-skin-side     侧栏、活动栏、标题栏、状态栏
--qoder-skin-panel    底部面板与终端
--qoder-skin-card     弹窗、菜单、建议框
--qoder-skin-border   低对比描边
--qoder-skin-shadow   浮层投影
```

透明度经验值（实测得来）：

- 编辑器低于 **0.72** 时代码可读性明显下降，0.76–0.80 是舒适区间。
- 弹窗和建议框必须比编辑器更实，**0.86–0.94**。太透会看到背景图穿透文字。
- 侧栏可以比编辑器略实一点（0.80–0.84），因为文件名字号更小。

## 两层背景的画法

第一层在 `html` 上：背景图 + 一道从左到右由深到浅的线性渐变，把左侧压暗给代码区让位。

第二层是 `html::after`：在所有 UI 之上再画一次同一张图，只让主体透出来。没有这层的话，各区域不透明度一叠，主体基本看不见了。

这一层的硬约束：

- `pointer-events: none` **不能删**，否则整个界面点不动。
- `z-index` 要足够高（当前 2147483000）才能盖住工作台，但也因此绝不能拦截事件。

### 四个可调变量

```css
--qoder-skin-art-size      /* 默认 cover，铺满整窗 */
--qoder-skin-art-position  /* 默认 center center */
--qoder-skin-art-opacity   /* 0.18–0.34，最常调的就是它 */
--qoder-skin-art-mask      /* 横向遮罩，让主体只在右侧显现 */
```

**背景图要铺满整个窗口。** `cover` 是默认也是应该保持的值——皮肤的观感来自整窗的氛围，
不是一个贴在角落的小图标。

**主体太抢、压住文字时，降 opacity，不要缩小图。** 把 `art-size` 改成 `auto 30%` 之类
确实能让文字变干净，但那样背景就不再是背景了，效果是右下角贴了个挂件，整个窗口回到纯色。
正确做法有两条，按顺序试：

1. 降 `--qoder-skin-art-opacity`。明亮高饱和的主体（吉祥物、纯色块）压到 0.18–0.26；
   深色柔和的插画可以留在 0.28–0.34。
2. 还不够就提高文字所在区域的面板不透明度——`--qoder-skin-side` 管 AI 侧栏，
   `--qoder-skin-editor` 管正文区。加 0.04 就有明显改善。

调 `art-size` 是最后手段，只在用户明确要「角落挂件」效果时才用。注意一旦不是全幅铺开，
图片自带的不透明底色就会露出矩形边界，必须同时把遮罩换成径向的从主体四周淡出：

```css
--qoder-skin-art-mask: radial-gradient(ellipse 34% 40% at 92% 88%, #000 30%, rgba(0, 0, 0, 0.45) 58%, transparent 84%);
```

### 边看边调

注入器每轮轮询会重读 `skin.css`（图片按 mtime 重读），所以改完 CSS **等 3 秒就生效，
不用重启注入器**。配合 `scripts/screenshot.sh` 就能「改 → 截图 → 看 → 再改」地收敛。
光看 CSS 数值判断不了效果，必须真的把截图打开看，一般两三轮才合适。

## Quest / Chat 页面

Qoder 自定义页面不吃 VS Code 颜色键，走的是一套自己的 `--color-*` 设计变量（Qoder CN 1.8.1 上实测共 140 个）。

**只改背景不改前景是这套皮肤方案最容易踩的坑。** VS Code 那边换主题时编辑器文字会跟着翻色，
Quest 这边不会——它的文字色是写死在 `--color-text-*` 里的浅色模式深色。你把背景压深、文字不动，
结果就是 `#141414` 的标题落在 `#110F1E` 的底上，**对比度约 1:1，字等于看不见**。

必须改的是三族，缺任何一族都有可见后果：

| 族 | 变量 | 不改的后果 |
|---|---|---|
| 背景 / 填充 / 描边 | `--color-bg-*`、`--color-fill*`、`--color-border*` | 页面还是浅色底 |
| **前景** | `--color-text`、`--color-text-base`、`--color-text-secondary/tertiary/quaternary`、`--color-popover-foreground`、`--color-accent-foreground`、`--color-muted-foreground` | **深底深字，正文不可读** |
| **`-static`** | 上面两族各自的 `*-static` 孪生变量，另加 `--color-bg-base-static`、`--color-bg-layout-static`（都是写死的 `#FFFFFF`） | Quest 左侧 Quests/Chats 列表保持白底，和右侧深色割裂 |

`-static` 是 Qoder 用来标记「不跟随主题」的一族，值全部写死成浅色。它不会因为你改了非 static 的同名变量而跟着变，
必须逐个显式改写。完整映射见 `templates/skin.css`。

### 坑一：选择器必须铺到每个 `[data-theme]` 作用域

Quest 页面的 `<html>` 是 `data-theme="light"`（workbench 那边是 `dark`），**而且页面内部还有若干
`<div data-theme="light">` 子作用域，每一个都会重新定义一整套 `--color-*`**。

只把改写挂在 `html, body` 上，根节点的变量确实变了，但子树里的组件仍然读到内层重新定义的浅色值——
表现就是「查根变量显示已生效、文字却还是黑的」。选择器必须包含 `[data-theme]`。

### 坑二：Quest 上还并存着两套 VS Code 变量

Quest 页面的 `<body>` 带的是 VS Code 浅色主题 class `.vs`，容器 `.quest-layout-mode` 上挂着完整的
`--vscode-*`（实测 2420 个）和 `--vscode-aicoding-*`。**VSIX 颜色主题只作用于 workbench renderer，
管不到 Quest**，所以这两族停留在浅色默认值，`--vscode-foreground` 就是 `#141414`。

Quest 的下拉框、分支选择器、模型选择器这些组件直接读 `--vscode-settings-dropdownForeground`
之类的变量，不改这一层，前面 `--color-*` 改得再全也没用。改写要**限定在 Quest 作用域**
（`.quest-layout-mode, body.vs`），不要波及 workbench——那边的 `--vscode-*` 由 VSIX 主题正确驱动，
覆盖它反而会把主题里精心区分的各种前景色抹平。

一句话总结 Quest 的三层：`--color-*`（Qoder 设计系统）、`--vscode-*`（VS Code 主题变量）、
`--vscode-aicoding-*`（Qoder 私有键）。三层都得改，缺一层就有一批组件是深底深字。

**语义色族刻意不改**：`--color-error*`、`--color-warning*`、`--color-info*`、`--color-success*`、`--color-diff-*`
以及 `--color-blue-bg` 这类色卡，是「浅色底 + 同色系深色字」的自洽组合。只改底不改字反而会让它们变得不可读，
整族保持原样是当前的取舍。

改完必须单独打开 Quest 窗口核对，**编辑器正常不代表 Quest 正常**——这两个页面是各自独立的 renderer。
用 `scripts/check-contrast.sh <slug>` 量化验证，不要只靠眼睛扫一遍。

想确认某个 Qoder 版本上真实存在哪些 token，直接问页面要：

```js
// 在 CDP evaluate 里跑
const cs = getComputedStyle(document.documentElement);
Array.from(cs).filter(n => n.startsWith('--color-')).map(n => `${n} = ${cs.getPropertyValue(n).trim()}`)
```

## 毛玻璃

`backdrop-filter: blur(18px) saturate(118%)` 是工作台各 part 的基线，浮层用 `blur(22px) saturate(125%)`。模糊半径再大会明显掉帧，饱和度超过 130% 会让背景图的颜色渗到 UI 上。
