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

第二层是 `html::after`：在所有 UI 之上再画一次同一张图，用横向 `mask-image` 只让右侧主体透出来。没有这层的话，各区域不透明度一叠，人物基本看不见了。

这一层的硬约束：

- `pointer-events: none` **不能删**，否则整个界面点不动。
- `z-index` 要足够高（当前 2147483000）才能盖住工作台，但也因此绝不能拦截事件。
- `opacity` 0.25–0.32 之间比较合适，再高会压住代码。

## Quest / Chat 页面

Qoder 自定义页面不吃 VS Code 颜色键，走的是一套 `--color-*` 设计变量：

```text
--color-bg-base  --color-bg-container  --color-bg-elevated
--color-bg-layout  --color-bg-spotlight
--color-border  --color-border-secondary  --color-border-tertiary
--color-fill  --color-fill-secondary  --color-fill-tertiary
```

`skin.css` 把它们统一改写到皮肤变量上。改完必须单独打开 Quest 窗口看一眼，编辑器正常不代表 Quest 正常。

## 毛玻璃

`backdrop-filter: blur(18px) saturate(118%)` 是工作台各 part 的基线，浮层用 `blur(22px) saturate(125%)`。模糊半径再大会明显掉帧，饱和度超过 130% 会让背景图的颜色渗到 UI 上。
