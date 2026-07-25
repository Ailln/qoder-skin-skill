# 故障排查与验证清单

## 已经踩过的坑

### 启动了但没有 CDP 端口

Qoder 用 Electron 单实例机制。如果 Qoder 已经从 Dock 普通启动，再执行带 `--remote-debugging-port` 的命令，新进程只会把打开请求转交给旧实例，端口根本不会出现。

判断标准不是「窗口打开了」，而是 `logs/<slug>-qoder.log` 里必须出现：

```text
DevTools listening on ws://127.0.0.1:9333/...
```

解决：⌘Q 完全退出（包括 Quest 窗口），确认主进程结束，再跑 `launch-themed-qoder.sh`。脚本里已有 `pgrep` 检查，但用户可能在脚本跑完后又从 Dock 点开了一次。

### `open -na ... --args` 传不进调试参数

macOS 常见写法在 Qoder 1.8.1 上不能稳定把参数交给最终主进程：

```bash
open -na '/Applications/Qoder CN.app' --args --remote-debugging-port=9333   # 不可靠
```

所以启动脚本直接调用应用包内的 `Contents/MacOS/Electron`。它仍是官方签名包里的可执行文件，没有替换或改写任何程序。

### 切了主题却没变色

`workbench.colorTheme` 匹配的是主题的 **id**，不是显示名。写成 label（`"Qoder 像素猫"`）会解析
失败，然后**静默回落到默认主题**——看起来像换肤没成功，其实是设置没生效，日志里也不会报错。

用 `./scripts/apply-theme.sh <slug>` 写入，它取的是 `contributes.themes[0].id`。
排查时用 `./scripts/doctor.sh` 看当前值，或直接读实际生效的颜色：

```bash
# 主题真生效时 editorBg 应该等于你主题里的 editor.background
node runtime/screenshot.mjs --port 9333 --out /tmp/shot   # 或直接看截图
```

另外，**刚用 CLI 装好的扩展，运行中的窗口不会自动注册**，需要重载窗口或重启 Qoder。

### 应用被别的换肤方案改过

有些换肤方案（包括一些叫 `*-background`、`custom-css` 的扩展）直接改写应用包里的
`workbench.html`，插入自己的 `<style>` 和一份放宽的 CSP。后果：

- Qoder 弹「安装似乎损坏。请重新安装。」——`product.json` 里的校验和对不上了
- `codesign --verify` 报 `a sealed resource is missing or invalid`
- 它的 `body::before` 会和本 skill 注入的背景叠在一起，调什么都不对
- macOS 的 App Management 保护会拦住后续写入，于是不停弹 `EPERM: operation not permitted`

`./scripts/doctor.sh` 第 1 步会直接比对校验和并指出注入标记。要还原成原始文件：

```bash
# 期望校验和取自 product.json，删掉注入块后应当能精确匹配
jq -r '.checksums["vs/code/electron-browser/workbench/workbench.html"]' \
  "/Applications/Qoder CN.app/Contents/Resources/app/product.json"
```

删掉 `<!-- qoder-background-start -->` 到 `<!-- qoder-background-end -->` 之间的内容以及
多余空行，直到 sha256（base64、去 padding）与期望值一致。注意**写回需要终端具备
「App 管理」权限**（系统设置 → 隐私与安全性 → App 管理），否则会报 `operation not permitted`。

### 有配色但没有背景图

预期行为。VSIX 只负责第一层，背景图来自 CDP 注入。用户从 Dock 点开时只有配色，不代表主题装失败。

### 背景图主体压住文字

高饱和的大块主体（吉祥物、纯色块）铺满窗口时，会压低右侧 AI 面板的文字对比度。

**降 `--qoder-skin-art-opacity` 到 0.18–0.26，不要去缩小背景图。** 把图缩到角落确实能让
文字变干净，但那样整窗背景就没了，皮肤退化成一个角落贴纸——这不是想要的效果。
还不够就把 `--qoder-skin-side` 提高 0.04 让面板更实。

### 缩小插画后右下角出现一个方块

只有在把 `art-size` 改成非 `cover` 时才会遇到。图片自带不透明底色，一旦不是全幅铺开，
整张图的矩形边界就会露出来；横向线性遮罩只挡左右，挡不住上边缘，得换成径向遮罩。
更简单的办法是别缩小，保持 `cover`。

### 背景图在但主体几乎看不见

各区域不透明度堆到 0.90 时，背景会被遮得只剩色调。解决办法是降低编辑器和面板不透明度到 0.78 左右，再加 `html::after` 的横向遮罩单独强调右侧主体。

### 界面点不动 / 输入没反应

`html::after` 忘了 `pointer-events: none`。这层 `z-index` 极高，会吃掉所有鼠标事件。`validate.sh` 第 4 步会拦。

### 两套皮肤互相打架

两个注入器同时运行会争抢 `--qoder-skin-image` 和 style 节点。`launch-themed-qoder.sh` 会检测已有注入器并拒绝启动，先 `./scripts/restore.sh` 停掉旧的。

不同皮肤也必须用不同 slug，否则 VSIX Identity 相同会互相覆盖安装。

### 重复打包出来的 VSIX 变大 / 装不上

`zip` 默认是追加模式。`package-vsix.sh` 每次会先删旧文件再打包，如果手工执行 `zip` 记得也这么做。

## 交付前验证清单

先跑 `./scripts/doctor.sh` 排除环境问题（应用被改过、没有调试端口、多个注入器打架、主题没切）。

静态部分（`./scripts/validate.sh <slug>` 已全部覆盖）：JSON 语法、Node / Shell 语法、字段一致性、`aicoding.*` 白名单、CSS 关键约束、VSIX 可解压。

实机部分必须人工或截图确认，**不要只声称完成**：

1. 主题能被 Qoder CLI 装上。
2. 主题真的生效了——不是「设置里写了」，而是截图上颜色确实变了。
3. 启动日志出现 `DevTools listening`。
4. 注入日志对 Editor 和 Quest 都打印了 `[已应用]`。
5. 背景不拦截点击、输入、拖动和快捷键。
6. 用 `./scripts/screenshot.sh <slug>` 截图并**真的打开看**，逐项确认可读性：代码正文、行号、文件树、终端、Diff、搜索框、建议框、AI 侧栏 / Chat、**Quest 独立窗口**。
7. 跑 `./scripts/restore.sh` 后背景和毛玻璃消失，界面回到纯配色状态。
8. 在 Qoder 里切回内置主题（如 Qoder Dark），原生配色恢复正常。

## Qoder 升级之后

升级可能改变 DOM 结构和注册的颜色键。升级后：

- 重跑一遍上面的实机清单。
- 如果 Qoder 报未知配置，用新版本重新核对 `references/aicoding-keys.txt`。
- 如果毛玻璃失效或某个区域没跟上，多半是 `.monaco-workbench > .part.*` 的类名或 Quest 页面的 `--color-*` 变量变了，用 CDP 直接查一下实际 DOM。

## 卸载

```bash
./scripts/restore.sh <slug>                                    # 移除运行时注入
'/Applications/Qoder CN.app/Contents/Resources/app/bin/code' \
  --uninstall-extension <publisher>.<slug>                     # 卸载颜色主题
```
