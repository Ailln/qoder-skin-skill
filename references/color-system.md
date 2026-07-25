# 配色系统

改主题 JSON 的方法：先定义配色角色，再逐组映射到颜色键。不要在 203 个键上做全局搜色替换——那样必然会把语义色（错误红、警告黄）也一起染掉。

## 1. 先定义角色

```text
base        最深背景        编辑器正文区
surface     次级背景        侧栏、活动栏、标题栏、状态栏
elevated    浮层背景        弹窗、菜单、卡片、建议框
foreground  主文字
muted       次级文字        描述、非活动项、行号
accent      品牌色          活动项、光标、徽章、进度条
secondary   辅助强调色      函数名、链接
success / warning / error   语义色，必须保持可辨识，不要为了统一色调而牺牲
border      低对比边界
```

暗色皮肤的经验取值：base 亮度最低，surface 比 base 亮 1–3%，elevated 再亮 2–4%。三者差太小会糊成一片，差太大会破坏整体感。

## 2. 映射到 VS Code 标准键

主题 JSON 的 `colors` 按区块组织，改的时候按块推进：

| 区块 | 键前缀 | 用哪个角色 |
|---|---|---|
| 全局 | `foreground`、`focusBorder`、`errorForeground`、`textLink.*`、`badge.*`、`progressBar.*` | foreground / accent |
| 标题栏与活动栏 | `titleBar.*`、`activityBar.*`、`activityBarBadge.*` | surface + accent |
| 侧栏 | `sideBar.*`、`sideBarSectionHeader.*`、`sideBarTitle.*` | surface |
| 编辑器 | `editor.*`、`editorLineNumber.*`、`editorCursor.*`、`editorIndentGuide.*`、`editorBracketMatch.*` | base + accent |
| 标签页 | `tab.*`、`editorGroupHeader.*` | surface / base |
| 列表与树 | `list.*`、`tree.*` | 选中态用 accent 的低透明度叠加 |
| 输入与下拉 | `input.*`、`dropdown.*`、`quickInput*` | elevated |
| 面板与终端 | `panel.*`、`terminal.ansi*`、`statusBar.*` | surface；终端 16 色要独立设计 |
| Diff 与 Git | `diffEditor.*`、`gitDecoration.*`、`editorGutter.*` | success / warning / error |
| 浮层 | `editorWidget.*`、`editorSuggestWidget.*`、`editorHoverWidget.*`、`notifications.*`、`menu.*` | elevated |
| Qoder 私有 | `aicoding.*` | 见下 |

带 alpha 的键（如 `focusBorder`、`list.hoverBackground`）用 8 位十六进制 `#RRGGBBAA`。

## 3. Qoder 私有颜色键 `aicoding.*`

Qoder 在 VS Code 之外注册了一组自己的颜色，主要作用在 AI 面板、Quest 页面和 Qoder 自定义控件上。**只能用 `references/aicoding-keys.txt` 里的 34 个键**，凭名字臆造的键会被 VS Code 报为未知配置（`validate.sh` 第 5 步会拦截）。

按用途分组：

```text
品牌与强调    primaryText  primaryBg  questBrandAccent  switchCheckedBackground
              annotationUnderline  annotationHighlightBackground
按钮          buttonBackground  buttonHoverBackground  buttonForeground
文字层级      colorTextTertiary  colorTextQuaternary
语义基色      colorSuccess  colorWarning
容器背景      bgContainer  bgElevated  titleBarInputBackground  skeletonBackground
填充层级      fill  fillSecondary  fillTertiary  fillQuaternary
边框          borderTertiary
消息条        sparkError / sparkInfo / sparkSuccess / sparkWarning
              各自还有 ...Bg 和 ...Border 三件套
```

`spark*` 三件套是 AI 面板里的提示条，前景色要在自己的 `Bg` 上可读，`Border` 取两者之间的中间亮度。`fillQuaternary` 通常是极低透明度的前景色叠加（月夜樱用 `#E8E6F00A`），别当成实色。

## 4. 语法高亮

`tokenColors` 按十组给：注释、字符串、数字与常量、关键字、函数、类型与类、变量与属性、标签、属性、非法。`semanticTokenColors` 再覆盖 class / function / method / parameter / property / type / variable 等 14 项，保证语义高亮打开时不回退。

原则：

- 注释用 muted，且要明显区别于正文，但不能低到看不见。
- 关键字和函数分别用 accent 和 secondary，是代码可读性的骨架。
- 字符串和数字用同色系但不同亮度，避免和关键字撞色。
- 非法（invalid）保持醒目的红。

## 5. 自检

改完跑 `./scripts/validate.sh <slug>`。第 6 步会报「与月夜樱基线完全相同的色值有多少」——超过 20% 说明有整块配色忘了改。
