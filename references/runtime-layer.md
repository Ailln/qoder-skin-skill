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
