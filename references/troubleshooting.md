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

### 有配色但没有背景图

预期行为。VSIX 只负责第一层，背景图来自 CDP 注入。用户从 Dock 点开时只有配色，不代表主题装失败。

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

静态部分（`./scripts/validate.sh <slug>` 已全部覆盖）：JSON 语法、Node / Shell 语法、字段一致性、`aicoding.*` 白名单、CSS 关键约束、VSIX 可解压。

实机部分必须人工或截图确认，**不要只声称完成**：

1. 主题能被 Qoder CLI 装上。
2. 主题出现在颜色主题选择器里，且名字正确。
3. 启动日志出现 `DevTools listening`。
4. 注入日志对 Editor 和 Quest 都打印了 `[已应用]`。
5. 背景不拦截点击、输入、拖动和快捷键。
6. 逐项看可读性：代码正文、行号、文件树、终端、Diff、搜索框、建议框、AI 侧栏 / Chat、**Quest 独立窗口**。
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
